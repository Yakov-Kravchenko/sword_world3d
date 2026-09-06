class_name MoveAction
extends RefCounted
## Перемещение по сетке с провокацией атак (02-combat.md, разделы 2.2 и 5.3).

## Клетки, доступные актёру с текущим запасом движения.
static func reachable(state: CombatState, actor: CombatActor) -> Dictionary:
	if actor.effective_speed() <= 0 or actor.movement_left <= 0:
		return {}
	return state.grid.reachable(actor.cell, actor.movement_left, state.blocked_cells(actor.id))

static func resolve(state: CombatState, actor: CombatActor, destination: Vector2i) -> ActionResult:
	var result := ActionResult.new()
	result.actor_id = actor.id
	result.action_id = &"move"
	if actor.has_flag_status(&"blocks_movement"):
		return ActionResult.failure(actor.id, &"move", "Обездвижен")
	if not state.can_occupy(actor, destination):
		return ActionResult.failure(actor.id, &"move", "Клетка занята")
	var blocked := state.blocked_cells(actor.id)
	var path := state.grid.find_path(actor.cell, destination, blocked, actor.movement_left)
	if path.is_empty():
		return ActionResult.failure(actor.id, &"move", "Туда не пройти")
	var cost := 0
	for c: Vector2i in path:
		cost += state.grid.move_cost(c)
	if cost > actor.movement_left:
		return ActionResult.failure(actor.id, &"move", "Не хватает движения")
	var threats := _threatening(state, actor)
	var start := actor.cell
	actor.cell = destination
	actor.movement_left -= cost
	result.movement = path
	result.resources_spent[&"movement"] = cost
	result.add_log("%s перемещается на %d кл." % [actor.display_name, path.size()])
	if not bool(actor.flags.get(&"disengaging", false)):
		_opportunity_attacks(state, actor, threats, start, result)
	return result

## Враги, угрожающие актёру в текущей клетке (могут провоцировать).
static func _threatening(state: CombatState, actor: CombatActor) -> Array[CombatActor]:
	var out: Array[CombatActor] = []
	for a: CombatActor in state.all_actors():
		if a.team == actor.team or not a.is_alive() or a.is_down:
			continue
		if a.reaction_left <= 0:
			continue
		if CombatGrid.distance(a.cell, actor.cell) <= 1:
			out.append(a)
	return out

static func _opportunity_attacks(state: CombatState, actor: CombatActor,
		threats: Array[CombatActor], _from: Vector2i, result: ActionResult) -> void:
	for enemy: CombatActor in threats:
		if CombatGrid.distance(enemy.cell, actor.cell) <= 1:
			continue  # остался рядом — провокации нет
		if enemy.reaction_left <= 0 or not enemy.is_alive() or enemy.attacks.is_empty():
			continue
		enemy.reaction_left -= 1
		result.add_log("Атака при возможности: %s" % enemy.display_name)
		var moved_to := actor.cell
		actor.cell = _from  # провокация разрешается по покидаемой клетке
		var sub := AttackAction.resolve(state, enemy, actor, enemy.attacks[0], true)
		actor.cell = moved_to
		result.rolls.append_array(sub.rolls)
		result.damage_events.append_array(sub.damage_events)
		result.status_events.append_array(sub.status_events)
		for line: String in sub.log_lines:
			result.add_log("  " + line)
