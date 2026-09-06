extends TestCase

var index: ContentIndex
var balance: BalanceData

func suite_name() -> String:
	return "Генерация подземелья"

func before_each() -> void:
	index = ContentIndex.load_from()
	balance = ContentIndex.load_balance()

func _biomes() -> Array:
	return index.of_class("BiomeData")

## Требование ТЗ: 1000 сидов на 12 наборов биомов — связность и отсутствие пересечений.
func test_thousand_seeds_are_connected() -> void:
	var biomes := _biomes()
	assert_eq(biomes.size(), 12, "6 базовых + 6 глубоких")
	var enemies := index.map_of_class("EnemyData")
	var checked := 0
	var fallback_used := 0
	for seed_value: int in range(1, 1001):
		var biome: BiomeData = biomes[seed_value % biomes.size()]
		var floor_index: int = 1 + (seed_value % 9)
		var gen := DungeonGenerator.new(balance, biome, floor_index, seed_value)
		gen.enemy_db = enemies
		var plan := gen.generate()
		checked += 1
		if plan.generation_attempts > 1:
			fallback_used += 1
		if not _all_rooms_reachable(plan):
			_fail("сид %d, биом %s: этаж несвязен" % [seed_value, biome.id])
			return
		if _rooms_overlap(plan):
			_fail("сид %d: комнаты пересекаются" % seed_value)
			return
		if plan.rooms.size() < 6:
			_fail("сид %d: слишком мало комнат (%d)" % [seed_value, plan.rooms.size()])
			return
	assert_eq(checked, 1000)
	assert_le(float(fallback_used), 200.0, "перегенерация должна быть редкой")

func test_same_seed_same_floor() -> void:
	var biome: BiomeData = index.get_resource(&"catacombs")
	var a := DungeonGenerator.new(balance, biome, 3, 777).generate()
	var b := DungeonGenerator.new(balance, biome, 3, 777).generate()
	assert_eq(a.rooms.size(), b.rooms.size())
	assert_eq(a.entrance_cell, b.entrance_cell)
	assert_eq(a.exit_cell, b.exit_cell)
	assert_true(a.tiles == b.tiles, "одинаковый сид — одинаковая геометрия")

func test_roles_assigned() -> void:
	var biome: BiomeData = index.get_resource(&"mines")
	var plan := DungeonGenerator.new(balance, biome, 4, 12345).generate()
	assert_not_null(plan.room_by_role(FloorPlan.ROLE_ENTRANCE))
	assert_not_null(plan.room_by_role(FloorPlan.ROLE_GUARDIAN))
	assert_not_null(plan.room_by_role(FloorPlan.ROLE_ALTAR))
	assert_ne(plan.entrance_cell, plan.exit_cell)
	# Страж стоит в той же комнате, что и спуск: мимо него на следующий этаж
	# не пройти (04-dungeon.md, раздел 5).
	var last_room := plan.room_at(plan.exit_cell)
	assert_not_null(last_room, "спуск лежит внутри комнаты")
	assert_eq(String(last_room.role), String(FloorPlan.ROLE_GUARDIAN))

func test_boss_floor_uses_boss_room() -> void:
	var biome: BiomeData = index.get_resource(&"necropolis")
	var gen := DungeonGenerator.new(balance, biome, balance.boss_floors[0], 5150)
	gen.enemy_db = index.map_of_class("EnemyData")
	var plan := gen.generate()
	var boss_room := plan.room_by_role(FloorPlan.ROLE_BOSS)
	assert_not_null(boss_room, "на этаже босса должна быть арена")
	var encounter := plan.encounter_for_room(boss_room.index)
	assert_eq(String(encounter.get("kind", "")), "boss")

func test_encounter_budget_grows_with_depth() -> void:
	assert_gt(float(balance.encounter_budget(10, 1.0)), float(balance.encounter_budget(1, 1.0)))
	assert_gt(float(balance.encounter_budget(5, balance.encounter_mult_guardian)),
		float(balance.encounter_budget(5, balance.encounter_mult_normal)))

func test_encounter_respects_enemy_cap() -> void:
	var biome: BiomeData = index.get_resource(&"catacombs")
	var enemies := index.map_of_class("EnemyData")
	for seed_value: int in range(1, 60):
		var gen := DungeonGenerator.new(balance, biome, 9, seed_value)
		gen.enemy_db = enemies
		var plan := gen.generate()
		for e: Dictionary in plan.encounters:
			assert_le(float((e["enemies"] as Array).size()),
				float(balance.max_enemies_per_room) + 3.0)

func _all_rooms_reachable(plan: FloorPlan) -> bool:
	var start := plan.entrance_cell
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cur + d
			if seen.has(n) or not plan.is_floor(n):
				continue
			seen[n] = true
			queue.append(n)
	for room: FloorPlan.Room in plan.rooms:
		if not seen.has(room.center()):
			return false
	return seen.has(plan.exit_cell)

func _rooms_overlap(plan: FloorPlan) -> bool:
	for i: int in plan.rooms.size():
		for j: int in range(i + 1, plan.rooms.size()):
			if plan.rooms[i].rect.intersects(plan.rooms[j].rect):
				return true
	return false

## Врата Возврата: только на этажах босса, только в его комнате (04-dungeon.md,
## раздел 2.4). На обычном этаже их быть не должно — выход там через спуск.
func test_gate_only_on_boss_floors_and_inside_boss_room() -> void:
	var biome: BiomeData = index.get_resource(&"necropolis")
	for floor_index: int in [1, 4, 9, balance.boss_floors[0], balance.boss_floors[1]]:
		var gen := DungeonGenerator.new(balance, biome, floor_index, 8080)
		gen.enemy_db = index.map_of_class("EnemyData")
		var plan := gen.generate()
		var gates: Array[Dictionary] = []
		for prop: Dictionary in plan.props:
			if StringName(prop["kind"]) == &"gate":
				gates.append(prop)
		if not balance.is_boss_floor(floor_index):
			assert_eq(gates.size(), 0, "на этаже %d Врат быть не должно" % floor_index)
			continue
		assert_eq(gates.size(), 1, "на этаже %d ровно одни Врата" % floor_index)
		var boss_room := plan.room_by_role(FloorPlan.ROLE_BOSS)
		assert_not_null(boss_room, "арена босса на этаже %d" % floor_index)
		var cell: Vector2i = gates[0]["cell"]
		assert_true(boss_room.rect.has_point(cell),
			"Врата стоят внутри комнаты босса на этаже %d" % floor_index)
		assert_true(plan.is_floor(cell), "клетка Врат проходима")
