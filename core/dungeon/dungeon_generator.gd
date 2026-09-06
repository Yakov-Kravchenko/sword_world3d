class_name DungeonGenerator
extends RefCounted
## Генерация этажа (04-dungeon.md, раздел 3.2). Все броски — из RngStream,
## поэтому один и тот же сид всегда даёт один и тот же этаж.

const MAP_SIZE := 72
const ROOM_MIN := 5
## Ширина коридора в клетках. Коридор в одну клетку читался как щель и не давал
## отряду разойтись: в бою на сетке 1.5 м это ровно один боец в ряд.
const CORRIDOR_WIDTH := 3
const ROOM_MAX := 11
const MAX_PLACEMENT_TRIES := 12
const MAX_REGENERATIONS := 5

var balance: BalanceData
var biome: BiomeData
var floor_index: int = 1
var run_seed: int = 0
## id -> EnemyData, передаётся игровым слоем.
var enemy_db: Dictionary = {}

func _init(balance_data: BalanceData, biome_data: BiomeData, index: int, seed_value: int) -> void:
	balance = balance_data
	biome = biome_data
	floor_index = index
	run_seed = seed_value

## Основной вход. Возвращает связный FloorPlan; при неудаче — запасной коридорный этаж.
func generate() -> FloorPlan:
	for attempt: int in MAX_REGENERATIONS:
		var rng := RngStream.new(RngStream.hash_combine(run_seed, "floor_%d_%d" % [floor_index, attempt]), &"floor")
		var plan := _attempt(rng)
		if plan != null:
			plan.generation_attempts = attempt + 1
			return plan
	return _fallback()

func _attempt(rng: RngStream) -> FloorPlan:
	var plan := FloorPlan.new(MAP_SIZE, MAP_SIZE)
	plan.floor_index = floor_index
	plan.biome_id = biome.id
	plan.run_seed = run_seed
	var target := rng.randi_range(biome.room_count_min, biome.room_count_max)
	var skeleton := _pick_skeleton(rng)
	if not _place_rooms(plan, rng, target, skeleton):
		return null
	_carve_corridors(plan, rng, skeleton)
	if not _is_connected(plan):
		return null
	_assign_roles(plan, rng)
	_populate(plan, rng)
	return plan

func _pick_skeleton(rng: RngStream) -> StringName:
	var names: Array = []
	var weights: Array = []
	for key: Variant in biome.graph_weights.keys():
		names.append(StringName(key))
		weights.append(float(biome.graph_weights[key]))
	if names.is_empty():
		return &"branching"
	return rng.pick_weighted(names, weights)

func _place_rooms(plan: FloorPlan, rng: RngStream, target: int, skeleton: StringName) -> bool:
	var first := _random_room_rect(rng, Vector2i(MAP_SIZE / 2 - 4, MAP_SIZE / 2 - 4))
	_add_room(plan, first)
	while plan.rooms.size() < target:
		var placed := false
		for tries: int in MAX_PLACEMENT_TRIES:
			var anchor: FloorPlan.Room = _pick_anchor(plan, rng, skeleton)
			var dir: Vector2i = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN][rng.randi_range(0, 3)]
			var size := Vector2i(rng.randi_range(ROOM_MIN, ROOM_MAX), rng.randi_range(ROOM_MIN, ROOM_MAX))
			var gap := rng.randi_range(3, 7)
			var pos := _offset_position(anchor.rect, size, dir, gap, rng)
			var rect := Rect2i(pos, size)
			if _fits(plan, rect):
				var room := _add_room(plan, rect)
				room.connections.append(anchor.index)
				anchor.connections.append(room.index)
				placed = true
				break
		if not placed:
			return plan.rooms.size() >= maxi(6, target - 3)
	return true

func _pick_anchor(plan: FloorPlan, rng: RngStream, skeleton: StringName) -> FloorPlan.Room:
	match skeleton:
		&"linear":
			return plan.rooms[plan.rooms.size() - 1]
		&"hub":
			return plan.rooms[0] if rng.randf_value() < 0.6 else plan.rooms[rng.randi_range(0, plan.rooms.size() - 1)]
		&"ring":
			return plan.rooms[maxi(0, plan.rooms.size() - 1 - rng.randi_range(0, 1))]
		_:
			return plan.rooms[rng.randi_range(0, plan.rooms.size() - 1)]

func _offset_position(anchor: Rect2i, size: Vector2i, dir: Vector2i, gap: int, rng: RngStream) -> Vector2i:
	var pos := anchor.position
	if dir == Vector2i.RIGHT:
		pos.x = anchor.end.x + gap
		pos.y = anchor.position.y + rng.randi_range(-2, 2)
	elif dir == Vector2i.LEFT:
		pos.x = anchor.position.x - gap - size.x
		pos.y = anchor.position.y + rng.randi_range(-2, 2)
	elif dir == Vector2i.DOWN:
		pos.y = anchor.end.y + gap
		pos.x = anchor.position.x + rng.randi_range(-2, 2)
	else:
		pos.y = anchor.position.y - gap - size.y
		pos.x = anchor.position.x + rng.randi_range(-2, 2)
	return pos

func _fits(plan: FloorPlan, rect: Rect2i) -> bool:
	if rect.position.x < 2 or rect.position.y < 2:
		return false
	if rect.end.x >= MAP_SIZE - 2 or rect.end.y >= MAP_SIZE - 2:
		return false
	var padded := rect.grow(2)
	for r: FloorPlan.Room in plan.rooms:
		if padded.intersects(r.rect):
			return false
	return true

func _add_room(plan: FloorPlan, rect: Rect2i) -> FloorPlan.Room:
	var room := FloorPlan.Room.new()
	room.index = plan.rooms.size()
	room.rect = rect
	plan.rooms.append(room)
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			plan.set_tile(Vector2i(x, y), FloorPlan.TILE_FLOOR)
	return room

func _carve_corridors(plan: FloorPlan, rng: RngStream, skeleton: StringName) -> void:
	for room: FloorPlan.Room in plan.rooms:
		for other_index: int in room.connections:
			_carve_l(plan, room.center(), plan.rooms[other_index].center(), rng)
	if skeleton == &"ring" and plan.rooms.size() > 3:
		_carve_l(plan, plan.rooms[0].center(), plan.rooms[plan.rooms.size() - 1].center(), rng)
		plan.rooms[0].connections.append(plan.rooms.size() - 1)
		plan.rooms[plan.rooms.size() - 1].connections.append(0)

func _carve_l(plan: FloorPlan, from: Vector2i, to: Vector2i, rng: RngStream) -> void:
	var horizontal_first := rng.randf_value() < 0.5
	var corner := Vector2i(to.x, from.y) if horizontal_first else Vector2i(from.x, to.y)
	_carve_line(plan, from, corner)
	_carve_line(plan, corner, to)

func _carve_line(plan: FloorPlan, from: Vector2i, to: Vector2i) -> void:
	var cur := from
	while cur != to:
		_carve_brush(plan, cur)
		if cur.x != to.x:
			cur.x += signi(to.x - cur.x)
		elif cur.y != to.y:
			cur.y += signi(to.y - cur.y)
	_carve_brush(plan, to)

## Квадратная кисть по ходу коридора: заодно скругляет углы, где линия ломается.
func _carve_brush(plan: FloorPlan, center: Vector2i) -> void:
	var reach := (CORRIDOR_WIDTH - 1) / 2
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			# Внешнее кольцо стен остаётся нетронутым, иначе этаж вскрывается наружу.
			var cell := Vector2i(clampi(center.x + dx, 1, MAP_SIZE - 2),
				clampi(center.y + dy, 1, MAP_SIZE - 2))
			if plan.tile(cell) == FloorPlan.TILE_WALL:
				plan.set_tile(cell, FloorPlan.TILE_FLOOR)

## BFS от входа: проверка, что все комнаты достижимы (04-dungeon.md, шаг 3).
func _is_connected(plan: FloorPlan) -> bool:
	if plan.rooms.is_empty():
		return false
	var start := plan.rooms[0].center()
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := cur + d
			if seen.has(n) or not plan.is_floor(n):
				continue
			seen[n] = true
			queue.append(n)
	for room: FloorPlan.Room in plan.rooms:
		if not seen.has(room.center()):
			return false
	return true

func _fallback() -> FloorPlan:
	# Гарантированный запасной этаж: цепочка комнат вдоль коридора.
	var plan := FloorPlan.new(MAP_SIZE, MAP_SIZE)
	plan.floor_index = floor_index
	plan.biome_id = biome.id
	plan.run_seed = run_seed
	var x := 4
	for i: int in 8:
		var rect := Rect2i(x, MAP_SIZE / 2 - 3, 7, 7)
		_add_room(plan, rect)
		if i > 0:
			plan.rooms[i].connections.append(i - 1)
			plan.rooms[i - 1].connections.append(i)
			_carve_line(plan, plan.rooms[i - 1].center(), plan.rooms[i].center())
		x += 11
	var rng := RngStream.new(run_seed, &"fallback")
	_assign_roles(plan, rng)
	_populate(plan, rng)
	return plan

func _random_room_rect(rng: RngStream, pos: Vector2i) -> Rect2i:
	return Rect2i(pos, Vector2i(rng.randi_range(ROOM_MIN, ROOM_MAX), rng.randi_range(ROOM_MIN, ROOM_MAX)))

## Шаг 4: назначение ролей комнатам (04-dungeon.md, раздел 3.2).
func _assign_roles(plan: FloorPlan, rng: RngStream) -> void:
	# Вход и выход разносим по концам графа комнат — по его диаметру. Комната 0
	# стоит в середине карты, и выход от неё оказывался посреди этажа: часть
	# комнат приходилось проходить дважды, туда и обратно.
	var entrance_index := _farthest_room(plan, 0)
	var distances := _room_distances(plan, entrance_index)
	var exit_index := _farthest_room(plan, entrance_index)
	if exit_index == entrance_index:
		exit_index = (entrance_index + 1) % plan.rooms.size()
	plan.rooms[entrance_index].role = FloorPlan.ROLE_ENTRANCE
	plan.entrance_cell = plan.rooms[entrance_index].center()
	plan.set_tile(plan.entrance_cell, FloorPlan.TILE_ENTRANCE)
	var exit_room := plan.rooms[exit_index]
	exit_room.role = FloorPlan.ROLE_EXIT
	plan.exit_cell = exit_room.center()
	plan.set_tile(plan.exit_cell, FloorPlan.TILE_STAIRS_DOWN)
	# Логово стража — комната перед выходом.
	var guardian_index := _predecessor(plan, distances, exit_index)
	if guardian_index >= 0:
		plan.rooms[guardian_index].role = FloorPlan.ROLE_GUARDIAN
	if balance.is_boss_floor(floor_index):
		exit_room.role = FloorPlan.ROLE_BOSS
	elif balance.is_herald_floor(floor_index) and guardian_index >= 0:
		plan.rooms[guardian_index].role = FloorPlan.ROLE_HERALD
	var free: Array[int] = []
	for i: int in plan.rooms.size():
		if plan.rooms[i].role == FloorPlan.ROLE_EMPTY:
			free.append(i)
	rng.shuffle(free)
	_take_role(plan, free, FloorPlan.ROLE_ALTAR, 1)
	_take_role(plan, free, FloorPlan.ROLE_TREASURE, 1)
	_take_role(plan, free, FloorPlan.ROLE_EVENT, 1 if rng.randf_value() < 0.6 else 0)
	_take_role(plan, free, FloorPlan.ROLE_TRAPS, 1 if rng.randf_value() < 0.5 else 0)
	for i: int in free:
		plan.rooms[i].role = FloorPlan.ROLE_COMBAT if rng.randf_value() < 0.72 else FloorPlan.ROLE_EMPTY

func _take_role(plan: FloorPlan, free: Array[int], role: StringName, count: int) -> void:
	for i: int in count:
		if free.is_empty():
			return
		plan.rooms[free.pop_back()].role = role

## Самая дальняя комната по графу. Дважды подряд от произвольной комнаты — это
## классический способ найти диаметр дерева, то есть два самых удалённых конца.
func _farthest_room(plan: FloorPlan, from_index: int) -> int:
	var distances := _room_distances(plan, from_index)
	var best := -1
	var found := from_index
	for i: int in plan.rooms.size():
		var d: int = int(distances.get(i, -1))
		if d > best:
			best = d
			found = i
	return found

## Расстояния по графу комнат (в рёбрах) от заданной комнаты.
func _room_distances(plan: FloorPlan, from_index: int) -> Dictionary:
	var dist := {from_index: 0}
	var queue: Array[int] = [from_index]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for n: int in plan.rooms[cur].connections:
			if dist.has(n):
				continue
			dist[n] = int(dist[cur]) + 1
			queue.append(n)
	return dist

func _predecessor(plan: FloorPlan, distances: Dictionary, index: int) -> int:
	var want: int = int(distances.get(index, 0)) - 1
	for n: int in plan.rooms[index].connections:
		if int(distances.get(n, -1)) == want:
			return n
	return -1

## Шаг 5: наполнение врагами, лутом и ловушками.
func _populate(plan: FloorPlan, rng: RngStream) -> void:
	var builder := EncounterBuilder.new(balance, biome, rng, enemy_db)
	for room: FloorPlan.Room in plan.rooms:
		var kind := room.role
		match kind:
			FloorPlan.ROLE_ENTRANCE, FloorPlan.ROLE_ALTAR, FloorPlan.ROLE_EMPTY:
				pass
			FloorPlan.ROLE_BOSS:
				plan.encounters.append(builder.build_boss(room, floor_index))
			FloorPlan.ROLE_HERALD:
				plan.encounters.append(builder.build(room, floor_index, balance.encounter_mult_guardian, true))
			FloorPlan.ROLE_GUARDIAN:
				plan.encounters.append(builder.build(room, floor_index, balance.encounter_mult_elite, true))
			FloorPlan.ROLE_TREASURE:
				plan.encounters.append(builder.build(room, floor_index, balance.encounter_mult_normal, false))
			_:
				if kind == FloorPlan.ROLE_COMBAT or rng.randf_value() < 0.25:
					plan.encounters.append(builder.build(room, floor_index, balance.encounter_mult_normal, false))
		_place_props(plan, room, rng)
	_place_lights(plan, rng)

func _place_props(plan: FloorPlan, room: FloorPlan.Room, rng: RngStream) -> void:
	var cells := plan.floor_cells_in(room.rect)
	if cells.is_empty():
		return
	match room.role:
		FloorPlan.ROLE_TREASURE:
			# Сокровищница часто заперта, а замок бывает с иглой (04-dungeon.md, разд. 3.3).
			for i: int in rng.randi_range(2, 4):
				plan.props.append({"kind": &"chest", "cell": rng.pick(cells),
					"table": &"chest_treasure", "room": room.index,
					"locked": rng.randf_value() < 0.6,
					"trapped": rng.randf_value() < biome.trap_density * 2.0})
		FloorPlan.ROLE_ALTAR:
			plan.props.append({"kind": &"altar", "cell": room.center(), "room": room.index})
		FloorPlan.ROLE_BOSS:
			plan.props.append({"kind": &"gate", "cell": room.center() + Vector2i(0, 2),
				"room": room.index})
		FloorPlan.ROLE_EVENT:
			plan.props.append({"kind": &"event", "cell": room.center(), "room": room.index})
		_:
			if rng.randf_value() < 0.35:
				plan.props.append({"kind": &"chest", "cell": rng.pick(cells),
					"table": &"chest_common", "room": room.index,
					"locked": rng.randf_value() < 0.15,
					"trapped": rng.randf_value() < biome.trap_density})
	var trap_rolls := 3 if room.role == FloorPlan.ROLE_TRAPS else 1
	for i: int in trap_rolls:
		if rng.randf_value() < biome.trap_density:
			plan.props.append({"kind": &"trap", "cell": rng.pick(cells), "room": room.index,
				"dc": 12 + floor_index / 2})

func _place_lights(plan: FloorPlan, rng: RngStream) -> void:
	var count := rng.randi_range(0, 3)
	for i: int in count:
		var room: FloorPlan.Room = plan.rooms[rng.randi_range(0, plan.rooms.size() - 1)]
		plan.static_lights.append(room.center())
