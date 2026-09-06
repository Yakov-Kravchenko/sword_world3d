class_name VillageLook
extends RefCounted
## Внешний вид хаба: небо, солнце, ландшафт, ограда и растительность.
##
## Вынесено из village.gd: подбор освещения и генерация рельефа — отдельная
## задача, держать её рядом с логикой ходьбы неудобно. Строится кодом, как и
## вся остальная деревня, поэтому village.tscn остаётся пустым узлом.

const NATURE := "res://assets/models/kenney_nature/"
const SKY_SHADER := "res://game/scenes/village/sky_clouds.gdshader"
const TERRAIN_SHADER := "res://game/scenes/village/terrain.gdshader"

## Дальше этого радиуса строить нечего: всё съедает туман.
const TERRAIN_EXTENT := 380.0
const TERRAIN_CELLS := 180

## Двор остаётся идеально плоским: по нему ходит игрок, а постройки ставятся на
## y = 0. Любой уклон под ними оторвал бы дома от земли. Рельеф — только снаружи.
const FLAT_MARGIN := 5.0
const HILL_FADE := 60.0
const HILL_HEIGHT := 9.0
const MOUNTAIN_START := 60.0
const MOUNTAIN_FADE := 185.0
const MOUNTAIN_HEIGHT := 195.0

## Ограда двора — низкий вал, а не глухая стена в 6 метров: с уровня глаз
## (камера на 1.7 м) стена закрывала бы и лес, и горы, ради которых всё это.
const RAMPART_HEIGHT := 2.4

## Выше границы леса деревья не растут — так хребет читается как хребет.
const TREE_LINE := 46.0

var root: Node3D
var yard: float
var _hills: FastNoiseLite
var _ridges: FastNoiseLite
var _rng: RandomNumberGenerator
var _foliage: StandardMaterial3D
var _bark: StandardMaterial3D
var _stone: StandardMaterial3D
var _grass_mat: StandardMaterial3D


func _init(parent: Node3D, yard_limit: float) -> void:
	root = parent
	yard = yard_limit
	# Фиксированное зерно: деревня должна выглядеть одинаково при каждом запуске,
	# иначе игрок не запомнит её силуэт.
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260906
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
	_build_palette()


func build() -> void:
	_build_environment()
	_build_sun()
	_build_terrain()
	_build_rampart()
	_scatter_trees()
	_scatter_rocks()
	_scatter_grass()


# --- Рельеф ---

## Высота земли в точке. Единственный источник правды: по ней строится меш,
## по ней же расставляются деревья и трава, поэтому они не висят в воздухе.
func height_at(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var flat := yard + FLAT_MARGIN
	if r <= flat:
		return 0.0
	var hill_t := clampf((r - flat) / HILL_FADE, 0.0, 1.0)
	var hills := _hills.get_noise_2d(x, z) * HILL_HEIGHT * hill_t * hill_t
	var mount_t := clampf((r - (yard + MOUNTAIN_START)) / MOUNTAIN_FADE, 0.0, 1.0)
	# Модуль шума даёт острые гребни вместо мягких куполов, степень их заостряет:
	# без этого «горы» выглядят как холмы, только выше.
	var ridge := 1.0 - absf(_ridges.get_noise_2d(x, z))
	ridge = pow(ridge, 2.0)
	return hills + ridge * MOUNTAIN_HEIGHT * mount_t * mount_t


## Нормаль считаем из самой функции высоты, а не из намотки треугольников:
## так не важно, в каком порядке PlaneMesh выдал вершины.
func normal_at(x: float, z: float) -> Vector3:
	var d := 1.5
	return Vector3(
		height_at(x - d, z) - height_at(x + d, z),
		2.0 * d,
		height_at(x, z - d) - height_at(x, z + d)).normalized()


func _build_terrain() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(TERRAIN_EXTENT * 2.0, TERRAIN_EXTENT * 2.0)
	plane.subdivide_width = TERRAIN_CELLS - 1
	plane.subdivide_depth = TERRAIN_CELLS - 1
	# Берём готовые массивы плоскости: намотка и UV у неё уже правильные,
	# остаётся поднять вершины и пересчитать нормали.
	var arrays := plane.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i: int in verts.size():
		var v := verts[i]
		v.y = height_at(v.x, v.z)
		verts[i] = v
		normals[i] = normal_at(v.x, v.z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var node := MeshInstance3D.new()
	node.name = "Terrain"
	node.mesh = mesh
	node.material_override = _terrain_material()
	root.add_child(node)


func _terrain_material() -> Material:
	var grass := _noise_texture(0.009, [
		Color(0.16, 0.20, 0.09), Color(0.27, 0.31, 0.15), Color(0.36, 0.38, 0.21)])
	var rock := _noise_texture(0.011, [
		Color(0.20, 0.20, 0.21), Color(0.34, 0.33, 0.32), Color(0.46, 0.45, 0.44)])
	var snow := _noise_texture(0.012, [
		Color(0.72, 0.77, 0.85), Color(0.90, 0.93, 0.97), Color(1.00, 1.00, 1.00)])
	var detail := _noise_normal(0.022, 4.0)
	if not ResourceLoader.exists(TERRAIN_SHADER):
		# Запасной вариант: без шейдера хотя бы трава с рельефной нормалью.
		var fallback := StandardMaterial3D.new()
		fallback.albedo_texture = grass
		fallback.normal_enabled = true
		fallback.normal_texture = detail
		fallback.uv1_scale = Vector3(64.0, 64.0, 1.0)
		fallback.roughness = 1.0
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = load(TERRAIN_SHADER)
	mat.set_shader_parameter("grass_albedo", grass)
	mat.set_shader_parameter("rock_albedo", rock)
	mat.set_shader_parameter("snow_albedo", snow)
	mat.set_shader_parameter("detail_normal", detail)
	# Снеговая линия выше границы леса: белыми должны быть только вершины.
	mat.set_shader_parameter("snow_line", 95.0)
	mat.set_shader_parameter("snow_fade", 38.0)
	return mat


# --- Небо и свет ---

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = _build_sky()

	# Заполняющий свет теперь берётся с неба, а не задаётся плоским цветом:
	# затенённые грани становятся холодными, освещённые — тёплыми, и объём
	# появляется сам собой.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.45
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
	e.adjustment_saturation = 0.92

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
	sun.rotation_degrees = Vector3(-38.0, 142.0, 0.0)
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

func _build_rampart() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _noise_texture(0.016, [
		Color(0.26, 0.25, 0.24), Color(0.42, 0.41, 0.39), Color(0.52, 0.50, 0.47)])
	mat.normal_enabled = true
	mat.normal_texture = _noise_normal(0.030, 5.0)
	mat.normal_scale = 1.5
	# Трипланарные UV по мировым координатам: текстура ложится на все грани вала
	# без развёртки и не растягивается на торцах.
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.22, 0.22, 0.22)
	mat.roughness = 1.0
	var span := yard * 2.0 + 6.0
	for i: int in 4:
		var angle := float(i) * PI * 0.5
		var offset := Vector3(sin(angle), 0.0, cos(angle)) * (yard + 1.5)
		var size := Vector3(span, RAMPART_HEIGHT, 1.1)
		if i % 2 != 0:
			size = Vector3(1.1, RAMPART_HEIGHT, span)
		var node := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		node.mesh = mesh
		node.position = offset + Vector3(0.0, RAMPART_HEIGHT * 0.5, 0.0)
		node.material_override = mat
		root.add_child(node)


# --- Растительность ---

func _scatter_trees() -> void:
	var models: Array[String] = ["tree_pineDefaultA", "tree_pineDefaultA",
		"tree_pineDefaultA", "tree_oak", "tree_default"]
	var placed := 0
	var attempts := 0
	while placed < 240 and attempts < 5000:
		attempts += 1
		var spot := _spot(yard + 9.0, 165.0)
		if spot.y > TREE_LINE or _slope_at(spot.x, spot.z) > 0.42:
			continue
		var model: String = models[_rng.randi() % models.size()]
		# Осадка на полметра: комель должен уходить в землю, иначе на склоне
		# дерево стоит на цыпочках.
		var node := _place(NATURE + model + ".glb",
			spot - Vector3(0.0, 0.5, 0.0), _rng.randf_range(9.0, 18.0), _bark)
		if node == null:
			return
		node.rotation.y = _rng.randf() * TAU
		placed += 1


func _scatter_rocks() -> void:
	var models: Array[String] = ["rock_largeA", "rock_smallA", "stump_round", "log"]
	var placed := 0
	var attempts := 0
	while placed < 90 and attempts < 2000:
		attempts += 1
		var spot := _spot(yard + 6.0, 120.0)
		var model: String = models[_rng.randi() % models.size()]
		var node := _place(NATURE + model + ".glb",
			spot - Vector3(0.0, 0.4, 0.0), _rng.randf_range(1.2, 4.0),
			_stone if model.begins_with("rock") else _bark)
		if node == null:
			return
		node.rotation.y = _rng.randf() * TAU
		placed += 1


## Трава идёт через MultiMesh: шесть тысяч отдельных узлов сцена бы не вынесла,
## а одна отрисовка на весь ковёр — вынесет.
func _scatter_grass() -> void:
	var mesh := _mesh_of(NATURE + "grass_large.glb")
	if mesh == null:
		return
	var target := 6000
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = target
	var unit := maxf(mesh.get_aabb().size.y, 0.001)
	var placed := 0
	var attempts := 0
	while placed < target and attempts < target * 5:
		attempts += 1
		# Внутрь двора траву не сеем: там площадь и постройки, а кусты полезли бы
		# сквозь стены — проверять пересечения с ними нечем.
		var spot := _spot(yard + 3.0, 95.0)
		if spot.y > TREE_LINE or _slope_at(spot.x, spot.z) > 0.40:
			continue
		var height := _rng.randf_range(0.45, 0.85)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU)
		basis = basis.scaled(Vector3.ONE * (height / unit))
		mm.set_instance_transform(placed, Transform3D(basis, spot))
		placed += 1
	mm.visible_instance_count = placed
	var node := MultiMeshInstance3D.new()
	node.name = "Grass"
	node.multimesh = mm
	node.material_override = _grass_mat
	# Тени от травы стоят дороже, чем добавляют.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)


## Случайная точка в кольце вокруг двора, посаженная на землю.
func _spot(inner: float, width: float) -> Vector3:
	var angle := _rng.randf() * TAU
	var radius := inner + _rng.randf() * width
	var x := sin(angle) * radius
	var z := cos(angle) * radius
	return Vector3(x, height_at(x, z), z)


func _slope_at(x: float, z: float) -> float:
	return 1.0 - normal_at(x, z).y


## Ставит модель, подгоняя её под нужную высоту в метрах. Габариты китов Kenney
## заранее не известны, поэтому масштаб считается от AABB, а не подбирается.
func _place(path: String, pos: Vector3, target_height: float,
		solid: Material = null) -> Node3D:
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


func _mesh_of(path: String) -> Mesh:
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
	noise.seed = _rng.randi()
	var ramp := Gradient.new()
	ramp.set_offset(0, 0.0)
	ramp.set_color(0, stops[0])
	ramp.set_offset(1, 1.0)
	ramp.set_color(1, stops[stops.size() - 1])
	for i: int in range(1, stops.size() - 1):
		ramp.add_point(float(i) / float(stops.size() - 1), stops[i])
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


func _noise_normal(frequency: float, strength: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 5
	noise.seed = _rng.randi()
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = strength
	tex.noise = noise
	return tex


## Материалы китов Kenney приходят из glTF гладкими и чуть металлическими: в них
## зеркалится небо, и зелёная листва уходит в бирюзу, а дерево — в розовый.
## Правим общий ресурс по одному разу, а не копию на каждый экземпляр.
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


# --- Палитра природы ---
# Цвета листвы в исходных моделях сине-зелёные, а стволы розовые: в лесу это
# читается как пластик. Перекрашиваем только то, что расставляем сами, —
# городской кит и постройки остаются как были.

func _build_palette() -> void:
	_foliage = _flat(Color(0.13, 0.23, 0.10))
	_bark = _flat(Color(0.17, 0.12, 0.09))
	_stone = _flat(Color(0.33, 0.32, 0.30))
	_grass_mat = _flat(Color(0.24, 0.31, 0.12))


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
			part.set_surface_override_material(surface, _foliage if leaf else solid)
