class_name CombatEngine
extends RefCounted
## Машина состояний боя (08-architecture.md, раздел 6). Логика полностью разрешает
## действие и отдаёт ActionResult; представление только проигрывает его.

signal round_started(number: int)
signal turn_started(actor_id: StringName)
signal action_resolved(result: ActionResult)
signal combat_ended(victory: bool)

var state: CombatState

func _init(combat_state: CombatState) -> void:
	state = combat_state

## Бросок инициативы и первый ход (02-combat.md, раздел 2.1).
func start() -> void:
	var entries: Array = []
	for a: CombatActor in state.all_actors():
		var roll := Resolver.roll_d20(state.rng)
		var value: int = int(roll["natural"]) + a.stat_mod(Stats.DEX) + int(a.modifier(&"initiative"))
		entries.append({"id": a.id, "value": value, "dex": a.stat(Stats.DEX),
			"tie": state.rng.randi_range(0, 999)})
		state.add_log("%s: инициатива d20(%d) + ЛОВ = %d" % [a.display_name, roll["natural"], value])
	entries.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["value"] != y["value"]:
			return x["value"] > y["value"]
		if x["dex"] != y["dex"]:
			return x["dex"] > y["dex"]
		return x["tie"] > y["tie"])
	state.initiative.clear()
	for e: Dictionary in entries:
		state.initiative.append(e["id"])
	state.turn_index = 0
	state.round_number = 1
	state.phase = CombatState.PHASE_TURN
	round_started.emit(1)
	_start_turn()

func current_actor() -> CombatActor:
	return state.current_actor()

## Начало хода: тик статусов, спасброски от смерти, обновление ресурсов.
func _start_turn() -> void:
	if _check_end():
		return
	var actor := state.current_actor()
	var guard := 0
	while actor != null and (not actor.is_alive()) and guard < state.initiative.size() + 1:
		_advance_index()
		actor = state.current_actor()
		guard += 1
	if actor == null or _check_end():
		return
	state.light.clear_cache()
	var result := ActionResult.new()
	result.actor_id = actor.id
	result.action_id = &"turn_start"
	actor.begin_turn(actor.effective_speed())
	if actor.is_down:
		_death_save(actor, result)
		action_resolved.emit(result)
		for line: String in result.log_lines:
			state.add_log(line)
		end_turn()
		return
	StatusEngine.tick_start_of_turn(state, actor, result)
	for line: String in result.log_lines:
		state.add_log(line)
	action_resolved.emit(result)
	if _check_end():
		return
	if not actor.can_act():
		state.add_log("%s пропускает ход" % actor.display_name)
		end_turn()
		return
	turn_started.emit(actor.id)

func _death_save(actor: CombatActor, result: ActionResult) -> void:
	if bool(actor.flags.get(&"stable", false)):
		result.add_log("%s стабилизирован" % actor.display_name)
		return
	var roll := Resolver.death_save(state.rng, state.balance.death_save_dc)
	result.rolls.append(roll)
	result.add_log("%s: %s" % [actor.display_name, roll["text"]])
	var natural: int = int(roll["natural"])
	if natural == 20:
		actor.is_down = false
		actor.hp = 1
		actor.death_successes = 0
		actor.death_failures = 0
		result.add_log("  %s поднимается с 1 HP" % actor.display_name)
		return
	if natural == 1:
		actor.death_failures += 2
	elif bool(roll["success"]):
		actor.death_successes += 1
	else:
		actor.death_failures += 1
	if actor.death_failures >= state.balance.death_saves_to_die:
		actor.is_dead = true
		result.effects.append({"kind": "death", "target": String(actor.id)})
		result.add_log("  %s погибает" % actor.display_name)
	elif actor.death_successes >= state.balance.death_saves_to_stable:
		actor.flags[&"stable"] = true
		result.add_log("  %s стабилизируется" % actor.display_name)

## Завершение хода и переход к следующему актёру.
func end_turn() -> void:
	var actor := state.current_actor()
	if actor != null:
		var result := ActionResult.new()
		result.actor_id = actor.id
		result.action_id = &"turn_end"
		StatusEngine.tick_end_of_turn(state, actor, result)
		for line: String in result.log_lines:
			state.add_log(line)
		if not result.rolls.is_empty() or not result.status_events.is_empty():
			action_resolved.emit(result)
	if _check_end():
		return
	_advance_index()
	_start_turn()

func _advance_index() -> void:
	state.turn_index += 1
	if state.turn_index >= state.initiative.size():
		state.turn_index = 0
		state.round_number += 1
		state.light.clear_cache()
		round_started.emit(state.round_number)

## Единая точка применения результата: концентрация, мораль, конец боя.
func submit(result: ActionResult) -> ActionResult:
	if not result.ok:
		return result
	for line: String in result.log_lines:
		state.add_log(line)
	_check_concentration(result)
	_check_morale()
	action_resolved.emit(result)
	_check_end()
	return result

func _check_concentration(result: ActionResult) -> void:
	for event: Dictionary in result.damage_events:
		var target := state.get_actor(StringName(event.get("target", "")))
		if target == null or not target.flags.has(&"concentration"):
			continue
		var dc := maxi(10, int(floor(int(event.get("amount", 0)) / 2.0)))
		var save := Resolver.saving_throw(state.rng, target, Stats.CON, dc)
		state.add_log("%s удерживает концентрацию: %s" % [target.display_name, save["text"]])
		if not bool(save["success"]):
			target.flags.erase(&"concentration")

## Бегство при низком боевом духе (02-combat.md, раздел 2.4).
func _check_morale() -> void:
	for a: CombatActor in state.team_actors(CombatActor.TEAM_ENEMY):
		if a.morale_threshold <= 0.0 or a.hp_ratio() > a.morale_threshold:
			continue
		var save := Resolver.saving_throw(state.rng, a, Stats.WIS, 12)
		if not bool(save["success"]):
			a.has_fled = true
			state.add_log("%s бежит с поля боя" % a.display_name)

func _check_end() -> bool:
	if state.phase == CombatState.PHASE_ENDED:
		return true
	var enemies := state.team_actors(CombatActor.TEAM_ENEMY)
	var party_alive := false
	for a: CombatActor in state.team_actors(CombatActor.TEAM_PARTY):
		if not a.is_down:
			party_alive = true
			break
	if enemies.is_empty() or not party_alive:
		state.phase = CombatState.PHASE_ENDED
		state.victory = enemies.is_empty() and party_alive
		for a: CombatActor in state.all_actors():
			StatusEngine.clear_after_combat(a)
		combat_ended.emit(state.victory)
		return true
	return false
