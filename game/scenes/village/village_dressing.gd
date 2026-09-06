class_name VillageDressing
extends RefCounted
## Обстановка деревни: улица, рынок, дворы у построек, ферма, берег и подлесок.
##
## Всё, кроме травы, собирает VillageGear из примитивов — моделей кита здесь
## больше нет. И расставляется не случайной россыпью, а по правилам: фонари
## равным шагом вдоль улицы, бочки рядом у стены, лотки в линию лицом к дороге.
## Случайный разброс читается как мусор, даже когда каждый предмет сам по себе
## хорош, — это и делало двор неопрятным.

const NATURE := "res://assets/models/kenney_nature/"

## Насколько предмет должен отстоять от оси улицы, чтобы по ней можно было идти.
const ROAD_CLEARANCE := 2.9

var look: VillageLook
var gear: VillageGear
var blockers: Array[Rect2]
var roads: Array
var places: Dictionary
var _rng: RandomNumberGenerator


func _init(village_look: VillageLook, obstacles: Array[Rect2], street_lines: Array,
		station_places: Dictionary) -> void:
	look = village_look
	# Массив общий с деревней: препятствия отсюда сразу учитываются при поиске
	# свободных мест для следующих предметов.
	blockers = obstacles
	roads = street_lines
	places = station_places
	_rng = RandomNumberGenerator.new()
	_rng.seed = 771144
	gear = VillageGear.new(look.root, VillageBuildings.new(look.root), look, blockers)


func dress() -> void:
	_market()
	_street_furniture()
	_yards()
	_farm()
	_riverside()
	_woods()
	_yard_grass()


# --- Площадь ---

## Колодец в центре и лотки в линию вдоль улицы, лицом к ней. Ряд читается как
## рынок; те же лотки, расставленные по кругу, — как склад под открытым небом.
func _market() -> void:
	var square := Vector2(-4.5, 0.0)
	if _free(square, 2.0):
		gear.well(square)
	var street := _main_street()
	var along := _direction(street)
	var side := Vector2(-along.y, along.x)
	for i: int in 3:
		var spot := Vector2(2.0, 4.0) + along * (float(i) * 3.4) + side * 3.6
		if not _free(spot, 1.8):
			continue
		# Лоток развёрнут прилавком к дороге.
		gear.stall(spot, atan2(-side.x, -side.y), i % 2 == 0)
	for i: int in 2:
		var spot := square + Vector2(0.0, -3.2 - float(i) * 2.2)
		if _free(spot, 1.4):
			gear.table(spot, 0.0)
			gear.bench(spot + Vector2(0.0, 1.1), 0.0)
			gear.bench(spot + Vector2(0.0, -1.1), PI)


# --- Улица ---

## Фонари равным шагом попеременно с двух сторон. Ровный шаг — главное, что
## отличает улицу от расставленных наугад столбов.
func _street_furniture() -> void:
	for line: PackedVector2Array in roads:
		var walked := 6.0
		var side := 1.0
		for i: int in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var span := a.distance_to(b)
			if span < 0.01:
				continue
			var dir := (b - a) / span
			var off := Vector2(-dir.y, dir.x) * 3.2
			var travelled := 0.0
			while travelled < span:
				travelled += 1.0
				walked += 1.0
				if walked < 13.0:
					continue
				walked = 0.0
				side = -side
				var spot := a + dir * travelled + off * side
				if _blocked_by_props(spot, 1.0) or look.river_distance(spot) < 8.0:
					continue
				gear.lamp_post(spot)
				_block(spot, Vector2(0.8, 0.8))


# --- Дворы у построек ---

## У каждой постройки свой двор: прясло вдоль стороны, обращённой к улице, и
## хозяйство у стены — бочки в ряд, ящики стопкой, телега вдоль забора.
func _yards() -> void:
	var index := 0
	for key: StringName in places:
		var centre: Vector2 = places[key]
		if key == &"descend":
			continue
		# Наружу от центра деревни — туда смотрит фасад, там и двор.
		var out := centre.normalized() if centre.length() > 0.1 else Vector2(0.0, 1.0)
		var along := Vector2(-out.y, out.x)
		var front := centre + out * 7.5
		gear.fence_run(front - along * 5.0, front - along * 1.8)
		gear.fence_run(front + along * 1.8, front + along * 5.0)
		var flank := centre + along * 6.5
		for i: int in 3:
			var spot := flank + out * (float(i) * 1.0 - 1.0)
			if _free(spot, 0.6):
				gear.barrel(spot)
				_block(spot, Vector2(0.8, 0.8))
		var stack := centre - along * 6.5
		if _free(stack, 1.0):
			gear.crate(stack, atan2(along.x, along.y))
			gear.crate(stack + out * 0.85, atan2(along.x, along.y), 0.6)
		var park := centre + out * 5.0 + along * 4.5
		if _free(park, 1.8):
			gear.cart(park, atan2(along.x, along.y))
		# У кузницы и зала — поленница и снопы, у лавки и склада — ящики.
		var utility := centre - out * 6.0
		if _free(utility, 1.6):
			if index % 2 == 0:
				gear.log_pile(utility, atan2(along.x, along.y))
			else:
				gear.hay_bale(utility, atan2(along.x, along.y))
				gear.hay_bale(utility + along * 1.3, atan2(along.x, along.y))
		index += 1


# --- Ферма ---

## Грядки за садом: они объясняют, чем деревня кормится, и дают ровную
## геометрию рядов — глазу нужен участок порядка среди неровностей.
func _farm() -> void:
	if not places.has(&"garden"):
		return
	var centre: Vector2 = places[&"garden"] + Vector2(-7.0, 8.0)
	if _free(centre, 5.0):
		gear.field(centre, Vector2(9.0, 7.0), 0.0)


# --- Берег ---

func _riverside() -> void:
	var placed := 0
	var attempts := 0
	while placed < 40 and attempts < 1200:
		attempts += 1
		var spot := Vector2(_rng.randf_range(-33.0, 33.0), _rng.randf_range(-33.0, 33.0))
		var to_water := look.river_distance(spot)
		if to_water < VillageLook.RIVER_HALF + 0.3 or to_water > VillageLook.RIVER_HALF + 4.5:
			continue
		if _road_distance(spot) < ROAD_CLEARANCE + 2.0 or _blocked_by_props(spot, 1.0):
			continue
		gear.boulder(spot, _rng.randf_range(0.6, 1.9), _rng.randi())
		placed += 1


# --- Зелень ---

## Ели по краям двора и подлесок. Кит остался только для кустов и цветов:
## сделать убедительную мелкую листву примитивами не выходит.
func _woods() -> void:
	var trees := 0
	var attempts := 0
	while trees < 16 and attempts < 500:
		attempts += 1
		var spot := Vector2(_rng.randf_range(-31.0, 31.0), _rng.randf_range(-31.0, 31.0))
		if spot.length() < 19.0 or not _free(spot, 3.2):
			continue
		gear.conifer(spot, _rng.randf_range(9.0, 15.0), _rng.randi())
		_block(spot, Vector2(1.6, 1.6))
		trees += 1
	var bushes := 0
	attempts = 0
	while bushes < 90 and attempts < 2500:
		attempts += 1
		var spot := Vector2(_rng.randf_range(-32.0, 32.0), _rng.randf_range(-32.0, 32.0))
		if not _free(spot, 0.9):
			continue
		var model := NATURE + ("plant_bushDetailed.glb" if _rng.randf() < 0.7
			else "flower_redA.glb")
		var node := look.place(model, look.ground(spot) - Vector3(0.0, 0.12, 0.0),
			_rng.randf_range(0.35, 0.8), look.bark)
		if node == null:
			return
		node.rotation.y = _rng.randf() * TAU
		bushes += 1


## Трава во дворе — MultiMesh с проверкой на постройки и дороги: пучки, растущие
## сквозь стену, разрушают картинку сильнее, чем их отсутствие.
func _yard_grass() -> void:
	var mesh := VillageGear.grass_tuft(_rng)
	if mesh == null:
		return
	var target := 5000
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = target
	var unit := maxf(mesh.get_aabb().size.y, 0.001)
	var blades := look.grass_blade_material()
	var placed := 0
	var attempts := 0
	while placed < target and attempts < target * 6:
		attempts += 1
		var spot := Vector2(_rng.randf_range(-33.0, 33.0), _rng.randf_range(-33.0, 33.0))
		if not _free(spot, 0.5):
			continue
		var height := _rng.randf_range(0.30, 0.62)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU)
		basis = basis.scaled(Vector3.ONE * (height / unit))
		mm.set_instance_transform(placed, Transform3D(basis, look.ground(spot)))
		placed += 1
	mm.visible_instance_count = placed
	var node := MultiMeshInstance3D.new()
	node.name = "YardGrass"
	node.multimesh = mm
	node.material_override = blades
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	look.root.add_child(node)


# --- Общее ---

func _main_street() -> PackedVector2Array:
	for line: PackedVector2Array in roads:
		if line.size() > 3:
			return line
	return roads[0] if not roads.is_empty() else PackedVector2Array()


func _direction(line: PackedVector2Array) -> Vector2:
	if line.size() < 2:
		return Vector2(0.0, -1.0)
	return (line[line.size() - 1] - line[0]).normalized()


## Точка годится, если она не внутри постройки, не на улице, не в реке и не на
## крутом склоне. Правило одно на всю обстановку: разные правила для разных
## предметов разошлись бы, и что-то одно всё равно полезло бы в стену.
func _free(spot: Vector2, clearance: float) -> bool:
	if _blocked_by_props(spot, clearance):
		return false
	if _road_distance(spot) < ROAD_CLEARANCE + clearance:
		return false
	if look.river_distance(spot) < VillageLook.RIVER_HALF + 2.0:
		return false
	return look.slope_at(spot.x, spot.y) < 0.42


func _blocked_by_props(spot: Vector2, clearance: float) -> bool:
	for rect: Rect2 in blockers:
		if rect.grow(clearance).has_point(spot):
			return true
	return false


func _road_distance(spot: Vector2) -> float:
	var best := INF
	for line: PackedVector2Array in roads:
		for i: int in line.size() - 1:
			var a := line[i]
			var ab := line[i + 1] - a
			var t := clampf((spot - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, spot.distance_to(a + ab * t))
	return best


func _block(spot: Vector2, size: Vector2) -> void:
	blockers.append(Rect2(spot - size * 0.5, size))
