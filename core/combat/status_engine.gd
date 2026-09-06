class_name StatusEngine
extends RefCounted
## Наложение, стаканье, тик и снятие статусов (02-combat.md, раздел 7).

## Накладывает статус. Возвращает событие для ActionResult (может быть пустым при иммунитете).
static func apply(state: CombatState, target: CombatActor, status_id: StringName,
		source: StringName = &"", dc: int = 0, stacks: int = 1) -> Dictionary:
	var data: StatusData = state.status_db.get(status_id, null)
	if data == null:
		return {}
	if target.status_immunities.has(status_id):
		return {"target": String(target.id), "status": String(status_id), "applied": false,
			"immune": true}
	for tag: StringName in data.tags:
		if target.status_immunities.has(tag):
			return {"target": String(target.id), "status": String(status_id),
				"applied": false, "immune": true}
	var existing := target.get_status(status_id)
	if existing != null:
		if data.stackable:
			existing.stacks = mini(data.max_stacks, existing.stacks + stacks)
		existing.rounds_left = maxi(existing.rounds_left, data.duration_rounds)
	else:
		var eff := StatusEffect.new(data, source, dc)
		eff.stacks = mini(data.max_stacks, stacks)
		target.statuses.append(eff)
	return {"target": String(target.id), "status": String(status_id), "applied": true,
		"stacks": target.get_status(status_id).stacks, "name": data.display_name}

static func remove(target: CombatActor, status_id: StringName) -> Dictionary:
	for i: int in target.statuses.size():
		if target.statuses[i].id() == status_id:
			var name := target.statuses[i].data.display_name
			target.statuses.remove_at(i)
			return {"target": String(target.id), "status": String(status_id),
				"removed": true, "name": name}
	return {}

## Снимает до count дебаффов (эффект «Очищение»).
static func cleanse(target: CombatActor, count: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var removed := 0
	for i: int in range(target.statuses.size() - 1, -1, -1):
		if removed >= count:
			break
		var s := target.statuses[i]
		if s.data != null and s.data.is_debuff:
			events.append({"target": String(target.id), "status": String(s.id()),
				"removed": true, "name": s.data.display_name})
			target.statuses.remove_at(i)
			removed += 1
	return events

## Снятие статусов, которые гасятся уроном определённого типа (заморозка от огня).
static func on_damage_taken(target: CombatActor, type: StringName) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i: int in range(target.statuses.size() - 1, -1, -1):
		var s := target.statuses[i]
		if s.data != null and s.data.removed_by_damage_types.has(type):
			events.append({"target": String(target.id), "status": String(s.id()),
				"removed": true, "name": s.data.display_name})
			target.statuses.remove_at(i)
	return events

## Тик в начале хода: периодический урон.
static func tick_start_of_turn(state: CombatState, actor: CombatActor, result: ActionResult) -> void:
	for s: StatusEffect in actor.statuses.duplicate():
		if s.data == null or s.data.tick_dice.is_empty():
			continue
		var times := s.stacks if s.data.tick_per_stack else 1
		var total := 0
		for i: int in times:
			total += int(Dice.roll(s.data.tick_dice, state.rng)["total"])
		var event := DamageCalc.deal(actor, total, s.data.tick_damage_type, false, state.balance)
		result.damage_events.append(event)
		result.add_log("%s: %s от эффекта «%s»" % [actor.display_name,
			DamageCalc.describe(event), s.data.display_name])

## Тик в конце хода: спасброски на снятие и уменьшение длительности.
static func tick_end_of_turn(state: CombatState, actor: CombatActor, result: ActionResult) -> void:
	for i: int in range(actor.statuses.size() - 1, -1, -1):
		var s := actor.statuses[i]
		if s.data == null:
			continue
		if s.data.save_stat != &"" and s.save_dc > 0:
			var roll := Resolver.saving_throw(state.rng, actor, s.data.save_stat, s.save_dc)
			result.rolls.append(roll)
			if bool(roll["success"]):
				result.status_events.append({"target": String(actor.id),
					"status": String(s.id()), "removed": true, "name": s.data.display_name})
				result.add_log("%s стряхивает «%s»" % [actor.display_name, s.data.display_name])
				actor.statuses.remove_at(i)
				continue
		s.rounds_left -= 1
		if s.rounds_left <= 0:
			result.status_events.append({"target": String(actor.id), "status": String(s.id()),
				"removed": true, "name": s.data.display_name})
			actor.statuses.remove_at(i)

## Снятие эффектов с меткой end_of_combat.
static func clear_after_combat(actor: CombatActor) -> void:
	for i: int in range(actor.statuses.size() - 1, -1, -1):
		var s := actor.statuses[i]
		if s.data == null or not s.data.persists_after_combat:
			actor.statuses.remove_at(i)
