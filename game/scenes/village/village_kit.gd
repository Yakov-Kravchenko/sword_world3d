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

## Дом собирает VillageBuildings, а не модули кита: модульные стены дают коробку
## с плоской крышей, а северную деревню держат крутой скат с большими свесами,
## фахверк и каменный цоколь. Сигнатура прежняя, вызовы построек не меняются.
## door_index больше не нужен — дверь всегда по центру фасада.
func house(center: Vector3, modules: Vector2i, storeys: int, door_index: int) -> Vector3:
	var world := center * KIT_SCALE
	var size := Vector2(float(modules.x), float(modules.y)) * KIT_SCALE
	# Фасадом к центру деревни: улица должна читаться домами, а не задворками.
	var yaw := atan2(-world.x, -world.z)
	# Дом повёрнут, поэтому препятствие описываем квадратом по большей стороне:
	# прямоугольник в плане после поворота уже не совпал бы с габаритом.
	var span := float(maxi(modules.x, modules.y))
	block(center, Vector2(span, span))
	return builder().house(world, size, storeys, yaw)


## Генератор общий на всю деревню: материалы домов создаются один раз, иначе
## каждая постройка тащила бы свой комплект текстур.
static var _shared_builder: VillageBuildings

func builder() -> VillageBuildings:
	if _shared_builder == null or _shared_builder.root != root:
		_shared_builder = VillageBuildings.new(root)
	return _shared_builder


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


## Генератор утвари, общий на деревню. Ленивое создание: препятствия и ландшафт
## к моменту первой постройки уже готовы.
static var _shared_gear: VillageGear

func gear() -> VillageGear:
	if _shared_gear == null or _shared_gear.root != root:
		_shared_gear = VillageGear.new(root, builder(), VillageLook.current, blockers)
	return _shared_gear
