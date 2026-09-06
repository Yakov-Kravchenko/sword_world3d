extends Node
## Проверка формы этажей на многих сидах:
##   godot --headless --path . res://tools/plan_dump.tscn
## Печатает узкое место коридоров и удалённость выхода от входа.

func _ready() -> void:
	var biome_ids: Array[StringName] = [&"catacombs", &"mines", &"swamp", &"necropolis"]
	var worst_width := 99
	var worst_ratio := 1.0
	var floors := 0
	for biome_id: StringName in biome_ids:
		var biome := Database.get_biome(biome_id)
		if biome == null:
			continue
		for seed_value: int in range(1, 26):
			var gen := DungeonGenerator.new(Balance.data, biome, seed_value % 20 + 1, seed_value * 7919)
			gen.enemy_db = Database.enemy_map()
			var plan := gen.generate()
			floors += 1
			worst_width = mini(worst_width, _narrowest(plan))
			worst_ratio = minf(worst_ratio, _exit_ratio(plan))
	print("этажей проверено: ", floors)
	print("самый узкий коридор: ", worst_width, " клеток")
	print("худшая удалённость выхода: ", worst_ratio, " от максимума по графу")
	get_tree().quit()

func _narrowest(plan: FloorPlan) -> int:
	var narrowest := 99
	for y: int in range(1, plan.height - 1):
		for x: int in range(1, plan.width - 1):
			var cell := Vector2i(x, y)
			if not (plan.is_floor(cell) and plan.room_at(cell) == null):
				continue
			narrowest = mini(narrowest, maxi(_run(plan, cell, Vector2i.RIGHT),
				_run(plan, cell, Vector2i.DOWN)))
	return narrowest

func _run(plan: FloorPlan, cell: Vector2i, axis: Vector2i) -> int:
	var total := 1
	for sign_value: int in [1, -1]:
		var cur := cell + axis * sign_value
		while plan.is_floor(cur) and plan.room_at(cur) == null:
			total += 1
			cur += axis * sign_value
	return total

## Доля: расстояние до выхода от максимального расстояния по графу комнат.
func _exit_ratio(plan: FloorPlan) -> float:
	var entrance := plan.room_at(plan.entrance_cell)
	var exit_room := plan.room_at(plan.exit_cell)
	if entrance == null or exit_room == null:
		return 0.0
	var dist := {entrance.index: 0}
	var queue: Array[int] = [entrance.index]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for n: int in plan.rooms[cur].connections:
			if dist.has(n):
				continue
			dist[n] = int(dist[cur]) + 1
			queue.append(n)
	var best := 1
	for i: int in plan.rooms.size():
		best = maxi(best, int(dist.get(i, 0)))
	return float(int(dist.get(exit_room.index, 0))) / float(best)
