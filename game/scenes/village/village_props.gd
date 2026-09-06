class_name VillageProps
extends RefCounted
## Постройки деревни в сером блокинге: каждая собирается из примитивов и читается
## по силуэту — кузница по горну и наковальне, лавка по прилавку с навесом и так
## далее. Каждый строитель возвращает точку взаимодействия, а стены и утварь
## попадают в список препятствий.

var root: Node3D
var blockers: Array[Rect2] = []
var player_radius: float = 0.45

const WOOD := Color(0.36, 0.26, 0.17)
const WOOD_DARK := Color(0.26, 0.19, 0.13)
const STONE := Color(0.31, 0.3, 0.29)
const STONE_DARK := Color(0.2, 0.19, 0.19)
const METAL := Color(0.32, 0.33, 0.36)
const CLOTH := Color(0.45, 0.3, 0.24)

var kit: VillageKit

func _init(parent: Node3D, radius: float) -> void:
	root = parent
	player_radius = radius
	if VillageKit.available():
		kit = VillageKit.new(parent, radius, blockers)

# --- Примитивы ---

func box(size: Vector3, pos: Vector3, color: Color, blocking: bool = false,
		yaw: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := _spawn(mesh, pos, color, yaw)
	if blocking:
		_block(size, pos, yaw)
	return node

func cylinder(radius: float, height: float, pos: Vector3, color: Color,
		blocking: bool = false) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var node := _spawn(mesh, pos, color, 0.0)
	if blocking:
		_block(Vector3(radius * 2.0, height, radius * 2.0), pos, 0.0)
	return node

func sphere(radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return _spawn(mesh, pos, color, 0.0)

func glow(size: Vector3, pos: Vector3, color: Color, energy: float = 2.4) -> MeshInstance3D:
	var node := box(size, pos, color)
	var mat: StandardMaterial3D = node.material_override
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return node

func lamp(pos: Vector3, color: Color, energy: float, range_m: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = false
	root.add_child(light)
	return light

func _spawn(mesh: Mesh, pos: Vector3, color: Color, yaw: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation.y = yaw
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	node.material_override = mat
	root.add_child(node)
	return node

## Препятствие описывается прямоугольником в плане, расширенным на радиус игрока.
func _block(size: Vector3, pos: Vector3, yaw: float) -> void:
	var half := Vector2(size.x, size.z) * 0.5
	if absf(sin(yaw)) > 0.5:
		half = Vector2(size.z, size.x) * 0.5
	blockers.append(Rect2(
		pos.x - half.x - player_radius, pos.z - half.y - player_radius,
		half.x * 2.0 + player_radius * 2.0, half.y * 2.0 + player_radius * 2.0))

## Столбы по углам площадки и крыша поверх — общий каркас открытого навеса.
func _shelter(center: Vector3, size: Vector2, height: float, post: float,
		roof_color: Color, post_color: Color) -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(Vector3(post, height, post),
				center + Vector3(sx * size.x * 0.5, height * 0.5, sz * size.y * 0.5),
				post_color, true)
	gable_roof(center + Vector3(0.0, height + 0.75, 0.0), size, 1.5, roof_color)
	# Стропила под скатом.
	for i: int in 3:
		box(Vector3(size.x + post, 0.12, 0.12),
			center + Vector3(0.0, height + 0.05, -size.y * 0.3 + float(i) * size.y * 0.3),
			roof_color.darkened(0.25))

# --- Кузница: открытый навес, горн с углями, наковальня, стойка с оружием ---

func build_forge(center: Vector3) -> Vector3:
	var ready := external("forge", center, Vector3(0.0, 0.9, 2.5))
	if ready != Vector3.INF:
		return ready
	if kit != null:
		return _kit_forge(center)
	box(Vector3(9.0, 0.2, 7.0), center + Vector3(0.0, 0.1, 0.0), STONE_DARK)
	_shelter(center, Vector2(8.0, 6.0), 3.2, 0.35, WOOD_DARK, WOOD)
	# Горн у дальней стены и труба над ним.
	var hearth := center + Vector3(0.0, 0.0, -2.2)
	box(Vector3(2.6, 1.3, 1.8), hearth + Vector3(0.0, 0.65, 0.0), STONE, true)
	glow(Vector3(1.8, 0.2, 1.1), hearth + Vector3(0.0, 1.35, 0.0), Color(1.0, 0.45, 0.12), 3.4)
	box(Vector3(1.2, 3.4, 1.2), hearth + Vector3(0.0, 2.9, 0.0), STONE_DARK)
	lamp(hearth + Vector3(0.0, 1.9, 0.6), Color(1.0, 0.55, 0.2), 3.0, 11.0)
	# Наковальня — точка взаимодействия.
	var anvil := center + Vector3(0.0, 0.0, 0.6)
	box(Vector3(0.7, 0.6, 0.7), anvil + Vector3(0.0, 0.4, 0.0), STONE_DARK, true)
	box(Vector3(1.5, 0.35, 0.6), anvil + Vector3(0.0, 0.87, 0.0), METAL)
	box(Vector3(1.9, 0.6, 1.1), center + Vector3(2.6, 0.4, 1.4), WOOD_DARK, true)
	cylinder(0.45, 0.9, center + Vector3(-2.8, 0.45, 1.6), WOOD, true)
	# Стойка с заготовками.
	box(Vector3(0.2, 1.8, 0.2), center + Vector3(-3.2, 0.9, -1.6), WOOD, true)
	box(Vector3(0.2, 1.8, 0.2), center + Vector3(-3.2, 0.9, 0.4), WOOD, true)
	box(Vector3(0.15, 0.15, 2.2), center + Vector3(-3.2, 1.7, -0.6), WOOD)
	for i: int in 3:
		box(Vector3(0.12, 1.1, 0.12), center + Vector3(-3.2, 1.15, -1.3 + i * 0.7), METAL)
	return anvil + Vector3(0.0, 0.9, 1.2)

# --- Тренировочный зал: помост под навесом, манекены, стойка ---

func build_training(center: Vector3) -> Vector3:
	var ready := external("training", center, Vector3(0.0, 0.9, 2.0))
	if ready != Vector3.INF:
		return ready
	if kit != null:
		var spot := kit.house(center / VillageKit.KIT_SCALE, Vector2i(4, 3), 1, 1)
		_training_yard(spot)
		return spot
	box(Vector3(11.0, 0.25, 9.0), center + Vector3(0.0, 0.12, 0.0), WOOD_DARK)
	_shelter(center, Vector2(10.0, 8.0), 3.4, 0.4, WOOD_DARK, WOOD)
	# Три манекена в ряд.
	for i: int in 3:
		var spot := center + Vector3(-2.8 + i * 2.8, 0.0, -2.6)
		box(Vector3(0.32, 2.0, 0.32), spot + Vector3(0.0, 1.0, 0.0), WOOD, true)
		box(Vector3(1.5, 0.28, 0.28), spot + Vector3(0.0, 1.55, 0.0), WOOD_DARK)
		sphere(0.26, spot + Vector3(0.0, 2.15, 0.0), CLOTH)
	box(Vector3(0.2, 1.9, 0.2), center + Vector3(4.0, 0.95, -1.0), WOOD, true)
	box(Vector3(0.2, 1.9, 0.2), center + Vector3(4.0, 0.95, 1.4), WOOD, true)
	box(Vector3(0.15, 0.15, 2.6), center + Vector3(4.0, 1.8, 0.2), WOOD)
	for i: int in 4:
		box(Vector3(0.14, 1.3, 0.14), center + Vector3(4.0, 1.25, -0.7 + i * 0.6), METAL)
	lamp(center + Vector3(0.0, 3.0, 1.0), Color(0.95, 0.9, 0.78), 2.0, 14.0)
	return center + Vector3(0.0, 0.9, 1.4)

# --- Лавка: прилавок с навесом, ящики, бочки, вывеска ---

func build_shop(center: Vector3) -> Vector3:
	var ready := external("shop", center, Vector3(0.0, 0.9, 2.2))
	if ready != Vector3.INF:
		return ready
	if kit != null:
		var spot := kit.house(center / VillageKit.KIT_SCALE, Vector2i(3, 2), 1, 1)
		var unit := VillageKit.KIT_SCALE
		kit.piece("stall-red", (spot + Vector3(-2.2, -0.9, 1.6)) / unit)
		kit.piece("cart", (spot + Vector3(2.6, -0.9, 1.2)) / unit, 1)
		kit.piece("banner-red", (spot + Vector3(-3.4, -0.9, -0.4)) / unit)
		kit.piece("lantern", (spot + Vector3(1.8, -0.9, 1.8)) / unit)
		lamp(spot + Vector3(1.8, 1.6, 1.8), Color(1.0, 0.85, 0.6), 2.4, 12.0)
		return spot
	box(Vector3(8.0, 0.2, 6.0), center + Vector3(0.0, 0.1, 0.0), STONE_DARK)
	# Задняя стенка с полками.
	log_wall(center + Vector3(0.0, 0.0, -2.6), 7.0, 3.0, WOOD_DARK, true)
	for i: int in 3:
		box(Vector3(6.2, 0.15, 0.5), center + Vector3(0.0, 0.9 + i * 0.7, -2.3), WOOD)
	for i: int in 6:
		box(Vector3(0.5, 0.5, 0.4),
			center + Vector3(-2.6 + i * 1.05, 1.2 + (i % 3) * 0.7, -2.25), CLOTH)
	# Прилавок и навес над ним.
	box(Vector3(6.0, 1.1, 1.0), center + Vector3(0.0, 0.55, 0.8), WOOD, true)
	box(Vector3(6.4, 0.12, 1.3), center + Vector3(0.0, 1.16, 0.8), WOOD_DARK)
	for sx: float in [-1.0, 1.0]:
		box(Vector3(0.25, 3.0, 0.25), center + Vector3(sx * 3.0, 1.5, 1.4), WOOD, true)
	var awning := box(Vector3(7.2, 0.2, 3.0), center + Vector3(0.0, 3.0, 0.4), CLOTH)
	awning.rotation.x = deg_to_rad(-12.0)
	# Вывеска на кронштейне.
	box(Vector3(0.15, 0.15, 1.2), center + Vector3(3.0, 3.1, 2.0), WOOD)
	box(Vector3(1.6, 0.9, 0.12), center + Vector3(3.0, 2.6, 2.5), WOOD_DARK)
	cylinder(0.5, 1.1, center + Vector3(-3.6, 0.55, 1.6), WOOD_DARK, true)
	cylinder(0.5, 1.1, center + Vector3(3.6, 0.55, 1.6), WOOD_DARK, true)
	box(Vector3(1.0, 0.9, 0.9), center + Vector3(-2.6, 0.45, 2.2), WOOD_DARK, true)
	lamp(center + Vector3(0.0, 2.6, 1.2), Color(1.0, 0.86, 0.6), 2.2, 12.0)
	return center + Vector3(0.0, 0.9, 2.2)

# --- Сад: огороженные грядки, бочка с водой, пугало ---

func build_garden(center: Vector3) -> Vector3:
	var ready := external("garden", center, Vector3(0.0, 0.9, 4.4))
	if ready != Vector3.INF:
		return ready
	if kit != null:
		return _kit_garden(center)
	box(Vector3(12.0, 0.15, 10.0), center + Vector3(0.0, 0.07, 0.0), Color(0.24, 0.22, 0.16))
	# Плетень по периметру с проходом со стороны двора.
	for i: int in 13:
		var x := -6.0 + i
		if absf(x) < 1.4:
			continue
		box(Vector3(0.18, 1.1, 0.18), center + Vector3(x, 0.55, 5.0), WOOD, true)
	for i: int in 13:
		box(Vector3(0.18, 1.1, 0.18), center + Vector3(-6.0 + i, 0.55, -5.0), WOOD, true)
	for i: int in 11:
		box(Vector3(0.18, 1.1, 0.18), center + Vector3(-6.0, 0.55, -5.0 + i), WOOD, true)
		box(Vector3(0.18, 1.1, 0.18), center + Vector3(6.0, 0.55, -5.0 + i), WOOD, true)
	# Четыре грядки с всходами.
	for row: int in 4:
		var bed := center + Vector3(0.0, 0.0, -3.2 + row * 2.0)
		box(Vector3(9.0, 0.4, 1.2), bed + Vector3(0.0, 0.2, 0.0), Color(0.3, 0.21, 0.14))
		for i: int in 9:
			sphere(0.22, bed + Vector3(-4.0 + i, 0.55, 0.0),
				Color(0.3, 0.5 - 0.05 * float(row % 2), 0.24))
	cylinder(0.6, 1.2, center + Vector3(-4.8, 0.6, 3.6), WOOD_DARK, true)
	glow(Vector3(0.9, 0.05, 0.9), center + Vector3(-4.8, 1.22, 3.6), Color(0.35, 0.5, 0.62), 0.6)
	# Пугало.
	box(Vector3(0.2, 2.2, 0.2), center + Vector3(4.4, 1.1, 3.4), WOOD, true)
	box(Vector3(1.8, 0.18, 0.18), center + Vector3(4.4, 1.7, 3.4), WOOD)
	sphere(0.3, center + Vector3(4.4, 2.35, 3.4), CLOTH)
	return center + Vector3(0.0, 0.9, 4.4)

# --- Склад: закрытое строение с воротами и штабелями ящиков ---

func build_storage(center: Vector3) -> Vector3:
	var ready := external("storage", center, Vector3(0.0, 0.9, 5.6))
	if ready != Vector3.INF:
		return ready
	if kit != null:
		return kit.house(center / VillageKit.KIT_SCALE, Vector2i(4, 3), 2, 1)
	var half := Vector2(5.0, 4.0)
	box(Vector3(half.x * 2.0 + 1.0, 0.2, half.y * 2.0 + 1.0),
		center + Vector3(0.0, 0.1, 0.0), STONE_DARK)
	var height := 4.0
	box(Vector3(0.5, height, half.y * 2.0), center + Vector3(-half.x, height * 0.5, 0.0), STONE, true)
	box(Vector3(0.5, height, half.y * 2.0), center + Vector3(half.x, height * 0.5, 0.0), STONE, true)
	box(Vector3(half.x * 2.0, height, 0.5), center + Vector3(0.0, height * 0.5, -half.y), STONE, true)
	# Фасад с воротами.
	var pier := (half.x * 2.0 - 3.2) * 0.5
	for sx: float in [-1.0, 1.0]:
		box(Vector3(pier, height, 0.5),
			center + Vector3(sx * (half.x - pier * 0.5), height * 0.5, half.y), STONE, true)
	box(Vector3(3.2, 1.0, 0.5), center + Vector3(0.0, height - 0.5, half.y), STONE)
	door(center + Vector3(0.0, 0.0, half.y), Vector2(3.0, height - 1.2), WOOD, WOOD_DARK)
	gable_roof(center + Vector3(0.0, height + 0.9, 0.0),
		Vector2(half.x * 2.0, half.y * 2.0), 1.8, WOOD_DARK)
	# Штабели у входа.
	for i: int in 3:
		box(Vector3(1.1, 1.1, 1.1), center + Vector3(-3.4 + i * 0.2, 0.55 + i * 1.1, half.y + 2.2),
			WOOD, i == 0)
	cylinder(0.55, 1.2, center + Vector3(3.4, 0.6, half.y + 2.0), WOOD_DARK, true)
	cylinder(0.55, 1.2, center + Vector3(4.4, 0.6, half.y + 1.2), WOOD_DARK, true)
	lamp(center + Vector3(0.0, 3.2, half.y + 1.4), Color(0.9, 0.85, 0.7), 2.0, 12.0)
	return center + Vector3(0.0, 0.9, half.y + 1.6)

# --- Спуск в Разлом: арка, ступени вниз, жаровни ---

func build_descend(center: Vector3) -> Vector3:
	var ready := external("descend", center, Vector3(0.0, 0.9, 1.6))
	if ready != Vector3.INF:
		return ready
	if kit != null:
		return _kit_descend(center)
	box(Vector3(10.0, 0.2, 8.0), center + Vector3(0.0, 0.1, 0.0), STONE_DARK)
	for sx: float in [-1.0, 1.0]:
		box(Vector3(1.2, 5.0, 1.2), center + Vector3(sx * 2.8, 2.5, -1.0), STONE, true)
	box(Vector3(6.8, 1.0, 1.4), center + Vector3(0.0, 5.5, -1.0), STONE)
	# Ступени, уходящие в темноту.
	for i: int in 5:
		box(Vector3(4.4 - i * 0.2, 0.3, 1.0),
			center + Vector3(0.0, -0.15 - i * 0.3, -1.6 - i * 1.0), STONE_DARK)
	box(Vector3(4.0, 0.1, 2.0), center + Vector3(0.0, -1.7, -6.6), Color(0.03, 0.03, 0.04))
	for sx: float in [-1.0, 1.0]:
		var brazier := center + Vector3(sx * 2.8, 0.0, 0.8)
		cylinder(0.45, 1.2, brazier + Vector3(0.0, 0.6, 0.0), METAL, true)
		glow(Vector3(0.7, 0.25, 0.7), brazier + Vector3(0.0, 1.3, 0.0), Color(1.0, 0.5, 0.15), 3.0)
		lamp(brazier + Vector3(0.0, 1.8, 0.0), Color(1.0, 0.55, 0.2), 2.6, 10.0)
	return center + Vector3(0.0, 0.9, 1.6)

# --- Кровля и стены: детали, которых не даёт голая коробка ---

## Двускатная крыша: призма-конёк плюс свес по краям.
func gable_roof(center: Vector3, size: Vector2, height: float, color: Color,
		yaw: float = 0.0) -> void:
	# PrismMesh уже имеет профиль крыши: треугольник в плоскости XY, вытянутый по Z.
	# Разворачивать его по X нельзя — конёк ляжет набок и получится стена.
	var mesh := PrismMesh.new()
	var ridge_along_x := size.x >= size.y
	if ridge_along_x:
		mesh.size = Vector3(size.y + 0.8, height, size.x + 0.8)
	else:
		mesh.size = Vector3(size.x + 0.8, height, size.y + 0.8)
	var ridge_yaw := yaw + (PI * 0.5 if ridge_along_x else 0.0)
	_spawn(mesh, center, color, ridge_yaw)

## Бревенчатая стена: ряд горизонтальных брёвен вместо плоской плиты.
func log_wall(center: Vector3, length: float, height: float, color: Color,
		along_x: bool, blocking: bool = true) -> void:
	var rows := maxi(2, int(height / 0.42))
	var radius := height / float(rows) * 0.5
	for i: int in rows:
		var y := radius + float(i) * radius * 2.0
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length
		var node := _spawn(mesh, center + Vector3(0.0, y, 0.0),
			color.darkened(0.05 * float(i % 2)), 0.0)
		node.rotation.z = deg_to_rad(90.0)
		if not along_x:
			node.rotation.y = deg_to_rad(90.0)
	if blocking:
		var size := Vector3(length, height, radius * 2.0) if along_x \
			else Vector3(radius * 2.0, height, length)
		_block(size, center + Vector3(0.0, height * 0.5, 0.0), 0.0)

## Оконный проём с рамой и переплётом.
func window(center: Vector3, size: Vector2, frame: Color, glass: Color,
		along_x: bool = true) -> void:
	var depth := 0.12
	var outer := Vector3(size.x, size.y, depth) if along_x else Vector3(depth, size.y, size.x)
	box(outer, center, frame)
	var inner := Vector3(size.x - 0.16, size.y - 0.16, depth * 0.6) if along_x \
		else Vector3(depth * 0.6, size.y - 0.16, size.x - 0.16)
	var pane := box(inner, center + Vector3(0.0, 0.0, 0.02 if along_x else 0.0), glass)
	var mat: StandardMaterial3D = pane.material_override
	mat.emission_enabled = true
	mat.emission = glass
	mat.emission_energy_multiplier = 0.8
	var bar := Vector3(size.x, 0.06, depth * 0.8) if along_x else Vector3(depth * 0.8, 0.06, size.x)
	box(bar, center, frame)
	var post := Vector3(0.06, size.y, depth * 0.8) if along_x else Vector3(depth * 0.8, size.y, 0.06)
	box(post, center, frame)

## Дверь с косяком и створкой.
func door(center: Vector3, size: Vector2, frame: Color, leaf: Color) -> void:
	box(Vector3(size.x + 0.3, 0.2, 0.3), center + Vector3(0.0, size.y, 0.0), frame)
	for side: float in [-1.0, 1.0]:
		box(Vector3(0.16, size.y, 0.3), center + Vector3(side * (size.x * 0.5 + 0.08),
			size.y * 0.5, 0.0), frame)
	box(Vector3(size.x, size.y, 0.16), center + Vector3(0.0, size.y * 0.5, 0.0), leaf, true)
	cylinder(0.06, 0.16, center + Vector3(size.x * 0.3, size.y * 0.5, -0.12), Color(0.6, 0.55, 0.35))

## Готовая модель постройки вместо процедурной сборки. Возвращает точку
## взаимодействия или Vector3.INF, если модели нет и надо строить примитивами.
func external(model_name: String, center: Vector3, anchor_offset: Vector3) -> Vector3:
	var node := ModelLibrary.instantiate("village", model_name)
	if node == null:
		return Vector3.INF
	node.position = center
	root.add_child(node)
	var box := ModelLibrary.footprint(node)
	if box.size.x > 0.1 and box.size.z > 0.1:
		blockers.append(Rect2(
			center.x + box.position.x - player_radius,
			center.z + box.position.z - player_radius,
			box.size.x + player_radius * 2.0, box.size.z + player_radius * 2.0))
	return center + anchor_offset

## Манекены и стойка перед залом — кит их не содержит, собираем сами.
func _training_yard(spot: Vector3) -> void:
	for i: int in 3:
		var post := spot + Vector3(-3.0 + float(i) * 3.0, -0.9, 2.6)
		box(Vector3(0.32, 2.0, 0.32), post + Vector3(0.0, 1.0, 0.0), WOOD, true)
		box(Vector3(1.5, 0.28, 0.28), post + Vector3(0.0, 1.55, 0.0), WOOD_DARK)
		sphere(0.26, post + Vector3(0.0, 2.15, 0.0), CLOTH)
	var rack := spot + Vector3(4.6, -0.9, 1.4)
	box(Vector3(0.2, 1.9, 0.2), rack + Vector3(0.0, 0.95, -1.2), WOOD, true)
	box(Vector3(0.2, 1.9, 0.2), rack + Vector3(0.0, 0.95, 1.2), WOOD, true)
	box(Vector3(0.15, 0.15, 2.6), rack + Vector3(0.0, 1.8, 0.0), WOOD)
	for i: int in 4:
		box(Vector3(0.14, 1.3, 0.14), rack + Vector3(0.0, 1.25, -0.9 + float(i) * 0.6), METAL)

## Сад на ките: плетень из модулей, грядки, деревья и кусты из Nature Kit.
func _kit_garden(center: Vector3) -> Vector3:
	var unit := VillageKit.KIT_SCALE
	box(Vector3(14.0, 0.15, 12.0), center + Vector3(0.0, 0.07, 0.0), Color(0.26, 0.23, 0.17))
	# Забор по периметру с проходом со стороны двора.
	for i: int in 5:
		var x := -2.0 + float(i)
		if absf(x + 0.0) < 0.6:
			continue
		kit.piece("fence", (center / unit) + Vector3(x, 0.0, 2.2), 3)
		kit.piece("fence", (center / unit) + Vector3(x, 0.0, -2.2), 1)
	for i: int in 5:
		var z := -2.2 + float(i) * 1.1
		kit.piece("fence", (center / unit) + Vector3(-2.4, 0.0, z), 2)
		kit.piece("fence", (center / unit) + Vector3(2.4, 0.0, z), 0)
	for row: int in 4:
		var bed := center + Vector3(0.0, 0.0, -3.6 + float(row) * 2.2)
		box(Vector3(10.0, 0.4, 1.2), bed + Vector3(0.0, 0.2, 0.0), Color(0.3, 0.21, 0.14))
		for i: int in 9:
			kit.nature("plant_bushDetailed", (bed + Vector3(-4.4 + float(i) * 1.1, 0.4, 0.0)) / unit, 0.5)
	kit.nature("tree_oak", (center + Vector3(-5.6, 0.0, 4.4)) / unit, 0.6)
	kit.nature("tree_default", (center + Vector3(5.4, 0.0, 4.2)) / unit, 0.55)
	kit.nature("rock_largeA", (center + Vector3(-5.2, 0.0, -3.8)) / unit, 0.5)
	kit.nature("stump_round", (center + Vector3(4.8, 0.0, -4.2)) / unit, 0.5)
	cylinder(0.6, 1.2, center + Vector3(-4.8, 0.6, 3.6), WOOD_DARK, true)
	return center + Vector3(0.0, 0.9, 5.6)

## Прямоугольное препятствие в метрах — для оград и площадок.
func block_rect(center: Vector3, size: Vector2) -> void:
	blockers.append(Rect2(center.x - size.x * 0.5 - player_radius,
		center.z - size.y * 0.5 - player_radius,
		size.x + player_radius * 2.0, size.y + player_radius * 2.0))

## Спуск в Разлом на ките замка: арка, пилоны, каменные ступени, флаги,
## жаровни из кладбищенского кита.
func _kit_descend(center: Vector3) -> Vector3:
	var unit := VillageKit.KIT_SCALE
	var cell := center / unit
	box(Vector3(12.0, 0.2, 10.0), center + Vector3(0.0, 0.1, 0.0), STONE_DARK)
	kit.piece("tower-square-arch", cell + Vector3(0.0, 0.0, -0.4), 0, VillageKit.CASTLE)
	for side: float in [-1.0, 1.0]:
		kit.piece("wall-pillar", cell + Vector3(side, 0.0, -0.4), 0, VillageKit.CASTLE)
		kit.piece("flag", cell + Vector3(side, 1.0, -0.2), 0, VillageKit.CASTLE)
		var brazier := center + Vector3(side * 3.4, 0.0, 1.6)
		kit.piece("fire-basket", brazier / unit, 0, VillageKit.GRAVE)
		glow(Vector3(0.6, 0.2, 0.6), brazier + Vector3(0.0, 0.9, 0.0), Color(1.0, 0.5, 0.15), 3.0)
		lamp(brazier + Vector3(0.0, 1.6, 0.0), Color(1.0, 0.55, 0.2), 2.8, 11.0)
		block_rect(brazier, Vector2(1.0, 1.0))
	# Ступени вниз и темнота под ними.
	for i: int in 5:
		kit.piece("stairs-stone", (center + Vector3(0.0, -0.35 * float(i), -3.0 - 1.4 * float(i))) / unit,
			0, VillageKit.CASTLE)
	box(Vector3(4.0, 0.1, 3.0), center + Vector3(0.0, -2.0, -9.0), Color(0.03, 0.03, 0.04))
	block_rect(center + Vector3(0.0, 0.0, -1.0), Vector2(9.0, 2.0))
	return center + Vector3(0.0, 0.9, 2.2)

## Кузница: настил и столбы из городского кита, горн с жаровней и наковальня
## своей геометрией — готового горна ни в одном ките нет.
func _kit_forge(center: Vector3) -> Vector3:
	var unit := VillageKit.KIT_SCALE
	var cell := center / unit
	for x: int in 3:
		for z: int in 2:
			kit.piece("planks", cell + Vector3(float(x) - 1.0, 0.0, float(z) - 0.5))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-0.5, 0.5]:
			kit.piece("pillar-wood", cell + Vector3(sx, 0.0, sz))
			kit.piece("pillar-wood", cell + Vector3(sx, 1.0, sz))
	_kit_roof(center + Vector3(0.0, 2.0 * unit, 0.0), Vector2(3.2, 2.4), 1.5, WOOD_DARK)
	# Горн, труба и угли.
	var hearth := center + Vector3(0.0, 0.0, -2.4)
	box(Vector3(2.6, 1.3, 1.8), hearth + Vector3(0.0, 0.65, 0.0), STONE, true)
	kit.piece("fire-basket", (hearth + Vector3(0.0, 1.3, 0.0)) / unit, 0, VillageKit.GRAVE)
	glow(Vector3(1.6, 0.2, 1.0), hearth + Vector3(0.0, 1.5, 0.0), Color(1.0, 0.45, 0.12), 3.4)
	kit.piece("chimney", (hearth + Vector3(0.0, 1.3, 0.0)) / unit, 1)
	lamp(hearth + Vector3(0.0, 2.0, 0.8), Color(1.0, 0.55, 0.2), 3.2, 12.0)
	# Наковальня — точка взаимодействия.
	var anvil := center + Vector3(0.0, 0.0, 0.4)
	box(Vector3(0.7, 0.6, 0.7), anvil + Vector3(0.0, 0.4, 0.0), STONE_DARK, true)
	box(Vector3(1.5, 0.35, 0.6), anvil + Vector3(0.0, 0.87, 0.0), METAL)
	kit.piece("cart", (center + Vector3(4.2, 0.0, 1.6)) / unit, 1)
	kit.piece("wheel", (center + Vector3(-4.0, 0.0, 1.8)) / unit)
	kit.piece("stall-bench", (center + Vector3(3.0, 0.0, -1.6)) / unit)
	return anvil + Vector3(0.0, 0.9, 1.6)

## Общая призматическая крыша поверх кит-построек.
func _kit_roof(center: Vector3, size: Vector2, height: float, color: Color) -> void:
	var mesh := PrismMesh.new()
	var ridge_along_x := size.x >= size.y
	var unit := VillageKit.KIT_SCALE
	if ridge_along_x:
		mesh.size = Vector3(size.y * unit, height * unit, size.x * unit)
	else:
		mesh.size = Vector3(size.x * unit, height * unit, size.y * unit)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = center + Vector3(0.0, height * unit * 0.4, 0.0)
	node.rotation.y = PI * 0.5 if ridge_along_x else 0.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	node.material_override = mat
	root.add_child(node)
