class_name VillageLook
extends RefCounted
## Внешний вид хаба: небо, солнце, рельеф, река, дороги, ограда и растительность.
##
## Вынесено из village.gd: подбор освещения и генерация рельефа — отдельная
## задача, держать её рядом с логикой ходьбы неудобно. Строится кодом, как и
## вся остальная деревня, поэтому village.tscn остаётся пустым узлом.

const NATURE := "res://assets/models/kenney_nature/"
const SKY_SHADER := "res://game/scenes/village/sky_clouds.gdshader"
const TERRAIN_SHADER := "res://game/scenes/village/terrain.gdshader"
const TEXTURES := "res://assets/textures/"
const WATER_SHADER := "res://game/scenes/village/water.gdshader"
const GRASS_SHADER := "res://game/scenes/village/grass.gdshader"

## Дальше этого радиуса строить нечего: всё съедает туман. Шаг сетки при этом
## должен оставаться мелким — русло реки шириной 10 м на редкой сетке
## превратилось бы в лестницу из двух ступеней.
const TERRAIN_EXTENT := 360.0
const TERRAIN_CELLS := 340

## Двор больше не идеально плоский: под ногами пологая волна. Ровными остаются
## только площадки под постройки — их выравнивает add_pad.
const YARD_RELIEF := 2.8
const HILL_FADE := 60.0
const HILL_HEIGHT := 9.0
const FLAT_MARGIN := 5.0
const MOUNTAIN_START := 60.0
const MOUNTAIN_FADE := 185.0
const MOUNTAIN_HEIGHT := 195.0

## Река. Уровень воды ниже нуля, а рельеф двора всегда неотрицательный —
## поэтому вода стоит только в прорезанном русле и не разливается лужами.
const WATER_LEVEL := -0.3
const RIVER_HALF := 6.0
const RIVER_BANK := 6.5
const RIVER_DEPTH := 1.2

## Ограда двора — низкий вал, а не глухая стена в 6 метров: с уровня глаз
## (камера на 1.7 м) стена закрывала бы и лес, и горы, ради которых всё это.
const RAMPART_HEIGHT := 2.4

## Выше границы леса деревья не растут — так хребет читается как хребет.
const TREE_LINE := 46.0

## Последний созданный ландшафт. Нужен генераторам утвари: они создаются
## глубоко внутри построек, куда ссылку иначе пришлось бы тащить через пять
## слоёв вызовов.
static var current: VillageLook

var root: Node3D
var yard: float
var rng: RandomNumberGenerator
var foliage: StandardMaterial3D
var bark: StandardMaterial3D
var stone: StandardMaterial3D
var grass_mat: StandardMaterial3D

var _hills: FastNoiseLite
var _ridges: FastNoiseLite
var _forest: FastNoiseLite
var _yard_noise: FastNoiseLite
var _pads: Array[Dictionary] = []
var _pads_bounds := Rect2()
var _paths: Array[Dictionary] = []
var _river: PackedVector2Array
var _river_bounds := Rect2()
var _road_mat: StandardMaterial3D


func _init(parent: Node3D, yard_limit: float) -> void:
	root = parent
	yard = yard_limit
	current = self
	# Фиксированное зерно: деревня должна выглядеть одинаково при каждом запуске,
	# иначе игрок не запомнит её силуэт.
	rng = RandomNumberGenerator.new()
	rng.seed = 20260906
	_yard_noise = FastNoiseLite.new()
	_yard_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_yard_noise.frequency = 0.017
	_yard_noise.fractal_octaves = 2
	_yard_noise.seed = 5
	_hills = FastNoiseLite.new()
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.010
	_hills.fractal_octaves = 3
	_hills.seed = 11
	_ridges = FastNoiseLite.new()
	_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridges.frequency = 0.0026
	_ridges.fractal_octaves = 3
	_ridges.fractal_gain = 0.45
	_ridges.seed = 29
	# Плотность леса: деревья садятся только там, где шум выше порога. Без этого
	# они ложатся равномерной сеткой — сверху это читается как посадка, а не лес.
	_forest = FastNoiseLite.new()
	_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest.frequency = 0.012
	_forest.fractal_octaves = 3
	_forest.seed = 77
	_build_river_path()
	_build_palette()


func build() -> void:

	_build_environment()
	_build_sun()
	_build_terrain()
	_build_water()
	_build_rampart()
	_scatter_trees()
	_scatter_rocks()
	_scatter_grass()


# --- Рельеф ---

## Русло задано ломаной и уходит далеко за границы двора: река, обрывающаяся
## у ограды, сразу выдаёт декорацию.
func _build_river_path() -> void:
	_river = PackedVector2Array([
		Vector2(-90.0, 30.0), Vector2(-52.0, 24.0), Vector2(-24.0, 20.0),
		Vector2(0.0, 18.0), Vector2(24.0, 20.0), Vector2(52.0, 26.0),
		Vector2(92.0, 34.0)])
	_river = _smooth(_river, 2)
	_river_bounds = _bounds_of(_river).grow(RIVER_HALF + RIVER_BANK + 2.0)


## Площадка под постройку: круг, выровненный в одну высоту, с плавным съездом.
## Регистрировать нужно до build() — меш строится уже с учётом площадок.
func add_pad(center: Vector2, radius: float, blend: float) -> void:
	_pads.append({
		"c": center, "r": radius, "b": blend,
		"y": _natural(center.x, center.y)})
	var box := Rect2(center - Vector2(radius + blend, radius + blend),
		Vector2(radius + blend, radius + blend) * 2.0)
	_pads_bounds = box if _pads.size() == 1 else _pads_bounds.merge(box)


## Высота земли в точке. Единственный источник правды: по ней строится меш, по
## ней же расставляются постройки, деревья и трава — ничто не висит в воздухе.
func height_at(x: float, z: float) -> float:
	var h := _natural(x, z)
	h = _apply_paths(x, z, h)
	h = _apply_pads(x, z, h)
	return _apply_river(x, z, h)


## Рельеф без площадок и русла. Нужен отдельно: высоту площадки берём именно
## отсюда, иначе она зависела бы от порядка регистрации.
func _natural(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	# Пологая волна идёт по всей карте, включая двор: если гасить её у ограды,
	# на границе появляется заметный уступ.
	# Смещение вверх: двор должен лежать выше полосы прибрежной грязи, иначе
	# шейдер красит грязью весь посёлок.
	var base := 1.1 + (_yard_noise.get_noise_2d(x, z) * 0.5 + 0.5) * YARD_RELIEF
	var hill_t := clampf((r - (yard + FLAT_MARGIN)) / HILL_FADE, 0.0, 1.0)
	var hills := _hills.get_noise_2d(x, z) * HILL_HEIGHT * hill_t * hill_t
	var mount_t := clampf((r - (yard + MOUNTAIN_START)) / MOUNTAIN_FADE, 0.0, 1.0)
	# Модуль шума даёт острые гребни вместо мягких куполов, степень их заостряет:
	# без этого «горы» выглядят как холмы, только выше.
	var ridge := 1.0 - absf(_ridges.get_noise_2d(x, z))
	ridge = pow(ridge, 2.0)
	return base + hills + ridge * MOUNTAIN_HEIGHT * mount_t * mount_t


func _apply_pads(x: float, z: float, h: float) -> float:
	# Общая рамка всех площадок: функция высоты вызывается сотни тысяч раз,
	# и перебирать список для каждой вершины карты незачем.
	if _pads.is_empty() or not _pads_bounds.has_point(Vector2(x, z)):
		return h
	var point := Vector2(x, z)
	for pad: Dictionary in _pads:
		var d := point.distance_to(pad["c"])
		var edge: float = pad["r"] + pad["b"]
		if d >= edge:
			continue
		var t := 1.0 - clampf((d - pad["r"]) / pad["b"], 0.0, 1.0)
		# Сглаживание края: линейный съезд даёт видимый залом по кругу.
		t = t * t * (3.0 - 2.0 * t)
		h = lerpf(h, pad["y"], t)
	return h


func _apply_river(x: float, z: float, h: float) -> float:
	var point := Vector2(x, z)
	if not _river_bounds.has_point(point):
		return h
	var d := river_distance(point)
	var bed := WATER_LEVEL - RIVER_DEPTH
	if d <= RIVER_HALF:
		return minf(h, bed)
	if d >= RIVER_HALF + RIVER_BANK:
		return h
	var t := (d - RIVER_HALF) / RIVER_BANK
	t = t * t * (3.0 - 2.0 * t)
	return minf(h, lerpf(bed, h, t))


## Расстояние до русла в плане. Ломаная, а не кривая: отрезков мало, и считать
## их дешевле — важно, функция высоты вызывается очень часто.
func river_distance(point: Vector2) -> float:
	var best := INF
	for i: int in _river.size() - 1:
		var a := _river[i]
		var ab := _river[i + 1] - a
		var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, point.distance_to(a + ab * t))
	return best


## Нормаль считаем из самой функции высоты, а не из намотки треугольников:
## так не важно, в каком порядке PlaneMesh выдал вершины.
func normal_at(x: float, z: float) -> Vector3:
	var d := 1.2
	return Vector3(
		height_at(x - d, z) - height_at(x + d, z),
		2.0 * d,
		height_at(x, z - d) - height_at(x, z + d)).normalized()


func slope_at(x: float, z: float) -> float:
	return 1.0 - normal_at(x, z).y


## Точка на земле — самый частый запрос снаружи модуля.
func ground(p: Vector2) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y), p.y)


## Сетка ландшафта неравномерная: шаг сгущается к центру по синусу гиперболы.
## При тех же 340 делениях под ногами получается около 0.4 м на ячейку, а у
## горизонта — 5–6 м. Равномерная сетка на 720 метров дала бы 2 м везде: русло
## реки в две ступени и заметные грани на улицах.
const GRID_CURVE := 2.6

func _grid_axis(i: int) -> float:
	var t := 2.0 * float(i) / float(TERRAIN_CELLS) - 1.0
	return TERRAIN_EXTENT * sinh(GRID_CURVE * t) / sinh(GRID_CURVE)


func _build_terrain() -> void:
	var n := TERRAIN_CELLS + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	norms.resize(n * n)
	uvs.resize(n * n)
	for ix: int in n:
		var x := _grid_axis(ix)
		for iz: int in n:
			var z := _grid_axis(iz)
			var at := ix * n + iz
			verts[at] = Vector3(x, height_at(x, z), z)
			# UV нужны только для расчёта касательных: сам шейдер берёт
			# координаты из мировой позиции.
			uvs[at] = Vector2(x, z) * 0.02
	# Нормали берём из соседних вершин, а не пересчётом функции высоты: так на
	# вершину приходится один расчёт вместо пяти, и меш строится вчетверо быстрее.
	# Заодно нормаль точно совпадает с геометрией, а не с идеальной поверхностью.
	for ix: int in n:
		for iz: int in n:
			var at := ix * n + iz
			var left := verts[maxi(ix - 1, 0) * n + iz]
			var right := verts[mini(ix + 1, n - 1) * n + iz]
			var back := verts[ix * n + maxi(iz - 1, 0)]
			var ahead := verts[ix * n + mini(iz + 1, n - 1)]
			norms[at] = (ahead - back).cross(right - left).normalized()
	var idx := PackedInt32Array()
	idx.resize(TERRAIN_CELLS * TERRAIN_CELLS * 6)
	var at_index := 0
	for ix: int in TERRAIN_CELLS:
		for iz: int in TERRAIN_CELLS:
			var a := ix * n + iz
			var b := (ix + 1) * n + iz
			idx[at_index] = a
			idx[at_index + 1] = b
			idx[at_index + 2] = b + 1
			idx[at_index + 3] = a
			idx[at_index + 4] = b + 1
			idx[at_index + 5] = a + 1
			at_index += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Касательные считает SurfaceTool: без них карты нормалей легли бы криво.
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_tangents()

	var node := MeshInstance3D.new()
	node.name = "Terrain"
	node.mesh = st.commit()
	node.material_override = _terrain_material()
	root.add_child(node)
	# Коллизия по самому мешу ландшафта: игрок ходит ровно по той земле,
	# которую видит, включая русло реки и откосы улиц.

	node.create_trimesh_collision()


## Улица врезается в рельеф: дорога, положенная поверх холмов, идёт волнами, а
## врезанная — с откосами по краям, как настоящая. Регистрировать до build().
func add_path(points: PackedVector2Array, width: float, blend: float) -> void:
	var line := _resample(_smooth(points, 2), 2.5)
	var profile := PackedFloat32Array()
	for p: Vector2 in line:
		profile.append(_natural(p.x, p.y))
	# Продольное сглаживание профиля: дорога должна идти ровным уклоном, а не
	# повторять каждую кочку под собой.
	for _pass: int in 8:
		var next := profile.duplicate()
		for i: int in range(1, profile.size() - 1):
			next[i] = (profile[i - 1] + profile[i] * 2.0 + profile[i + 1]) * 0.25
		profile = next
	_paths.append({
		"line": line, "profile": profile, "half": width * 0.5, "blend": blend,
		"box": _bounds_of(line).grow(width + blend + 2.0)})


func _apply_paths(x: float, z: float, h: float) -> float:
	if _paths.is_empty():
		return h
	var point := Vector2(x, z)
	for path: Dictionary in _paths:
		var box: Rect2 = path["box"]
		if not box.has_point(point):
			continue
		var line: PackedVector2Array = path["line"]
		var profile: PackedFloat32Array = path["profile"]
		var best := INF
		var level := h
		for i: int in line.size():
			var d := point.distance_squared_to(line[i])
			if d < best:
				best = d
				level = profile[i]
		var distance := sqrt(best)
		var half: float = path["half"]
		var blend: float = path["blend"]
		if distance >= half + blend:
			continue
		var t := 1.0 - clampf((distance - half) / blend, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		h = lerpf(h, level, t)
	return h


## Ландшафт на фотосканных материалах Poly Haven (CC0). Процедурный шум остался
## только запасным вариантом: если папки с текстурами нет, деревня всё равно
## должна строиться, а не падать.
func _terrain_material() -> Material:
	if not ResourceLoader.exists(TERRAIN_SHADER) or _tex("forest_ground_04", "diff") == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_texture = _noise_texture(0.009, [
			Color(0.16, 0.20, 0.09), Color(0.27, 0.31, 0.15), Color(0.36, 0.38, 0.21)])
		fallback.normal_enabled = true
		fallback.normal_texture = _noise_normal(0.022, 4.0)
		fallback.uv1_scale = Vector3(64.0, 64.0, 1.0)
		fallback.roughness = 1.0
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = load(TERRAIN_SHADER)
	# Основа земли — лесная подстилка: aerial_grass_rock снят с высоты и вблизи
	# читается как сухой песок.
	_bind(mat, "grass", "forest_ground_04")
	_bind(mat, "rock", "cliff_side")
	_bind(mat, "snow", "snow_02")
	_bind(mat, "dirt", "brown_mud_03")
	# Снеговая линия выше границы леса: белыми должны быть только вершины.
	mat.set_shader_parameter("snow_line", 92.0)
	mat.set_shader_parameter("snow_fade", 34.0)
	mat.set_shader_parameter("rock_slope", 0.42)
	mat.set_shader_parameter("dirt_level", WATER_LEVEL + 0.5)
	return mat


## Три карты одного материала разом: цвет, нормали и шероховатость.
func _bind(mat: ShaderMaterial, slot: String, set_name: String) -> void:
	mat.set_shader_parameter(slot + "_diff", _tex(set_name, "diff"))
	mat.set_shader_parameter(slot + "_norm", _tex(set_name, "nor_gl"))
	mat.set_shader_parameter(slot + "_rough", _tex(set_name, "rough"))


## Текстура из скачанного набора. null означает «набора нет» — вызывающий код
## обязан иметь запасной вариант.
func _tex(set_name: String, map: String) -> Texture2D:
	var path := "%s%s/%s_%s_1k.jpg" % [TEXTURES, set_name, set_name, map]
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## Материал из набора: цвет, нормали, шероховатость и трипланарная развёртка
## по мировым координатам. Развёртки у коробок нет, поэтому иначе никак.
func _pbr(set_name: String, scale: float, fallback: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var diff := _tex(set_name, "diff")
	if diff == null:
		mat.albedo_color = fallback
		mat.roughness = 1.0
		mat.metallic = 0.0
		return mat
	mat.albedo_texture = diff
	mat.normal_enabled = true
	mat.normal_texture = _tex(set_name, "nor_gl")
	mat.normal_scale = 1.2
	mat.roughness_texture = _tex(set_name, "rough")
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(scale, scale, scale)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

# --- Вода, дороги, мост ---
# Всё это ленты по ломаной: у воды высота постоянная, у дороги — по рельефу,
# у моста — дугой между берегами.

func _build_water() -> void:
	var mesh := _ribbon(_river, (RIVER_HALF + 1.2) * 2.0, WATER_LEVEL, 0.0)
	if mesh == null:
		return
	var node := MeshInstance3D.new()
	node.name = "River"
	node.mesh = mesh
	node.material_override = _water_material()
	# Вода не должна отбрасывать тень: полупрозрачная поверхность даёт от неё
	# сплошное чёрное пятно на дне.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)


func _water_material() -> Material:
	if not ResourceLoader.exists(WATER_SHADER):
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.12, 0.26, 0.30, 0.85)
		fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fallback.roughness = 0.08
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = load(WATER_SHADER)
	mat.set_shader_parameter("wave_normal", _noise_normal(0.09, 2.2))
	return mat


## Дорога — лента по рельефу, а не набор плит: плиты на неровностях торчат
## углами, а лента повторяет землю.
func build_road(points: PackedVector2Array, width: float = 3.4) -> void:
	var mesh := _ribbon(_smooth(points, 2), width, INF, 0.07)
	if mesh == null:
		return
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _road_material()
	root.add_child(node)


## Мост через реку: настил дугой, перила и опоры в воде. Концы садятся ровно на
## высоту берега, поэтому стыка с дорогой не видно.
func build_bridge(a: Vector2, b: Vector2, width: float = 3.0) -> void:
	var ya := height_at(a.x, a.y)
	var yb := height_at(b.x, b.y)
	var peak := WATER_LEVEL + 2.0
	var steps := 18
	var deck := PackedVector3Array()
	for i: int in steps + 1:
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var base := lerpf(ya, yb, t)
		# Подъём по синусу: на концах ноль, в середине — полная высота арки.
		deck.append(Vector3(p.x, maxf(base, lerpf(base, peak, sin(t * PI))), p.y))
	var dir := (b - a).normalized()
	var side := Vector3(-dir.y, 0.0, dir.x) * width * 0.5
	var wood := _pbr("medieval_wood", 0.6, Color(0.24, 0.17, 0.11))

	for i: int in steps:
		var from := deck[i]
		var to := deck[i + 1]
		var mid := (from + to) * 0.5
		var span := from.distance_to(to)
		var plank := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, 0.18, span + 0.05)
		plank.mesh = mesh
		plank.position = mid
		plank.rotation.y = atan2(dir.x, dir.y)
		plank.material_override = wood
		root.add_child(plank)
		rack_solid(plank, mesh.size)
		# Перила по обеим сторонам секции.
		for s: float in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var rail_mesh := BoxMesh.new()
			rail_mesh.size = Vector3(0.14, 0.62, span + 0.05)
			rail.mesh = rail_mesh
			rail.position = mid + side * s + Vector3(0.0, 0.38, 0.0)
			rail.rotation.y = plank.rotation.y
			rail.material_override = wood
			root.add_child(rail)
			rack_solid(rail, rail_mesh.size)
	# Опоры: без них настил висит над водой без причины.
	for t: float in [0.3, 0.7]:
		var top: Vector3 = deck[int(float(steps) * t)]
		for s: float in [-1.0, 1.0]:
			var pillar := MeshInstance3D.new()
			var pillar_mesh := CylinderMesh.new()
			pillar_mesh.top_radius = 0.24
			pillar_mesh.bottom_radius = 0.3
			pillar_mesh.height = top.y - (WATER_LEVEL - RIVER_DEPTH)
			pillar.mesh = pillar_mesh
			pillar.position = Vector3(top.x, (top.y + WATER_LEVEL - RIVER_DEPTH) * 0.5,
				top.z) + side * s * 0.8
			pillar.material_override = wood
			root.add_child(pillar)


## Общий построитель лент. flat_y = INF означает «идти по рельефу».
func _ribbon(points: PackedVector2Array, width: float, flat_y: float,
		lift: float) -> ArrayMesh:
	var samples := _resample(points, 1.8)
	if samples.size() < 2:
		return null
	var flat := not is_inf(flat_y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for i: int in samples.size() - 1:
		var a := samples[i]
		var b := samples[i + 1]
		var delta := b - a
		var span := delta.length()
		if span < 0.001:
			continue
		var dir := delta / span
		var off := Vector2(-dir.y, dir.x) * width * 0.5
		var v0 := _ribbon_point(a - off, flat_y, lift)
		var v1 := _ribbon_point(a + off, flat_y, lift)
		var v2 := _ribbon_point(b + off, flat_y, lift)
		var v3 := _ribbon_point(b - off, flat_y, lift)
		# UV.x идёт поперёк ленты (0..1) — по нему шейдер воды считает берег.
		# UV.y — метры вдоль, чтобы булыжник не растягивался на длинных участках.
		_ribbon_quad(st, v0, v1, v2, v3, along * 0.5, (along + span) * 0.5, flat)
		along += span
	st.generate_tangents()
	return st.commit()


func _ribbon_point(p: Vector2, flat_y: float, lift: float) -> Vector3:
	if is_inf(flat_y):
		return Vector3(p.x, height_at(p.x, p.y) + lift, p.y)
	return Vector3(p.x, flat_y, p.y)


func _ribbon_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3,
		v3: Vector3, u0: float, u1: float, flat: bool) -> void:
	var corners := [v0, v1, v2, v3]
	var uvs := [Vector2(0.0, u0), Vector2(1.0, u0), Vector2(1.0, u1), Vector2(0.0, u1)]
	# Намотку не угадываем: у материалов ленты выключено отсечение задних граней,
	# а нормали заданы явно, поэтому свет ложится правильно в любом случае.
	for index: int in [0, 1, 2, 0, 2, 3]:
		var v: Vector3 = corners[index]
		st.set_normal(Vector3.UP if flat else normal_at(v.x, v.z))
		st.set_uv(uvs[index])
		st.add_vertex(v)


## Мостовая: булыжник со сканом, а не клеточный шум. UV у ленты свои
## (поперёк 0..1, вдоль в метрах), поэтому трипланар здесь не нужен.
func _road_material() -> StandardMaterial3D:
	if _road_mat != null:
		return _road_mat
	var mat := StandardMaterial3D.new()
	var diff := _tex("cobblestone_floor_08", "diff")
	if diff == null:
		mat.albedo_texture = _cellular_texture()
		mat.normal_enabled = true
		mat.normal_texture = _cellular_normal()
	else:
		mat.albedo_texture = diff
		mat.normal_enabled = true
		mat.normal_texture = _tex("cobblestone_floor_08", "nor_gl")
		mat.roughness_texture = _tex("cobblestone_floor_08", "rough")
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.normal_scale = 1.6
	# Скан булыжника тёмный и «мокрый»; осветляем, иначе улица выглядит после дождя.
	mat.albedo_color = Color(1.35, 1.30, 1.22)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Поперёк ленты укладываем примерно два тайла, вдоль — по метражу из UV.
	mat.uv1_scale = Vector3(2.0, 1.0, 1.0)
	_road_mat = mat
	return mat


## Ломаную сглаживаем по Чайкину: улица из прямых отрезков с острыми поворотами
## читается как схема, а не как дорога.
func _smooth(points: PackedVector2Array, passes: int) -> PackedVector2Array:
	var current := points
	for _pass: int in passes:
		if current.size() < 3:
			return current
		var out := PackedVector2Array([current[0]])
		for i: int in current.size() - 1:
			var a := current[i]
			var b := current[i + 1]
			out.append(a.lerp(b, 0.25))
			out.append(a.lerp(b, 0.75))
		out.append(current[current.size() - 1])
		current = out
	return current


func _resample(points: PackedVector2Array, step: float) -> PackedVector2Array:
	if points.size() < 2:
		return points
	var out := PackedVector2Array()
	for i: int in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var count := maxi(1, int(a.distance_to(b) / step))
		for s: int in count:
			out.append(a.lerp(b, float(s) / float(count)))
	out.append(points[points.size() - 1])
	return out


func _bounds_of(points: PackedVector2Array) -> Rect2:
	var box := Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		box = box.expand(p)
	return box


# --- Небо и свет ---

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = _build_sky()

	# Заполняющий свет берётся с неба, а не задаётся плоским цветом: затенённые
	# грани становятся холодными, освещённые — тёплыми, и объём появляется сам.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	# Затенённые стены при 0.45 уходили в чёрное — северный день пасмурный,
	# но не беспросветный.
	e.ambient_light_energy = 0.85
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Без тонмаппинга яркие места просто упираются в белый, и картинка выглядит
	# пластиковой. AgX мягко сводит пересветы.
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0

	# Контактные тени в стыках и подхват отражённого света.
	e.ssao_enabled = true
	e.ssao_radius = 1.6
	e.ssao_intensity = 2.4
	e.ssao_power = 1.6
	e.ssao_detail = 0.6
	e.ssao_light_affect = 0.15
	e.ssil_enabled = true
	e.ssil_radius = 2.5
	e.ssil_intensity = 0.5
	e.ssil_normal_rejection = 1.0

	# Отражения в экранном пространстве нужны прежде всего реке: без них вода
	# отражает только небо и не видит берегов.
	e.ssr_enabled = true
	e.ssr_max_steps = 48
	e.ssr_fade_in = 0.2
	e.ssr_fade_out = 3.0

	# SDFGI — переотражённый свет: стены домов подсвечивают землю, и цвета
	# перестают быть независимыми друг от друга.
	e.sdfgi_enabled = true
	# Окклюзия SDFGI на огромной плоскости ландшафта даёт грязные тёмные пятна:
	# воксели крупные, и затенение ложится кляксами. Отражённый свет оставляем.
	e.sdfgi_use_occlusion = false
	e.sdfgi_bounce_feedback = 0.5
	e.sdfgi_cascades = 4
	e.sdfgi_energy = 1.0

	# Дымка вдаль: горы уходят в цвет неба, и расстояние до них становится
	# читаемым. Без этого хребет выглядит нарисованным на заднике.
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = Color(0.55, 0.65, 0.79)
	e.fog_light_energy = 1.0
	e.fog_sun_scatter = 0.28
	e.fog_density = 0.00035
	e.fog_aerial_perspective = 0.12
	e.fog_sky_affect = 0.05
	e.fog_height = 4.0
	e.fog_height_density = 0.0015

	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.0015
	e.volumetric_fog_albedo = Color(0.80, 0.86, 0.94)
	e.volumetric_fog_gi_inject = 0.8
	e.volumetric_fog_ambient_inject = 0.2
	e.volumetric_fog_anisotropy = 0.35
	e.volumetric_fog_length = 120.0
	e.volumetric_fog_sky_affect = 0.4

	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.1
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Холодная, слегка обесцвеченная палитра — та самая нордическая.
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.12
	# Палитра Скайрима холодная и приглушённая: сочная зелень выдаёт мультик.
	e.adjustment_saturation = 0.78

	env.environment = e
	root.add_child(env)


func _build_sky() -> Sky:
	var sky := Sky.new()
	# Облака ползут, ambient должен ехать за ними — но пересчитывать кубмапу
	# целиком каждый кадр незачем, хватает порций.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	if ResourceLoader.exists(SKY_SHADER):
		var mat := ShaderMaterial.new()
		mat.shader = load(SKY_SHADER)
		sky.sky_material = mat
	else:
		sky.sky_material = PhysicalSkyMaterial.new()
	return sky


func _build_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# Низкое солнце сбоку: длинные тени показывают рельеф, зенитное — стирает его.
	sun.rotation_degrees = Vector3(-47.0, 138.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.light_energy = 2.4
	# Угловой размер диска задаёт мягкость края тени. При нуле тень абсолютно
	# резкая, и сразу видно, что свет ненастоящий.
	sun.light_angular_distance = 0.7
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.14
	sun.directional_shadow_split_3 = 0.38
	# Шейдер неба берёт направление и цвет отсюда — диск солнца окажется ровно
	# там, откуда падает свет.
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	root.add_child(sun)


# --- Ограда ---

## Вал собирается секциями по рельефу и прерывается там, где сквозь него идёт
## река: сплошная стена поперёк русла сразу выдала бы декорацию.
func _build_rampart() -> void:
	var mat := _rampart_material()
	var half := yard + 1.5
	var step := 2.0
	var corners := [
		Vector2(-half, half), Vector2(half, half),
		Vector2(half, -half), Vector2(-half, -half)]
	for i: int in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var count := int(a.distance_to(b) / step)
		for s: int in count:
			var p := a.lerp(b, (float(s) + 0.5) / float(count))
			if river_distance(p) < RIVER_HALF + 3.0:
				continue
			var mesh := BoxMesh.new()
			# Секция уходит на два метра в землю: на неровностях иначе видны щели.
			mesh.size = Vector3(step + 0.1, RAMPART_HEIGHT + 2.0, 1.2)
			if i % 2 != 0:
				mesh.size = Vector3(1.2, RAMPART_HEIGHT + 2.0, step + 0.1)
			var node := MeshInstance3D.new()
			node.mesh = mesh
			node.position = Vector3(p.x, height_at(p.x, p.y) + 0.2, p.y)
			node.material_override = mat
			root.add_child(node)
			node.add_child(VillageBuildings.collider(mesh.size))


## Вал — каменная кладка со сканом, трипланарно по миру: секций много, и шов
## между ними не должен читаться.
func _rampart_material() -> StandardMaterial3D:
	return _pbr("castle_wall_slates", 0.35, Color(0.42, 0.41, 0.39))


# --- Растительность за оградой ---

func _scatter_trees() -> void:
	var models: Array[String] = ["tree_pineDefaultA", "tree_pineDefaultA",
		"tree_pineDefaultA", "tree_oak", "tree_default"]
	var placed := 0
	var attempts := 0
	while placed < 300 and attempts < 9000:
		attempts += 1
		var spot := _spot(yard + 9.0, 165.0)
		if spot.y > TREE_LINE or slope_at(spot.x, spot.z) > 0.42:
			continue
		if _forest.get_noise_2d(spot.x, spot.z) < -0.02:
			continue
		# В реку деревья не сажаем.
		if river_distance(Vector2(spot.x, spot.z)) < RIVER_HALF + 3.0:
			continue
		# Вблизи ставим процедурную ель: гранёный конус кита в двадцати метрах от
		# игрока и делал картинку игрушечной. Дальше он читается силуэтом, и разница
		# уже не видна — а тысяча ярусов на дальний лес стоила бы кадров.
		if Vector2(spot.x, spot.z).length() < yard + 70.0:
			gear().conifer(Vector2(spot.x, spot.z), rng.randf_range(8.0, 16.0), rng.randi())
			placed += 1
			continue
		var model: String = models[rng.randi() % models.size()]
		# Осадка на полметра: комель должен уходить в землю, иначе на склоне
		# дерево стоит на цыпочках.
		var node := place(NATURE + model + ".glb",
			spot - Vector3(0.0, 0.5, 0.0), rng.randf_range(9.0, 18.0), bark, 0.55)
		if node == null:
			return
		node.rotation.y = rng.randf() * TAU
		placed += 1


func _scatter_rocks() -> void:
	var models: Array[String] = ["rock_largeA", "rock_smallA", "stump_round", "log"]
	var placed := 0
	var attempts := 0
	while placed < 90 and attempts < 2000:
		attempts += 1
		var spot := _spot(yard + 6.0, 120.0)
		var model: String = models[rng.randi() % models.size()]
		var node := place(NATURE + model + ".glb",
			spot - Vector3(0.0, 0.4, 0.0), rng.randf_range(1.2, 4.0),
			stone if model.begins_with("rock") else bark, 0.7)
		if node == null:
			return
		node.rotation.y = rng.randf() * TAU
		placed += 1


## Трава идёт через MultiMesh: шесть тысяч отдельных узлов сцена бы не вынесла,
## а одна отрисовка на весь ковёр — вынесет.
func _scatter_grass() -> void:
	var mesh := VillageGear.grass_tuft(rng)
	if mesh == null:
		return
	var target := 6000
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = target
	var unit := maxf(mesh.get_aabb().size.y, 0.001)
	var blades := grass_blade_material()
	var placed := 0
	var attempts := 0
	while placed < target and attempts < target * 5:
		attempts += 1
		# Двор засевает VillageDressing: там нужно обходить постройки и дороги,
		# а список препятствий появляется только после их постройки.
		var spot := _spot(yard + 3.0, 95.0)
		if spot.y > TREE_LINE or slope_at(spot.x, spot.z) > 0.40:
			continue
		if spot.y < WATER_LEVEL + 0.2:
			continue
		var height := rng.randf_range(0.35, 0.7)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis.scaled(Vector3.ONE * (height / unit))
		mm.set_instance_transform(placed, Transform3D(basis, spot))
		placed += 1
	mm.visible_instance_count = placed
	var node := MultiMeshInstance3D.new()
	node.name = "Grass"
	node.multimesh = mm
	node.material_override = blades
	# Тени от травы стоят дороже, чем добавляют.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)


## Случайная точка в кольце вокруг двора, посаженная на землю.
func _spot(inner: float, width: float) -> Vector3:
	var angle := rng.randf() * TAU
	var radius := inner + rng.randf() * width
	var x := sin(angle) * radius
	var z := cos(angle) * radius
	return Vector3(x, height_at(x, z), z)


## Ставит модель, подгоняя её под нужную высоту в метрах. Габариты китов Kenney
## заранее не известны, поэтому масштаб считается от AABB, а не подбирается.
## solid_radius > 0 добавляет цилиндрический коллайдер по стволу. Для дерева
## обводить коллизией всю крону нельзя — игрок упирался бы в воздух за метры
## до ствола.
func place(path: String, pos: Vector3, target_height: float,
		solid: Material = null, solid_radius: float = 0.0) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	var node: Node3D = scene.instantiate()
	var box := _aabb_of(node)
	var factor := target_height / maxf(box.size.y, 0.001)
	node.scale = Vector3.ONE * clampf(factor, 0.2, 60.0)
	node.position = pos
	if solid != null:
		_repaint(node, solid)
	root.add_child(node)
	if solid_radius > 0.0:
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = solid_radius
		cyl.height = target_height
		shape.shape = cyl
		shape.position = Vector3(0.0, target_height * 0.5, 0.0)
		var solid_body := StaticBody3D.new()
		solid_body.add_child(shape)
		solid_body.position = pos
		root.add_child(solid_body)
	return node


func _aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for child: Node in _descendants(node):
		if child is MeshInstance3D:
			var part := (child as MeshInstance3D).get_aabb()
			box = part if first else box.merge(part)
			first = false
	return box


func mesh_of(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	var node: Node = scene.instantiate()
	var mesh: Mesh = null
	for child: Node in _descendants(node):
		if child is MeshInstance3D:
			mesh = (child as MeshInstance3D).mesh
			break
	# Узел в дерево не добавлялся, освобождаем сразу; ресурс меша это переживёт.
	node.free()
	return mesh


static func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(_descendants(child))
	return found


# --- Процедурные текстуры ---
# Готовых PBR-текстур в проекте нет, поэтому albedo и карта нормалей собираются
# из шума прямо в рантайме. Фотосканы это не заменит, но снимает главную беду
# заливки одним цветом — полное отсутствие деталей на поверхности.

func _noise_texture(frequency: float, stops: Array) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 4
	noise.seed = rng.randi()
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = _ramp(stops)
	return tex


func _noise_normal(frequency: float, strength: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 5
	noise.seed = rng.randi()
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = strength
	tex.noise = noise
	return tex


## Клеточный шум даёт готовые ячейки Вороного — это и есть булыжник мостовой.
## Каждая ячейка получает свой оттенок, поэтому камни читаются по отдельности.
func _cellular_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	noise.cellular_jitter = 0.95
	noise.frequency = 0.045
	noise.seed = rng.randi()
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = _ramp([
		Color(0.20, 0.19, 0.18), Color(0.34, 0.32, 0.30), Color(0.45, 0.43, 0.40)])
	return tex


## А расстояние до центра ячейки — готовые швы между камнями: на карте нормалей
## границы ячеек становятся канавками.
func _cellular_normal() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	noise.cellular_jitter = 0.95
	noise.frequency = 0.045
	noise.seed = rng.randi()
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 5.0
	tex.noise = noise
	return tex


func _ramp(stops: Array) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_offset(0, 0.0)
	ramp.set_color(0, stops[0])
	ramp.set_offset(1, 1.0)
	ramp.set_color(1, stops[stops.size() - 1])
	for i: int in range(1, stops.size() - 1):
		ramp.add_point(float(i) / float(stops.size() - 1), stops[i])
	return ramp


## Материалы китов Kenney приходят из glTF гладкими и чуть металлическими: в них
## зеркалится небо, и зелёная листва уходит в бирюзу, а дерево — в розовый.
## Причина — в спецификации glTF: metallicFactor по умолчанию равен 1.0, а Kenney
## его не прописывает. Правим общий ресурс по одному разу.
static func polish_materials(node: Node) -> void:
	var seen := {}
	for child: Node in _descendants(node):
		var mesh: Mesh = null
		if child is MeshInstance3D:
			mesh = (child as MeshInstance3D).mesh
		elif child is MultiMeshInstance3D:
			var mm := (child as MultiMeshInstance3D).multimesh
			mesh = mm.mesh if mm != null else null
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var mat := mesh.surface_get_material(surface)
			if mat == null or not mat is StandardMaterial3D:
				continue
			var id := mat.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			var std := mat as StandardMaterial3D
			std.roughness = 1.0
			std.metallic = 0.0
			std.metallic_specular = 0.15
			# Палитра Kenney — пастельно-оранжевая. Рядом с фотосканами она кричит,
			# поэтому приглушаем её тоном, не трогая сам рисунок.
			std.albedo_color = Color(0.60, 0.56, 0.50)


# --- Палитра природы ---
# Цвета листвы в исходных моделях сине-зелёные, а стволы розовые: в лесу это
# читается как пластик. Перекрашиваем только то, что расставляем сами, —
# городской кит и постройки остаются как были.

func _build_palette() -> void:
	foliage = _flat(Color(0.13, 0.23, 0.10))
	bark = _flat(Color(0.17, 0.12, 0.09))
	stone = _flat(Color(0.33, 0.32, 0.30))
	grass_mat = _flat(Color(0.32, 0.38, 0.17))


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Материал ставится оверрайдом на экземпляр, а не правкой общего ресурса:
## те же меши используются и в других местах, менять их всем сразу нельзя.
func _repaint(node: Node3D, solid: Material) -> void:
	for child: Node in _descendants(node):
		if not child is MeshInstance3D:
			continue
		var part := child as MeshInstance3D
		var mesh := part.mesh
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var source := mesh.surface_get_material(surface)
			var leaf := false
			if source is StandardMaterial3D:
				var c := (source as StandardMaterial3D).albedo_color
				# Листва в исходниках сине-зелёная: зелёный и синий высокие,
				# красный заметно ниже. Ствол и камень так не выглядят.
				leaf = c.g > 0.55 and c.b > 0.5 and c.r < c.g * 0.75
			part.set_surface_override_material(surface, foliage if leaf else solid)


## Коллайдер под уже добавленный меш. Обёртка нужна, чтобы не повторять одно и
## то же в мосту, вале и настилах.
func rack_solid(node: MeshInstance3D, size: Vector3) -> void:
	node.add_child(VillageBuildings.collider(size))


## Материал травы: цвет берётся из вершин, качание — из шейдера. Общий на все
## пучки, поэтому ветер по полю идёт единой волной.
func grass_blade_material() -> Material:
	if not ResourceLoader.exists(GRASS_SHADER):
		return grass_mat
	var mat := ShaderMaterial.new()
	mat.shader = load(GRASS_SHADER)
	return mat


## Генератор утвари для самого ландшафта: им ставятся ближние ели. Свой список
## препятствий — лесу за оградой он не нужен, там никто не ходит.
var _gear: VillageGear

func gear() -> VillageGear:
	if _gear == null:
		_gear = VillageGear.new(root, VillageBuildings.new(root), self, [] as Array[Rect2])
	return _gear
