class_name AbilityAction
extends RefCounted
## Классовые способности героев (03-characters.md, раздел 2).
## Список способностей и их стоимость — в data/abilities.json, здесь только эффекты.

static func uses_left(actor: CombatActor, spec: AbilityData) -> int:
	if spec.uses_per_rest <= 0:
		return 99
	var used: Dictionary = actor.flags.get(&"ability_uses", {})
	return maxi(0, spec.uses_per_rest - int(used.get(spec.id, 0)))

static func _consume(actor: CombatActor, spec: AbilityData, result: ActionResult) -> bool:
	if spec.cost == &"action":
		if actor.action_left <= 0:
			return false
		actor.action_left -= 1
	elif spec.cost == &"bonus":
		if actor.bonus_left <= 0:
			return false
		actor.bonus_left -= 1
	elif spec.cost == &"reaction":
		if actor.reaction_left <= 0:
			return false
		actor.reaction_left -= 1
	if spec.uses_per_rest > 0:
		var used: Dictionary = actor.flags.get(&"ability_uses", {})
		used[spec.id] = int(used.get(spec.id, 0)) + 1
		actor.flags[&"ability_uses"] = used
	result.resources_spent[spec.cost] = 1
	return true

static func resolve(state: CombatState, actor: CombatActor, spec: AbilityData,
		target: CombatActor) -> ActionResult:
	var r := ActionResult.new()
	r.actor_id = actor.id
	r.action_id = spec.id
	if uses_left(actor, spec) <= 0:
		return ActionResult.failure(actor.id, spec.id, "Способность израсходована до отдыха")
	if not _consume(actor, spec, r):
		return ActionResult.failure(actor.id, spec.id, "Нет свободного действия")
	if target != null:
		r.targets = [target.id]
	match spec.id:
		&"taunt":
			_taunt(state, actor, target, r)
		&"second_wind":
			var roll := Dice.roll("1d10+%d" % actor.level, state.rng)
			var healed := DamageCalc.heal(actor, int(roll["total"]))
			r.effects.append({"kind": "heal", "target": String(actor.id), "amount": healed})
			r.add_log("Второе дыхание: %s восстанавливает %d HP" % [actor.display_name, healed])
		&"shield_wall":
			var e := StatusEngine.apply(state, actor, &"shield_wall_buff", actor.id)
			if not e.is_empty():
				r.status_events.append(e)
			actor.movement_left = 0
			r.add_log("%s поднимает Стену щитов" % actor.display_name)
		&"crushing_blow":
			_crushing_blow(state, actor, target, r)
		&"stealth":
			_stealth(state, actor, r)
		&"aimed_shot":
			actor.flags[&"aimed"] = true
			r.add_log("%s прицеливается: +2 к следующей дальней атаке" % actor.display_name)
		&"short_step":
			actor.flags[&"disengaging"] = true
			actor.movement_left = maxi(actor.movement_left, 3)
			r.add_log("%s делает Отскок" % actor.display_name)
		_:
			r.add_log("%s использует «%s»" % [actor.display_name, spec.display_name])
	return r

static func _taunt(state: CombatState, actor: CombatActor, target: CombatActor,
		r: ActionResult) -> void:
	if target == null or CombatGrid.distance(actor.cell, target.cell) > 3:
		r.add_log("Провокация: цель слишком далеко")
		return
	var save := Resolver.saving_throw(state.rng, target, Stats.WIS, actor.spell_save_dc())
	r.rolls.append(save)
	r.add_log("Провокация против %s: %s" % [target.display_name, save["text"]])
	if bool(save["success"]):
		return
	target.flags[&"taunted_by"] = String(actor.id)
	var e := StatusEngine.apply(state, target, &"taunted", actor.id)
	if not e.is_empty():
		r.status_events.append(e)

static func _crushing_blow(state: CombatState, actor: CombatActor, target: CombatActor,
		r: ActionResult) -> void:
	if target == null or actor.attacks.is_empty():
		r.add_log("Сокрушающий удар: нет цели")
		return
	var attack: AttackData = actor.attacks[0].duplicate()
	attack.attack_bonus -= 2
	attack.display_name = "Сокрушающий удар"
	var sub := AttackAction.resolve(state, actor, target, attack, true)
	r.rolls.append_array(sub.rolls)
	r.damage_events.append_array(sub.damage_events)
	r.status_events.append_array(sub.status_events)
	r.log_lines.append_array(sub.log_lines)
	if sub.total_damage() > 0:
		var save := Resolver.saving_throw(state.rng, target, Stats.STR, actor.spell_save_dc())
		r.rolls.append(save)
		if not bool(save["success"]):
			var e := StatusEngine.apply(state, target, &"prone_push", actor.id)
			if not e.is_empty():
				r.status_events.append(e)
			r.add_log("  %s сбит с ног" % target.display_name)

static func _stealth(state: CombatState, actor: CombatActor, r: ActionResult) -> void:
	var dark := state.light.level_at(actor.cell) == LightService.DARK
	var mode := Resolver.ADV if dark else Resolver.NONE
	var best_passive := 10
	for e: CombatActor in state.team_actors(CombatActor.TEAM_ENEMY):
		best_passive = maxi(best_passive, 10 + e.stat_mod(Stats.WIS) + e.proficiency)
	var check := Resolver.ability_check(state.rng, actor, Stats.DEX, best_passive, true, mode)
	r.rolls.append(check)
	r.add_log("Скрытность: %s" % check["text"])
	if bool(check["success"]):
		actor.flags[&"hidden"] = true
