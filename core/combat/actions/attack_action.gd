class_name AttackAction
extends RefCounted
## Атака оружием или естественным оружием врага (02-combat.md, разделы 3 и 4).

## Собирает источники преимущества и помехи (02-combat.md, раздел 3.2).
static func compute_mode(state: CombatState, actor: CombatActor, target: CombatActor,
		attack: AttackData) -> Dictionary:
	var adv := 0
	var dis := 0
	var notes: Array[String] = []
	var ranged := attack.range_cells > 1
	if not state.light.can_see(actor, target.cell, state.balance.darkvision_cells):
		dis += 1
		notes.append("цель не видна")
	if state.light.level_at(actor.cell) == LightService.DARK and not actor.darkvision:
		dis += 1
		notes.append("атакующий в темноте")
	if actor.has_flag_status(&"attacks_have_disadvantage"):
		dis += 1
		notes.append("статус")
	if target.has_flag_status(&"incoming_have_advantage"):
		adv += 1
		notes.append("цель обездвижена")
	if target.is_down:
		adv += 1
		notes.append("цель при смерти")
	if bool(target.flags.get(&"dodging", false)):
		dis += 1
		notes.append("цель уклоняется")
	if bool(actor.flags.get(&"hidden", false)):
		adv += 1
		notes.append("атака из скрытности")
	if bool(actor.flags.get(&"helped", false)):
		adv += 1
		notes.append("помощь союзника")
	if not ranged and state.adjacent_enemies_of(target) >= state.balance.flanking_requires:
		adv += 1
		notes.append("окружение")
	if ranged and state.adjacent_enemies_of(actor) > 0:
		dis += 1
		notes.append("стрельба в упор")
	return {"mode": Resolver.resolve_mode(adv, dis), "notes": notes}

static func attack_bonus(actor: CombatActor, attack: AttackData) -> int:
	var bonus := attack.attack_bonus
	if attack.attack_stat != &"":
		bonus += actor.stat_mod(attack.attack_stat)
	if attack.uses_proficiency:
		bonus += actor.proficiency
	return bonus + int(actor.modifier(&"attack"))

static func target_ac(state: CombatState, actor: CombatActor, target: CombatActor,
		attack: AttackData) -> int:
	var ac := target.effective_ac()
	if attack.range_cells > 1:
		ac += state.grid.cover_bonus(actor.cell, target.cell,
			state.balance.cover_half_ac, state.balance.cover_three_quarter_ac)
	return ac

static func resolve(state: CombatState, actor: CombatActor, target: CombatActor,
		attack: AttackData, free: bool = false) -> ActionResult:
	var result := ActionResult.new()
	result.actor_id = actor.id
	result.action_id = &"attack"
	result.targets = [target.id]
	if CombatGrid.distance(actor.cell, target.cell) > attack.range_cells:
		return ActionResult.failure(actor.id, &"attack", "Цель вне досягаемости")
	if attack.range_cells > 1 and not state.grid.has_line_of_sight(actor.cell, target.cell):
		return ActionResult.failure(actor.id, &"attack", "Нет линии видимости")
	if not free:
		if actor.action_left <= 0:
			return ActionResult.failure(actor.id, &"attack", "Действие уже потрачено")
		actor.action_left -= 1
		result.resources_spent[&"action"] = 1
	var mode_info := compute_mode(state, actor, target, attack)
	var ac := target_ac(state, actor, target, attack)
	var crit_at := actor.crit_threshold(state.balance.crit_threshold)
	# Паралич: ближняя атака по цели — автокрит (02-combat.md, раздел 7).
	var auto_crit := attack.range_cells <= 1 and target.has_flag_status(&"incoming_melee_auto_crit")
	var roll := Resolver.attack_roll(state.rng, attack_bonus(actor, attack), ac,
		int(mode_info["mode"]), crit_at, attack.display_name)
	if auto_crit and bool(roll["hit"]):
		roll["crit"] = true
	result.rolls.append(roll)
	var notes: Array = mode_info["notes"]
	var suffix := (" (" + ", ".join(notes) + ")") if not notes.is_empty() else ""
	result.add_log("%s атакует %s: %s%s" % [actor.display_name, target.display_name,
		roll["text"], suffix])
	actor.flags.erase(&"helped")
	actor.flags.erase(&"hidden")
	if not bool(roll["hit"]):
		result.effects.append({"kind": "miss", "target": String(target.id)})
		return result
	_apply_damage(state, actor, target, attack, bool(roll["crit"]), result)
	_apply_on_hit(state, actor, target, attack, result)
	return result

static func _apply_damage(state: CombatState, actor: CombatActor, target: CombatActor,
		attack: AttackData, crit: bool, result: ActionResult) -> void:
	var roll := Dice.roll(attack.damage_dice, state.rng, crit)
	var total: int = int(roll["total"])
	if attack.adds_stat_to_damage and attack.attack_stat != &"":
		total += actor.stat_mod(attack.attack_stat)
	total += int(actor.modifier(&"damage"))
	var event := DamageCalc.deal(target, maxi(0, total), attack.damage_type, crit, state.balance)
	result.damage_events.append(event)
	result.add_log("  урон: %s" % DamageCalc.describe(event))
	for e: Dictionary in StatusEngine.on_damage_taken(target, attack.damage_type):
		result.status_events.append(e)
	_bonus_damage(state, actor, target, crit, result)
	if bool(event.get("killed", false)):
		result.add_log("  %s повержен" % target.display_name)
	elif bool(event.get("downed", false)):
		result.add_log("  %s при смерти" % target.display_name)

static func _bonus_damage(state: CombatState, actor: CombatActor, target: CombatActor,
		crit: bool, result: ActionResult) -> void:
	var extra: Array = actor.flags.get(&"bonus_damage_dice", [])
	for entry: Dictionary in extra:
		var roll := Dice.roll(String(entry.get("dice", "1d4")), state.rng, crit)
		var event := DamageCalc.deal(target, int(roll["total"]),
			StringName(entry.get("type", "fire")), crit, state.balance)
		result.damage_events.append(event)
		result.add_log("  доп. урон: %s" % DamageCalc.describe(event))

static func _apply_on_hit(state: CombatState, actor: CombatActor, target: CombatActor,
		attack: AttackData, result: ActionResult) -> void:
	if attack.on_hit_status == &"" or not target.is_alive():
		return
	var dc := attack.on_hit_status_dc
	if attack.save_stat != &"" and dc > 0:
		var save := Resolver.saving_throw(state.rng, target, attack.save_stat, dc)
		result.rolls.append(save)
		result.add_log("  " + String(save["text"]))
		if bool(save["success"]):
			return
	var event := StatusEngine.apply(state, target, attack.on_hit_status, actor.id, dc)
	if not event.is_empty():
		result.status_events.append(event)
		if bool(event.get("applied", false)):
			result.add_log("  наложен статус: %s" % event.get("name", ""))
