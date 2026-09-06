class_name SpellAction
extends RefCounted
## Сотворение заклинания (02-combat.md, раздел 6).

static func has_slot(actor: CombatActor, level: int) -> bool:
	if level <= 0:
		return true
	for i: int in range(level - 1, actor.spell_slots.size()):
		if actor.spell_slots[i] > 0:
			return true
	return false

static func spend_slot(actor: CombatActor, level: int) -> int:
	if level <= 0:
		return 0
	for i: int in range(level - 1, actor.spell_slots.size()):
		if actor.spell_slots[i] > 0:
			actor.spell_slots[i] -= 1
			return i + 1
	return 0

## Кого накрывает форма заклинания.
static func gather_targets(state: CombatState, caster: CombatActor, spell: SpellData,
		point: Vector2i) -> Array[CombatActor]:
	var out: Array[CombatActor] = []
	var candidates := state.all_actors()
	for a: CombatActor in candidates:
		if not a.is_alive():
			continue
		if spell.target_team == &"enemy" and a.team == caster.team:
			continue
		if spell.target_team == &"ally" and a.team != caster.team:
			continue
		if spell.target_team == &"self" and a.id != caster.id:
			continue
		match spell.shape:
			&"single":
				if a.cell == point:
					out.append(a)
			&"self":
				if a.id == caster.id:
					out.append(a)
			&"sphere":
				if CombatGrid.distance(point, a.cell) <= spell.shape_size:
					out.append(a)
			&"cone":
				if _in_cone(caster.cell, point, a.cell, spell.shape_size):
					out.append(a)
			&"line":
				if state.grid.line_cells(caster.cell, point).has(a.cell):
					out.append(a)
	if spell.max_targets > 0 and out.size() > spell.max_targets and spell.shape == &"single":
		out.resize(spell.max_targets)
	return out

static func _in_cone(origin: Vector2i, aim: Vector2i, cell: Vector2i, length: int) -> bool:
	if CombatGrid.distance(origin, cell) > length or cell == origin:
		return false
	var dir := Vector2(aim - origin)
	var to := Vector2(cell - origin)
	if dir.length() < 0.01:
		return false
	return dir.normalized().dot(to.normalized()) >= 0.5

static func resolve(state: CombatState, caster: CombatActor, spell: SpellData,
		point: Vector2i, slot_level: int = -1) -> ActionResult:
	var result := ActionResult.new()
	result.actor_id = caster.id
	result.action_id = spell.id
	var level := spell.level if slot_level < 0 else maxi(spell.level, slot_level)
	if spell.cast_time == &"action" and caster.action_left <= 0:
		return ActionResult.failure(caster.id, spell.id, "Действие уже потрачено")
	if spell.cast_time == &"bonus" and caster.bonus_left <= 0:
		return ActionResult.failure(caster.id, spell.id, "Бонусное действие потрачено")
	if not has_slot(caster, level):
		return ActionResult.failure(caster.id, spell.id, "Нет свободной ячейки")
	if spell.shape != &"self" and CombatGrid.distance(caster.cell, point) > spell.range_cells:
		return ActionResult.failure(caster.id, spell.id, "Слишком далеко")
	if spell.shape != &"self" and not state.grid.has_line_of_sight(caster.cell, point):
		return ActionResult.failure(caster.id, spell.id, "Нет линии видимости")
	var targets := gather_targets(state, caster, spell, point)
	if targets.is_empty() and spell.shape == &"single":
		return ActionResult.failure(caster.id, spell.id, "Нет цели")
	if spell.cast_time == &"action":
		caster.action_left -= 1
		result.resources_spent[&"action"] = 1
	elif spell.cast_time == &"bonus":
		caster.bonus_left -= 1
		result.resources_spent[&"bonus"] = 1
	var used := spend_slot(caster, level)
	if used > 0:
		result.resources_spent[&"slot"] = used
	if spell.concentration:
		caster.flags[&"concentration"] = String(spell.id)
	result.add_log("%s творит «%s»%s" % [caster.display_name, spell.display_name,
		(" (ячейка %d ур.)" % used) if used > 0 else ""])
	for t: CombatActor in targets:
		result.targets.append(t.id)
		_apply_to_target(state, caster, spell, t, level, result)
	return result

static func _apply_to_target(state: CombatState, caster: CombatActor, spell: SpellData,
		target: CombatActor, level: int, result: ActionResult) -> void:
	var crit := false
	var halved := false
	if spell.attack_roll:
		var mode: int = int(AttackAction.compute_mode(state, caster, target,
			_pseudo_attack(spell))["mode"])
		var bonus := caster.proficiency + caster.stat_mod(caster.casting_stat) \
			+ int(caster.modifier(&"attack"))
		var roll := Resolver.attack_roll(state.rng, bonus, target.effective_ac(), int(mode),
			caster.crit_threshold(state.balance.crit_threshold), spell.display_name)
		result.rolls.append(roll)
		result.add_log("  по %s: %s" % [target.display_name, roll["text"]])
		if not bool(roll["hit"]):
			return
		crit = bool(roll["crit"])
	elif spell.save_stat != &"":
		var save := Resolver.saving_throw(state.rng, target, spell.save_stat, caster.spell_save_dc())
		result.rolls.append(save)
		result.add_log("  %s: %s" % [target.display_name, save["text"]])
		if bool(save["success"]):
			if not spell.save_for_half:
				return
			halved = true
	if not spell.damage_dice.is_empty():
		var dice := spell.damage_dice
		var extra_levels := level - spell.level
		if extra_levels > 0 and not spell.upcast_dice.is_empty():
			for i: int in extra_levels:
				dice += "+" + spell.upcast_dice
		var roll := Dice.roll(dice, state.rng, crit)
		var amount: int = int(roll["total"])
		if halved:
			amount = int(floor(amount / 2.0))
		if state.dev_damage > 0 and caster.is_hero:
			amount = state.dev_damage
		var event := DamageCalc.deal(target, amount, spell.damage_type, crit, state.balance)
		result.damage_events.append(event)
		result.add_log("  урон: %s" % DamageCalc.describe(event))
		for e: Dictionary in StatusEngine.on_damage_taken(target, spell.damage_type):
			result.status_events.append(e)
	if not spell.heal_dice.is_empty():
		var roll := Dice.roll(spell.heal_dice, state.rng)
		var amount: int = int(roll["total"])
		if spell.heal_adds_casting_mod:
			amount += caster.stat_mod(caster.casting_stat)
		var healed := DamageCalc.heal(target, amount)
		result.effects.append({"kind": "heal", "target": String(target.id), "amount": healed})
		result.add_log("  восстановлено %d HP у %s" % [healed, target.display_name])
	if spell.remove_status_count > 0:
		for e: Dictionary in StatusEngine.cleanse(target, spell.remove_status_count):
			result.status_events.append(e)
			result.add_log("  снят статус: %s" % e.get("name", ""))
	if spell.apply_status != &"":
		var e := StatusEngine.apply(state, target, spell.apply_status, caster.id,
			caster.spell_save_dc())
		if not e.is_empty():
			result.status_events.append(e)

static func _pseudo_attack(spell: SpellData) -> AttackData:
	var a := AttackData.new()
	a.range_cells = spell.range_cells
	a.display_name = spell.display_name
	return a
