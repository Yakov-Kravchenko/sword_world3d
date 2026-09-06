extends Node
## Форма и наполнение этажей:
##   godot --headless --path . res://tools/plan_dump.tscn

func _ready() -> void:
	for floor_index: int in [1, 9, 10, 20]:
		var biome := Database.get_biome(&"catacombs")
		var gen := DungeonGenerator.new(Balance.data, biome, floor_index, 4242)
		gen.enemy_db = Database.enemy_map()
		var plan := gen.generate()
		var roles: Array[String] = []
		for room: FloorPlan.Room in plan.rooms:
			roles.append("%d:%s" % [room.index, room.role])
		print("--- этаж %d, босс-этаж=%s" % [floor_index, Balance.data.is_boss_floor(floor_index)])
		print("   комнаты: ", ", ".join(roles))
		var exit_room := plan.room_at(plan.exit_cell)
		print("   выход в комнате %d (роль %s)" % [exit_room.index if exit_room else -1,
			exit_room.role if exit_room else "?"])
		for prop: Dictionary in plan.props:
			if StringName(prop["kind"]) != &"gate":
				continue
			var cell: Vector2i = prop["cell"]
			print("   ВРАТА в клетке %s, пол=%s, комната=%s" % [cell, plan.is_floor(cell),
				prop.get("room", -1)])
		var gates := 0
		for prop: Dictionary in plan.props:
			if StringName(prop["kind"]) == &"gate":
				gates += 1
		if gates == 0:
			print("   ВРАТ НЕТ")
		for e: Dictionary in plan.encounters:
			var room := plan.rooms[int(e["room"])]
			if room.role in [FloorPlan.ROLE_BOSS, FloorPlan.ROLE_GUARDIAN, FloorPlan.ROLE_HERALD]:
				print("   встреча %s в комнате %d: %s" % [room.role, room.index,
					", ".join(PackedStringArray(e.get("enemies", [])))])
	get_tree().quit()
