class_name SimpleActions
extends RefCounted
## Рывок, Уклонение, Отход, Помощь, Толчок, Стабилизация, расходники
## (02-combat.md, раздел 5).

static func _spend(actor: CombatActor, kind: StringName, result: ActionResult) -> bool:
	if kind == &"action":
		if actor.action_left <= 0:
			return false
		actor.action_left -= 1
	elif kind == &"bonus":
		if actor.bonus_left <= 0:
			return false
		actor.bonus_left -= 1
	result.resources_spent[kind] = 1
	return true

static func _make(actor: CombatActor, id: StringName) -> ActionResult:
	var r := ActionResult.new()
	r.actor_id = actor.id
	r.action_id = id
	return r

static func dash(actor: CombatActor) -> ActionResult:
	var r := _make(actor, &"dash")
	if not _spend(actor, &"action", r):
		return ActionResult.failure(actor.id, &"dash", "Действие уже потрачено")
	actor.movement_left += actor.effective_speed()
	r.add_log("%s совершает Рывок (+%d кл.)" % [actor.display_name, actor.effective_speed()])
	return r

static func dodge(actor: CombatActor) -> ActionResult:
	var r := _make(actor, &"dodge")
	if not _spend(actor, &"action", r):
		return ActionResult.failure(actor.id, &"dodge", "Действие уже потрачено")
	actor.flags[&"dodging"] = true
	r.add_log("%s уклоняется: атаки по нему с помехой" % actor.display_name)
	return r

static func disengage(actor: CombatActor) -> ActionResult:
	var r := _make(actor, &"disengage")
	if not _spend(actor, &"action", r):
		return ActionResult.failure(actor.id, &"disengage", "Действие уже потрачено")
	actor.flags[&"disengaging"] = true
	r.add_log("%s отходит: движение не провоцирует атак" % actor.display_name)
	return r

static func help(actor: CombatActor, ally: CombatActor) -> ActionResult:
	var r := _make(actor, &"help")
	if CombatGrid.distance(actor.cell, ally.cell) > 1:
		return ActionResult.failure(actor.id, &"help", "Союзник не рядом")
	if not _spend(actor, &"action", r):
		return ActionResult.failure(actor.id, &"help", "Действие уже потрачено")
	ally.flags[&"helped"] = true
	r.targets = [ally.id]
	r.add_log("%s помогает %s: преимущество на следующую атаку" % [
		actor.display_name, ally.display_name])
	return r

## Толчок: состязание СИЛ (02-combat.md, раздел 5.1).
static func shove(state: CombatState, actor: CombatActor, target: CombatActor) -> ActionResult:
	var r := _make(actor, &"shove")
	if CombatGrid.distance(actor.cell, target.cell) > 1:
		return ActionResult.failure(actor.id, &"shove", "Цель не рядом")
	if not _spend(actor, &"action", r):
		return ActionResult.failure(actor.id, &"shove", "Действие уже потрачено")
	r.targets = [target.id]
	var a := Resolver.ability_check(state.rng, actor, Stats.STR, 0, true)
	var d := Resolver.ability_check(state.rng, target, Stats.STR, 0, true)
	r.rolls.append(a)
	r.rolls.append(d)
	if int(a["total"]) <= int(d["total"]):
		r.add_log("%s пытается оттолкнуть %s и не может (%d против %d)" % [
			actor.display_name, target.display_name, int(a["total"]), int(d["total"])])
		return r
	var dir := target.cell - actor.cell
	dir = Vector2i(signi(dir.x), signi(dir.y))
	var dest := target.cell + dir
	if state.grid.is_walkable(dest) and state.actor_at(dest) == null:
		target.cell = dest
		r.movement = [dest]
	var event := StatusEngine.apply(state, target, &"prone_push", actor.id)
	if not event.is_empty():
		r.status_events.append(event)
	r.add_log("%s отталкивает %s (%d против %d)" % [actor.display_name,
		target.display_name, int(a["total"]), int(d["total"])])
	return r

## Стабилизация умирающего союзника (проверка МДР СЛ 10).
static func stabilize(state: CombatState, actor: CombatActor, target: CombatActor) -> ActionResult:
	var r := _make(actor, &"stabilize")
	if not target.is_down:
		return ActionResult.failure(actor.id, &"stabilize", "Цель не при смерти")
	if CombatGrid.distance(actor.cell, target.cell) > 1:
		return ActionResult.failure(actor.id, &"stabilize", "Цель не рядом")
	if not _spend(actor, &"action", r):
		return ActionResult.failure(actor.id, &"stabilize", "Действие уже потрачено")
	r.targets = [target.id]
	var check := Resolver.ability_check(state.rng, actor, Stats.WIS, state.balance.death_save_dc, true)
	r.rolls.append(check)
	if bool(check["success"]):
		target.flags[&"stable"] = true
		target.death_failures = 0
		r.add_log("%s стабилизирует %s" % [actor.display_name, target.display_name])
	else:
		r.add_log("%s не смог стабилизировать %s" % [actor.display_name, target.display_name])
	return r

## Применение расходника (зелье, бинт, антидот, эссенция).
static func use_consumable(state: CombatState, actor: CombatActor, target: CombatActor,
		item: ConsumableData) -> ActionResult:
	var r := _make(actor, item.id)
	var kind: StringName = &"action" if item.use_time == &"action" else &"bonus"
	if item.use_time != &"free" and not _spend(actor, kind, r):
		return ActionResult.failure(actor.id, item.id, "Нет свободного действия")
	r.targets = [target.id]
	match item.effect:
		&"heal":
			var roll := Dice.roll(item.dice, state.rng)
			var healed := DamageCalc.heal(target, int(roll["total"]))
			r.effects.append({"kind": "heal", "target": String(target.id), "amount": healed})
			r.add_log("%s: %s восстанавливает %d HP" % [item.display_name, target.display_name, healed])
		&"cure_status":
			var e := StatusEngine.remove(target, item.status_id)
			if not e.is_empty():
				r.status_events.append(e)
				r.add_log("%s снимает «%s»" % [item.display_name, e.get("name", "")])
			else:
				r.add_log("%s не находит, что снимать" % item.display_name)
		&"restore_slot":
			for i: int in target.spell_slots.size():
				if target.spell_slots[i] < target.spell_slots_max[i]:
					target.spell_slots[i] += 1
					r.add_log("%s восстанавливает ячейку %d уровня" % [item.display_name, i + 1])
					break
		&"buff":
			var e := StatusEngine.apply(state, target, item.status_id, actor.id)
			if not e.is_empty():
				r.status_events.append(e)
				r.add_log("%s накладывает «%s»" % [item.display_name, e.get("name", "")])
		_:
			r.add_log("%s использован" % item.display_name)
	return r
