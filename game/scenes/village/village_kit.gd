class_name VillageKit
extends RefCounted
## Сборка построек из модульного кита (Kenney Fantasy Town Kit, CC0).
## Модуль кита — куб 1x1x1, панель стены прижата к грани +X, поэтому поворот
## на 90 градусов ставит её на нужную сторону. Всё умножается на KIT_SCALE,
## чтобы дверной проём был по росту героя (1.8 м).

const KIT := "res://assets/models/kenney_town/"
const NATURE := "res://assets/models/kenney_nature/"
const CASTLE := "res://assets/models/kenney_castle/"
const GRAVE := "res://assets/models/kenney_graveyard/"
const KIT_SCALE := 2.2

var root: Node3D
var blockers: Array[Rect2]
var player_radius: float

func _init(parent: Node3D, radius: float, blocker_list: Array[Rect2]) -> void:
	root = parent
	player_radius = radius
	blockers = blocker_list

static func available() -> bool:
	return ResourceLoader.exists(KIT + "wall.glb")

## Ставит модуль кита. cell — координаты в модулях, yaw — четверти оборота.
func piece(model: String, cell: Vector3, quarter_turns: int = 0,
		folder: String = KIT) -> Node3D:
	var path := folder + model + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	var node: Node3D = scene.instantiate()
	node.position = cell * KIT_SCALE
	node.rotation.y = deg_to_rad(90.0 * float(quarter_turns))
	node.scale = Vector3.ONE * KIT_SCALE
	root.add_child(node)
	return node

func nature(model: String, cell: Vector3, scale_factor: float = 1.0) -> Node3D:
	var node := piece(model, cell, 0, NATURE)
	if node != null:
		node.scale = Vector3.ONE * KIT_SCALE * scale_factor
	return node

func block(center: Vector3, size: Vector2) -> void:
	blockers.append(Rect2(
		center.x * KIT_SCALE - size.x * KIT_SCALE * 0.5 - player_radius,
		center.z * KIT_SCALE - size.y * KIT_SCALE * 0.5 - player_radius,
		size.x * KIT_SCALE + player_radius * 2.0,
		size.y * KIT_SCALE + player_radius * 2.0))

## Ряд стен вдоль стороны. side: 0 = +X, 1 = -Z, 2 = -X, 3 = +Z.
func wall_run(origin: Vector3, side: int, count: int, models: Array[String]) -> void:
	var step := Vector3(0.0, 0.0, 1.0) if side % 2 == 0 else Vector3(1.0, 0.0, 0.0)
	for i: int in count:
		var model: String = models[i % models.size()]
		if model.is_empty():
			continue
		# Панель модуля прижата к +X, поэтому четверть оборота равна номеру стороны.
		piece(model, origin + step * float(i), side)

## Коробка дома: пол, стены по периметру с дверью и окнами, двускатная крыша.
## Возвращает точку взаимодействия перед дверью.
func house(center: Vector3, modules: Vector2i, storeys: int, door_index: int) -> Vector3:
	var half := Vector3(float(modules.x - 1) * 0.5, 0.0, float(modules.y - 1) * 0.5)
	var base := center - half
	for x: int in modules.x:
		for z: int in modules.y:
			piece("planks", base + Vector3(x, 0.0, z))
	for level: int in storeys:
		var y := float(level)
		var front: Array[String] = []
		for x: int in modules.x:
			if level == 0 and x == door_index:
				front.append("wall-door")
			elif level == 0:
				front.append("wall-window-shutters")
			else:
				front.append("wall-window-glass" if x % 2 == 1 else "wall")
		var plain: Array[String] = ["wall"]
		var windows: Array[String] = ["wall", "wall-window-small"]
		# Фасад смотрит на +Z (во двор), остальные стороны глухие с окнами.
		wall_run(base + Vector3(0.0, y, float(modules.y - 1)), 3, modules.x, front)
		wall_run(base + Vector3(0.0, y, 0.0), 1, modules.x, windows)
		wall_run(base + Vector3(0.0, y, 0.0), 2, modules.y, windows)
		wall_run(base + Vector3(float(modules.x - 1), y, 0.0), 0, modules.y, plain)
	_roof(base, modules, storeys)
	block(center, Vector2(float(modules.x), float(modules.y)))
	return (center + Vector3(float(door_index) - half.x, 0.0, half.z + 1.2)) * KIT_SCALE \
		+ Vector3(0.0, 0.9, 0.0)

## Крыша своя, а не из кита: собрать скаты из модулей вслепую не выходит,
## а призма даёт предсказуемый конёк и садится на стены точно по габаритам.
func _roof(base: Vector3, modules: Vector2i, storeys: int) -> void:
	var center := base + Vector3(float(modules.x - 1) * 0.5, float(storeys),
		float(modules.y - 1) * 0.5)
	var mesh := PrismMesh.new()
	var ridge_along_x := modules.x >= modules.y
	var span := Vector2(float(modules.x), float(modules.y))
	if ridge_along_x:
		mesh.size = Vector3(span.y + 0.2, 0.75, span.x + 0.2)
	else:
		mesh.size = Vector3(span.x + 0.2, 0.75, span.y + 0.2)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = (center + Vector3(0.0, 0.38, 0.0)) * KIT_SCALE
	node.rotation.y = PI * 0.5 if ridge_along_x else 0.0
	node.scale = Vector3.ONE * KIT_SCALE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.24, 0.18)
	mat.roughness = 0.95
	node.material_override = mat
	root.add_child(node)

## Модуль stone-wall из кладбищенского кита прижат к грани -Z, поэтому четверти
## оборота считаются от неё: -Z = 0, -X = 1, +Z = 2, +X = 3.
func stone_wall(cell: Vector3, side: int, model: String = "stone-wall") -> void:
	piece(model, cell, side, GRAVE)

## Ряд низких каменных стен вдоль стороны с пропуском под дверной проём.
func stone_run(origin: Vector3, side: int, count: int, gap_index: int = -1) -> void:
	var step := Vector3(1.0, 0.0, 0.0) if side % 2 == 0 else Vector3(0.0, 0.0, 1.0)
	for i: int in count:
		if i == gap_index:
			continue
		stone_wall(origin + step * float(i), side)
