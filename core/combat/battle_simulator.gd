class_name BattleSimulator
extends RefCounted
## Автобой без нод: используется в тестах и в симуляторе баланса
## (08-architecture.md, раздел 1 — «боевую систему можно прогнать 10 000 раз»).

const MAX_ITERATIONS := 2000

## Собирает готовое к бою состояние на открытой площадке.
static func build_state(party: Array, enemies: Array, balance: BalanceData,
		status_db: Dictionary, seed_value: int, size: int = 16) -> CombatState:
	var state := CombatState.new()
	state.balance = balance
	state.status_db = status_db
	state.rng = RngStream.new(seed_value, &"combat")
	state.grid = CombatGrid.new(size, size)
	for y: int in size:
		for x: int in size:
			state.grid.set_flags(Vector2i(x, y), 0)
	state.light = LightService.new(state.grid, balance.light_bright_cells, balance.light_dim_cells)
	var y_party := 2
	var y_enemy := size - 3
	var i := 0
	for a: CombatActor in party:
		a.cell = Vector2i(2 + i * 2, y_party)
		state.add_actor(a)
		i += 1
	i = 0
	for e: CombatActor in enemies:
		e.cell = Vector2i(2 + i * 2, y_enemy)
		state.add_actor(e)
		i += 1
	# Факел у отряда: без света бой шёл бы с помехой у всех.
	state.light.add_source(party[0].cell if not party.is_empty() else Vector2i(1, 1),
		balance.light_bright_cells, balance.light_dim_cells)
	return state

## Прогоняет бой до конца. Обе стороны ведёт UtilityAI.
static func run(state: CombatState, max_rounds: int = 40) -> Dictionary:
	var engine := CombatEngine.new(state)
	engine.start()
	var iterations := 0
	while state.phase != CombatState.PHASE_ENDED and iterations < MAX_ITERATIONS:
		iterations += 1
		if state.round_number > max_rounds:
			break
		var actor := state.current_actor()
		if actor == null:
			break
		if not actor.can_act():
			engine.end_turn()
			continue
		_take_turn(engine, state, actor)
		if state.phase == CombatState.PHASE_ENDED:
			break
		engine.end_turn()
	return {
		"victory": state.victory,
		"rounds": state.round_number,
		"iterations": iterations,
		"timeout": iterations >= MAX_ITERATIONS or state.round_number > max_rounds,
		"log": state.log_lines,
		"party_hp": _team_hp(state, CombatActor.TEAM_PARTY),
		"enemy_hp": _team_hp(state, CombatActor.TEAM_ENEMY),
	}

static func _take_turn(engine: CombatEngine, state: CombatState, actor: CombatActor) -> void:
	# Заклинатель сначала пробует полезное заклинание, иначе бьёт оружием.
	if _try_cast(engine, state, actor):
		return
	var plan := UtilityAI.plan_turn(state, actor)
	for step: Dictionary in plan:
		if state.phase == CombatState.PHASE_ENDED:
			return
		match String(step.get("kind", "")):
			"move":
				engine.submit(MoveAction.resolve(state, actor, step["cell"]))
			"attack":
				engine.submit(AttackAction.resolve(state, actor, step["target"], step["attack"]))

static func _try_cast(engine: CombatEngine, state: CombatState, actor: CombatActor) -> bool:
	if actor.spells.is_empty() or actor.action_left <= 0:
		return false
	var enemies := state.team_actors(
		CombatActor.TEAM_PARTY if actor.team == CombatActor.TEAM_ENEMY else CombatActor.TEAM_ENEMY)
	var wounded := _most_wounded(state, actor.team)
	for spell_id: StringName in actor.spells:
		var spell: SpellData = state.spell_db.get(spell_id, null)
		if spell == null:
			continue
		if not spell.heal_dice.is_empty():
			if wounded == null or wounded.hp_ratio() > 0.55:
				continue
			var r := SpellAction.resolve(state, actor, spell, wounded.cell)
			if r.ok:
				engine.submit(r)
				return true
			continue
		if spell.damage_dice.is_empty() or enemies.is_empty():
			continue
		var target: CombatActor = enemies[0]
		for e: CombatActor in enemies:
			if e.hp < target.hp:
				target = e
		var result := SpellAction.resolve(state, actor, spell, target.cell)
		if result.ok:
			engine.submit(result)
			return true
	return false

static func _most_wounded(state: CombatState, team: int) -> CombatActor:
	var best: CombatActor = null
	for a: CombatActor in state.team_actors(team):
		if a.is_dead:
			continue
		if best == null or a.hp_ratio() < best.hp_ratio():
			best = a
	return best

static func _team_hp(state: CombatState, team: int) -> int:
	var total := 0
	for a: CombatActor in state.team_actors(team, false):
		total += maxi(0, a.hp)
	return total
