class_name VillageBuildings
extends RefCounted
## Нордический сруб: каменный цоколь, фахверк, крутая двускатная крыша с соломой,
## ставни и резные ветровые доски на фронтоне.
##
## Зачем своя геометрия вместо кита: дом из модулей Kenney — это коробка с
## плоской заливкой и почти плоской крышей. Узнаваемость северной деревни держится
## на трёх вещах — крутом скате с большими свесами, тёмных балках по светлой
## стене и каменном цоколе. Ни одной из них в ките нет, зато все три собираются
## из примитивов, и материал у них процедурный, а не одноцветный.

## Скат: 52 градуса. Пологая крыша сразу читается как сарай, а не как северный дом.
const PITCH := 52.0
const STOREY := 2.5
const EAVE := 0.9               # вынос свеса за стену
const BEAM := 0.22              # толщина балок фахверка

var root: Node3D
var timber: StandardMaterial3D
var plaster: StandardMaterial3D
var thatch: StandardMaterial3D
var plinth: StandardMaterial3D
var shutter: StandardMaterial3D
var dark: StandardMaterial3D
var needles: StandardMaterial3D
var mud: StandardMaterial3D
var _rng: RandomNumberGenerator
var _wear: RandomNumberGenerator


func _init(parent: Node3D) -> void:
	root = parent
	_rng = RandomNumberGenerator.new()
	_rng.seed = 40404
	_wear = RandomNumberGenerator.new()
	_wear.seed = 90210
	# Материалы общие на все дома: одна текстура на деревню читается как единый
	# материал построек, а не как набор разных объектов.
	timber = _pbr("medieval_wood", 0.55, Color(0.20, 0.14, 0.09), Color(0.30, 0.21, 0.13))
	plaster = _pbr("plastered_stone_wall", 0.30, Color(0.74, 0.70, 0.60), Color(0.86, 0.83, 0.75))
	thatch = _pbr("thatch_roof_angled", 0.42, Color(0.55, 0.44, 0.24), Color(0.94, 0.86, 0.66))
	plinth = _pbr("castle_wall_slates", 0.40, Color(0.42, 0.41, 0.39), Color(0.72, 0.70, 0.67))
	shutter = _pbr("medieval_wood", 0.9, Color(0.32, 0.22, 0.14), Color(0.42, 0.28, 0.17))
	mud = _pbr("brown_mud_03", 0.55, Color(0.24, 0.19, 0.14), Color(0.62, 0.56, 0.48))
	needles = StandardMaterial3D.new()
	needles.albedo_color = Color(0.10, 0.16, 0.09)
	needles.roughness = 0.95
	needles.metallic = 0.0
	dark = StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.04, 0.035)
	dark.roughness = 1.0
	dark.metallic = 0.0


## Дом. center — точка на земле, size — габарит в метрах, yaw — куда смотрит
## фасад. Возвращает точку перед дверью: по ней деревня ставит взаимодействие.
func house(center: Vector3, size: Vector2, storeys: int, yaw: float) -> Vector3:
	var body := Node3D.new()
	body.position = center
	body.rotation.y = yaw
	root.add_child(body)

	var w := size.x
	var d := size.y
	var wall := STOREY * float(maxi(storeys, 1))
	var pitch := deg_to_rad(PITCH)
	var half := d * 0.5 + EAVE
	var ridge := wall + (d * 0.5) * tan(pitch)

	_plinth(body, w, d)
	_walls(body, w, d, wall)
	_frame(body, w, d, wall, storeys)
	_gables(body, w, d, wall, ridge)
	_roof(body, w, half, wall, ridge, pitch)
	_ragged_eave(body, w, half, wall + 0.6, pitch)
	_facade(body, w, d, wall, storeys)
	_chimney(body, w, d, ridge)
	_threshold(body, w, d)

	# Точка перед дверью, повёрнутая вместе с домом.
	var offset := Vector3(0.0, 0.9, d * 0.5 + 1.3).rotated(Vector3.UP, yaw)
	return center + offset


# --- Части дома ---

## Цоколь: дом, поставленный прямо на траву, выглядит приклеенным. Каменная
## подушка чуть шире стен даёт тень по периметру и сажает постройку в землю.
func _plinth(body: Node3D, w: float, d: float) -> void:
	_box(body, Vector3(w + 0.7, 1.1, d + 0.7), Vector3(0.0, 0.15, 0.0), plinth)


func _walls(body: Node3D, w: float, d: float, wall: float) -> void:
	var y := wall * 0.5 + 0.6
	_box(body, Vector3(w, wall, 0.3), Vector3(0.0, y, -d * 0.5), plaster)
	_box(body, Vector3(w, wall, 0.3), Vector3(0.0, y, d * 0.5), plaster)
	_box(body, Vector3(0.3, wall, d), Vector3(-w * 0.5, y, 0.0), plaster)
	_box(body, Vector3(0.3, wall, d), Vector3(w * 0.5, y, 0.0), plaster)


## Фахверк — главный признак северного дома: тёмные балки поверх светлой стены.
## Стойки, обвязки и раскосы ставятся снаружи стены, чтобы читался их рельеф.
func _frame(body: Node3D, w: float, d: float, wall: float, storeys: int) -> void:
	var out := 0.18
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			# Угловые стойки.
			_box(body, Vector3(BEAM * 1.6, wall, BEAM * 1.6),
				Vector3(sx * w * 0.5, wall * 0.5 + 0.6, sz * d * 0.5), timber)
	# Горизонтальные обвязки: понизу, по верху и между этажами.
	var levels: Array[float] = [0.6, wall + 0.6]
	for i: int in maxi(storeys - 1, 0):
		levels.append(0.6 + STOREY * float(i + 1))
	for level: float in levels:
		for sz: float in [-1.0, 1.0]:
			_box(body, Vector3(w + BEAM, BEAM, BEAM),
				Vector3(0.0, level, sz * (d * 0.5 + out)), timber)
		for sx: float in [-1.0, 1.0]:
			_box(body, Vector3(BEAM, BEAM, d + BEAM),
				Vector3(sx * (w * 0.5 + out), level, 0.0), timber)
	# Вертикальные стойки по длинным стенам и раскосы по торцам.
	var studs := maxi(2, int(w / 1.7))
	for i: int in studs + 1:
		var x := lerpf(-w * 0.5, w * 0.5, float(i) / float(studs))
		for sz: float in [-1.0, 1.0]:
			_lean(body, Vector3(BEAM, wall, BEAM),
				Vector3(x, wall * 0.5 + 0.6, sz * (d * 0.5 + out)), timber)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var brace := _box(body, Vector3(BEAM, wall * 0.9, BEAM),
				Vector3(sx * (w * 0.5 + out), wall * 0.5 + 0.6, sz * d * 0.28), timber)
			brace.rotation.x = sz * 0.42


## Фронтон — треугольник между верхом стены и коньком. PrismMesh даёт ровно
## такую форму, поэтому собирать её из скошенных коробок незачем.
func _gables(body: Node3D, w: float, d: float, wall: float, ridge: float) -> void:
	for sz: float in [-1.0, 1.0]:
		var mesh := PrismMesh.new()
		mesh.size = Vector3(w, ridge - wall, 0.3)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = Vector3(0.0, (wall + ridge) * 0.5 + 0.6, sz * d * 0.5)
		node.material_override = plaster
		body.add_child(node)


## Крыша: два ската с большим выносом. Свес — половина впечатления: без него
## крыша выглядит крышкой от коробки.
func _roof(body: Node3D, w: float, half: float, wall: float, ridge: float,
		pitch: float) -> void:
	var slope := half / cos(pitch)
	for sz: float in [-1.0, 1.0]:
		var node := _box(body, Vector3(w + EAVE * 2.0, 0.28, slope),
			Vector3(0.0, (wall + ridge) * 0.5 + 0.6, sz * half * 0.5), thatch)
		node.rotation.x = sz * pitch
	# Конёк и ветровые доски по фронтону — та самая резьба северных домов.
	_box(body, Vector3(w + EAVE * 2.2, 0.3, 0.4), Vector3(0.0, ridge + 0.7, 0.0), timber)
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var board := _box(body, Vector3(0.22, 0.34, slope + 0.4),
				Vector3(sx * (w * 0.5 + EAVE), (wall + ridge) * 0.5 + 0.75,
					sz * half * 0.5), timber)
			board.rotation.x = sz * pitch


## Фасад: дверь в тёмном проёме и окна со ставнями. Проём заглублён — плоская
## дверь, нарисованная на стене, сразу выдаёт коробку.
func _facade(body: Node3D, w: float, d: float, wall: float, storeys: int) -> void:
	var z := d * 0.5 + 0.2
	_box(body, Vector3(1.5, 2.3, 0.24), Vector3(0.0, 1.75, z), dark)
	_box(body, Vector3(1.2, 2.1, 0.12), Vector3(0.0, 1.65, z + 0.1), shutter)
	for side: float in [-1.0, 1.0]:
		_box(body, Vector3(0.24, 2.5, 0.3), Vector3(side * 0.86, 1.85, z), timber)
	_box(body, Vector3(2.1, 0.26, 0.36), Vector3(0.0, 3.05, z), timber)
	# Окна по обеим сторонам двери и на верхних этажах.
	for level: int in maxi(storeys, 1):
		var y := 1.7 + STOREY * float(level)
		if level == 0:
			for side: float in [-1.0, 1.0]:
				_window(body, Vector3(side * w * 0.3, 1.75, z))
		else:
			for side: float in [-1.0, 1.0]:
				_window(body, Vector3(side * w * 0.26, y, z))
	for side: float in [-1.0, 1.0]:
		_window(body, Vector3(side * (w * 0.5 + 0.2), 1.8, d * 0.22), PI * 0.5)


func _window(body: Node3D, pos: Vector3, yaw: float = 0.0) -> void:
	var frame := _box(body, Vector3(1.0, 1.1, 0.2), pos, dark)
	frame.rotation.y = yaw
	for side: float in [-1.0, 1.0]:
		var leaf := _box(body, Vector3(0.5, 1.1, 0.1),
			pos + Vector3(side * 0.72, 0.0, 0.1).rotated(Vector3.UP, yaw), shutter)
		leaf.rotation.y = yaw
	var sill := _box(body, Vector3(1.3, 0.14, 0.3),
		pos + Vector3(0.0, -0.62, 0.05).rotated(Vector3.UP, yaw), timber)
	sill.rotation.y = yaw


## Труба с дымом. Дым — самая дешёвая деталь, которая делает дом обитаемым:
## неподвижная деревня всегда выглядит макетом.
func _chimney(body: Node3D, w: float, d: float, ridge: float) -> void:
	var pos := Vector3(w * 0.28, 0.0, -d * 0.22)
	var top := ridge + 1.4
	_box(body, Vector3(1.0, top, 1.0), pos + Vector3(0.0, top * 0.5 + 0.6, 0.0), plinth)
	_box(body, Vector3(1.25, 0.25, 1.25), pos + Vector3(0.0, top + 0.6, 0.0), plinth)

	var smoke := GPUParticles3D.new()
	smoke.position = pos + Vector3(0.0, top + 0.8, 0.0)
	smoke.amount = 24
	smoke.lifetime = 5.0
	smoke.explosiveness = 0.0
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.25, 1.0, 0.1)
	process.spread = 12.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.1
	process.gravity = Vector3(0.35, 0.25, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.4
	process.color = Color(0.62, 0.62, 0.64, 0.30)
	smoke.process_material = process
	var puff := QuadMesh.new()
	puff.size = Vector2(1.4, 1.4)
	var puff_mat := StandardMaterial3D.new()
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff_mat.albedo_color = Color(0.66, 0.66, 0.68, 0.22)
	puff_mat.vertex_color_use_as_albedo = true
	puff.material = puff_mat
	smoke.draw_pass_1 = puff
	body.add_child(smoke)


# --- Примитивы и материалы ---

## Каждая коробка дома получает свой коллайдер: сквозь стену пройти нельзя,
## а форма совпадает с мешем точно — приблизительных прямоугольников больше нет.
func _box(body: Node3D, size: Vector3, pos: Vector3, mat: Material,
		solid: bool = true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = mat
	body.add_child(node)
	if solid:
		node.add_child(collider(size))
	return node


## Материал с процедурной текстурой и картой нормалей. Трипланар по мировым
## координатам: развёртки у коробок нет, а так рисунок ложится на все грани и
## не рвётся на стыке балок.
func _material(base: Color, frequency: float, bump: float,
		shade: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _noise_texture(frequency, shade, base)
	mat.normal_enabled = true
	mat.normal_texture = _noise_normal(frequency * 2.2, bump)
	mat.normal_scale = 1.4
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.45, 0.45, 0.45)
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


func _noise_texture(frequency: float, from: Color, to: Color) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 4
	noise.seed = _rng.randi()
	var ramp := Gradient.new()
	ramp.set_offset(0, 0.0)
	ramp.set_color(0, from)
	ramp.set_offset(1, 1.0)
	ramp.set_color(1, to)
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


## Материал из скачанного набора Poly Haven (CC0). tint подкрашивает скан, чтобы
## одно и то же дерево работало и балкой, и ставней. Трипланар по мировым
## координатам: у коробок нет развёртки, а рисунок должен идти сквозь стыки.
func _pbr(set_name: String, scale: float, fallback: Color,
		tint: Color) -> StandardMaterial3D:
	var base := "res://assets/textures/%s/%s_" % [set_name, set_name]
	if not ResourceLoader.exists(base + "diff_1k.jpg"):
		# Текстур нет — остаётся процедурный шум, дом всё равно построится.
		return _material(fallback, 0.05, 4.0, fallback.darkened(0.35))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(base + "diff_1k.jpg")
	mat.albedo_color = tint
	mat.normal_enabled = true
	mat.normal_texture = load(base + "nor_gl_1k.jpg")
	mat.normal_scale = 1.3
	mat.roughness_texture = load(base + "rough_1k.jpg")
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(scale, scale, scale)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Статичный коллайдер-коробка под меш. Отдельной функцией, потому что нужен и
## дому, и валу, и мосту.
static func collider(size: Vector3) -> StaticBody3D:
	var solid := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	solid.add_child(shape)
	return solid


## Настил: доски в один уровень с каменной отбортовкой по краю. Плитки кита
## ложились сеткой отдельных квадратов — сверху это читалось как разбросанные
## доски, а не как пол.
func deck(center: Vector3, size: Vector2, yaw: float = 0.0) -> void:
	var body := Node3D.new()
	body.position = center
	body.rotation.y = yaw
	root.add_child(body)
	_box(body, Vector3(size.x + 0.6, 0.4, size.y + 0.6), Vector3(0.0, 0.12, 0.0), plinth)
	_box(body, Vector3(size.x, 0.24, size.y), Vector3(0.0, 0.34, 0.0), timber)


# --- Навес ---

## Открытый навес под ту же крышу, что у домов: каменный настил, столбы с
## подкосами, крутой скат со свесом. Кузница собиралась из модулей кита —
## связка оранжевых палок под пирамидой рядом с домами не читалась как одна
## деревня.
func shelter(center: Vector3, size: Vector2, yaw: float) -> void:
	var body := Node3D.new()
	body.position = center
	body.rotation.y = yaw
	root.add_child(body)
	var w := size.x
	var d := size.y
	var wall := 3.1
	var pitch := deg_to_rad(PITCH)
	var half := d * 0.5 + EAVE
	var ridge := wall + (d * 0.5) * tan(pitch)
	_box(body, Vector3(w + 0.9, 0.55, d + 0.9), Vector3(0.0, 0.06, 0.0), plinth)
	_box(body, Vector3(w, 0.22, d), Vector3(0.0, 0.36, 0.0), timber)
	for sx: float in [-1.0, 0.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_lean(body, Vector3(0.32, wall, 0.32),
				Vector3(sx * w * 0.5, wall * 0.5 + 0.35, sz * d * 0.5), timber)
	for sz: float in [-1.0, 1.0]:
		_box(body, Vector3(w + 0.6, 0.26, 0.26),
			Vector3(0.0, wall + 0.35, sz * d * 0.5), timber)
	# Подкосы в углах: без них навес выглядит столами на ножках.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var brace := _box(body, Vector3(0.17, 1.2, 0.17),
				Vector3(sx * (w * 0.5 - 0.35), wall - 0.15, sz * (d * 0.5 - 0.3)), timber)
			brace.rotation.x = sz * 0.62
	_roof(body, w, half, wall + 0.35, ridge + 0.35, pitch)


# --- Износ ---
# Идеально прямые рёбра и одинаковые интервалы читаются как «сгенерировано».
# Ниже — минимальные отклонения, которые ломают эту правильность.

## Столб с лёгким завалом. Отклонение маленькое, но заметное: ряд абсолютно
## вертикальных стоек выглядит чертежом.
func _lean(body: Node3D, size: Vector3, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	var node := _box(body, size, pos, mat)
	node.rotation.x = _wear.randf_range(-0.035, 0.035)
	node.rotation.z = _wear.randf_range(-0.035, 0.035)
	return node


## Щербатый край кровли: пучки соломы вдоль свеса с неровным вылетом.
func _ragged_eave(body: Node3D, w: float, half: float, wall: float,
		pitch: float) -> void:
	var count := maxi(4, int(w / 0.7))
	for i: int in count:
		var x := lerpf(-w * 0.5 - EAVE * 0.8, w * 0.5 + EAVE * 0.8,
			float(i) / float(count - 1))
		for sz: float in [-1.0, 1.0]:
			var tuft := _box(body, Vector3(0.55, 0.16,
				_wear.randf_range(0.25, 0.6)),
				Vector3(x, wall - 0.12 + _wear.randf_range(-0.05, 0.05),
					sz * (half + 0.12)), thatch, false)
			tuft.rotation.x = sz * pitch + _wear.randf_range(-0.08, 0.08)


## Вытоптанная земля у порога. След использования — самое дешёвое, что отличает
## обжитое место от макета.
func _threshold(body: Node3D, w: float, d: float) -> void:
	var patch := _box(body, Vector3(minf(w, 3.4), 0.06, 2.2),
		Vector3(0.0, 0.62, d * 0.5 + 1.3), mud, false)
	patch.rotation.y = _wear.randf_range(-0.06, 0.06)
