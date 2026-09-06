class_name VillageGear
extends RefCounted
## Утварь деревни: заборы, фонари, телеги, лотки, столы, бочки, ящики, снопы,
## поленницы, колодец, грядки и валуны.
##
## Всё собирается из примитивов и красится теми же фотосканными материалами, что
## и дома. Раньше здесь стояли модели Kenney: пастельно-оранжевые, с плоской
## заливкой и в другом масштабе. Рядом со сканами камня и дерева они читались как
## игрушки из другого набора — именно это и выглядело неаккуратно.

const IRON := Color(0.09, 0.09, 0.10)
const CLOTH_A := Color(0.32, 0.13, 0.11)
const CLOTH_B := Color(0.13, 0.20, 0.32)

var root: Node3D
var build: VillageBuildings
var look: VillageLook
var blockers: Array[Rect2]
var iron: StandardMaterial3D
var cloth_red: StandardMaterial3D
var cloth_blue: StandardMaterial3D
var flame: StandardMaterial3D
var _wear: RandomNumberGenerator


func _init(parent: Node3D, buildings: VillageBuildings, village_look: VillageLook,
		obstacles: Array[Rect2]) -> void:
	root = parent
	build = buildings
	look = village_look
	blockers = obstacles
	iron = _flat(IRON, 0.45)
	cloth_red = _flat(CLOTH_A, 0.95)
	cloth_blue = _flat(CLOTH_B, 0.95)
	_wear = RandomNumberGenerator.new()
	_wear.seed = 5150
	flame = StandardMaterial3D.new()
	flame.albedo_color = Color(1.0, 0.62, 0.24)
	flame.emission_enabled = true
	flame.emission = Color(1.0, 0.55, 0.18)
	flame.emission_energy_multiplier = 8.0


# --- Забор ---

## Прясло между двумя точками: столбы через равные промежутки и две слеги.
## Именно равный шаг делает забор аккуратным — врозь стоящие секции читаются
## как мусор.
func fence_run(from: Vector2, to: Vector2, height: float = 1.25) -> void:
	var span := from.distance_to(to)
	if span < 0.5:
		return
	var count := maxi(1, int(round(span / 2.0)))
	var yaw := atan2(to.x - from.x, to.y - from.y)
	for i: int in count + 1:
		var p := from.lerp(to, float(i) / float(count))
		_post(p, height, 0.14)
	for level: float in [0.42, 0.78]:
		for i: int in count:
			var a := from.lerp(to, float(i) / float(count))
			var b := from.lerp(to, float(i + 1) / float(count))
			var mid := (a + b) * 0.5
			var rail := _box(Vector3(0.07, 0.14, a.distance_to(b) + 0.05),
				_at(mid, height * level), build.timber)
			rail.rotation.y = yaw


func _post(p: Vector2, height: float, thick: float) -> void:
	# Столб с лёгким завалом: идеально ровный ряд читается как чертёж.
	var post := _box(Vector3(thick, height, thick), _at(p, height * 0.5 - 0.1),
		build.timber)
	post.rotation.x = _wear.randf_range(-0.05, 0.05)
	post.rotation.z = _wear.randf_range(-0.05, 0.05)


# --- Фонарь ---

## Фонарный столб: каменная тумба, кованый стержень, кронштейн и фонарь с
## живым огнём. Свет от него делает улицу улицей, а не дорожкой по газону.
func lamp_post(p: Vector2, yaw: float = 0.0) -> void:
	var base := _at(p, 0.0)
	_box(Vector3(0.55, 0.42, 0.55), base + Vector3(0.0, 0.16, 0.0), build.plinth)
	var mast := _cylinder(0.075, 3.1, base + Vector3(0.0, 1.75, 0.0), iron)
	mast.rotation.x = _wear.randf_range(-0.03, 0.03)
	mast.rotation.z = _wear.randf_range(-0.03, 0.03)
	var head := base + Vector3(0.0, 3.35, 0.0)
	_box(Vector3(0.36, 0.10, 0.36), head + Vector3(0.0, 0.30, 0.0), iron)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
		var edge := _box(Vector3(0.05, 0.44, 0.05),
			head + Vector3(corner.x * 0.15, 0.05, corner.y * 0.15), iron)
		edge.rotation.y = yaw
	_box(Vector3(0.20, 0.30, 0.20), head + Vector3(0.0, 0.03, 0.0), flame)
	var light := OmniLight3D.new()
	light.position = head + Vector3(0.0, 0.05, 0.0)
	light.light_color = Color(1.0, 0.72, 0.38)
	light.light_energy = 2.6
	light.omni_range = 11.0
	light.shadow_enabled = false
	root.add_child(light)


# --- Телега ---

func cart(p: Vector2, yaw: float) -> void:
	var body := _group(p, 0.0, yaw)
	_local(body, Vector3(2.3, 0.16, 1.15), Vector3(0.0, 0.72, 0.0), build.timber)
	for side: float in [-1.0, 1.0]:
		_local(body, Vector3(2.3, 0.42, 0.09), Vector3(0.0, 0.98, side * 0.53),
			build.timber)
	_local(body, Vector3(0.09, 0.42, 1.15), Vector3(-1.10, 0.98, 0.0), build.timber)
	# Оглобли вперёд: телега без них выглядит ящиком на колёсах.
	for side: float in [-0.42, 0.42]:
		_local(body, Vector3(1.5, 0.09, 0.09), Vector3(1.85, 0.62, side), build.timber)
	for side: float in [-0.62, 0.62]:
		var wheel := _local(body, Vector3(0.0, 0.0, 0.0), Vector3(-0.35, 0.52, side),
			iron)
		wheel.queue_free()
		_wheel(body, Vector3(-0.35, 0.52, side))
	_block(p, Vector2(2.4, 1.4))


func _wheel(body: Node3D, pos: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.52
	mesh.bottom_radius = 0.52
	mesh.height = 0.14
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	# Колесо лежит в вертикальной плоскости, поэтому цилиндр кладём набок.
	node.rotation.x = PI * 0.5
	node.material_override = build.timber
	body.add_child(node)
	node.add_child(VillageBuildings.collider(Vector3(1.04, 0.14, 1.04)))
	for spoke: int in 4:
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.9, 0.07, 0.07)
		bar.mesh = bar_mesh
		bar.position = pos
		bar.rotation = Vector3(0.0, 0.0, float(spoke) * PI * 0.25)
		bar.material_override = iron
		body.add_child(bar)


# --- Лоток, стол, скамья ---

## Торговый лоток: прилавок, четыре стойки и полотняный навес двумя скатами.
func stall(p: Vector2, yaw: float, red: bool) -> void:
	var body := _group(p, 0.0, yaw)
	var canopy := cloth_red if red else cloth_blue
	_local(body, Vector3(2.4, 0.14, 1.0), Vector3(0.0, 0.95, 0.0), build.timber)
	_local(body, Vector3(2.4, 0.55, 0.08), Vector3(0.0, 0.66, -0.46), build.timber)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_local(body, Vector3(0.10, 2.2, 0.10),
				Vector3(sx * 1.12, 1.1, sz * 0.46), build.timber)
	for sz: float in [-1.0, 1.0]:
		var slope := _local(body, Vector3(2.7, 0.07, 0.95),
			Vector3(0.0, 2.35, sz * 0.42), canopy)
		slope.rotation.x = sz * 0.55
	_local(body, Vector3(2.7, 0.10, 0.10), Vector3(0.0, 2.58, 0.0), build.timber)
	# Товар на прилавке.
	for i: int in 3:
		_local(body, Vector3(0.34, 0.30, 0.30),
			Vector3(-0.7 + float(i) * 0.7, 1.17, 0.0), build.timber)
	_block(p, Vector2(2.6, 1.3))


func bench(p: Vector2, yaw: float) -> void:
	var body := _group(p, 0.0, yaw)
	_local(body, Vector3(1.7, 0.10, 0.40), Vector3(0.0, 0.46, 0.0), build.timber)
	for side: float in [-1.0, 1.0]:
		_local(body, Vector3(0.12, 0.46, 0.36), Vector3(side * 0.72, 0.23, 0.0),
			build.timber)


func table(p: Vector2, yaw: float) -> void:
	var body := _group(p, 0.0, yaw)
	_local(body, Vector3(1.9, 0.12, 0.95), Vector3(0.0, 0.78, 0.0), build.timber)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_local(body, Vector3(0.11, 0.78, 0.11),
				Vector3(sx * 0.82, 0.39, sz * 0.36), build.timber)
	_block(p, Vector2(2.0, 1.1))


# --- Тара и запасы ---

func barrel(p: Vector2, height: float = 0.9) -> void:
	var base := _at(p, 0.0)
	_cylinder(0.34, height, base + Vector3(0.0, height * 0.5, 0.0), build.timber)
	for level: float in [0.22, 0.78]:
		_cylinder(0.36, 0.07, base + Vector3(0.0, height * level, 0.0), iron)


func crate(p: Vector2, yaw: float, size: float = 0.7) -> void:
	var body := _group(p, 0.0, yaw)
	_local(body, Vector3(size, size, size), Vector3(0.0, size * 0.5, 0.0), build.timber)
	for edge: float in [-1.0, 1.0]:
		_local(body, Vector3(size + 0.03, 0.07, 0.07),
			Vector3(0.0, size * 0.5, edge * size * 0.5), iron)


func hay_bale(p: Vector2, yaw: float) -> void:
	var body := _group(p, 0.0, yaw)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.55
	mesh.height = 1.1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = Vector3(0.0, 0.55, 0.0)
	node.rotation.z = PI * 0.5
	node.material_override = build.thatch
	body.add_child(node)
	node.add_child(VillageBuildings.collider(Vector3(1.1, 1.1, 1.1)))


## Поленница: ряды брёвен в перевязку. Аккуратная кладка сама по себе читается
## как признак жилого места.
func log_pile(p: Vector2, yaw: float) -> void:
	var body := _group(p, 0.0, yaw)
	for row: int in 3:
		for i: int in 4:
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.14
			mesh.bottom_radius = 0.14
			mesh.height = 1.6
			var node := MeshInstance3D.new()
			node.mesh = mesh
			node.position = Vector3(0.0, 0.15 + float(row) * 0.27,
				-0.42 + float(i) * 0.28 + (0.14 if row % 2 == 1 else 0.0))
			node.rotation.z = PI * 0.5
			node.material_override = build.timber
			body.add_child(node)
	_block(p, Vector2(1.8, 1.4))


# --- Колодец и грядки ---

func well(p: Vector2) -> void:
	var base := _at(p, 0.0)
	_cylinder(1.05, 0.9, base + Vector3(0.0, 0.45, 0.0), build.plinth)
	_cylinder(0.86, 0.95, base + Vector3(0.0, 0.5, 0.0), build.plinth)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.16, 2.0, 0.16), base + Vector3(side * 0.85, 1.9, 0.0),
			build.timber)
	_cylinder(0.10, 1.9, base + Vector3(0.0, 2.75, 0.0), build.timber)
	for sz: float in [-1.0, 1.0]:
		var slope := _box(Vector3(2.4, 0.10, 1.1), base + Vector3(0.0, 3.05, sz * 0.48),
			build.thatch)
		slope.rotation.x = sz * 0.6
	_block(p, Vector2(2.2, 2.2))


## Грядки: насыпные гряды из земли с бороздами между ними, всходы рядами и
## пугало. Прежняя версия ставила каменные бруски торчком — сверху это читалось
## как ряд зубьев, а не как огород.
func field(center: Vector2, size: Vector2, yaw: float) -> void:
	var body := _group(center, 0.0, yaw)
	var beds := maxi(3, int(size.y / 1.5))
	for i: int in beds:
		var z := -size.y * 0.5 + (float(i) + 0.5) * size.y / float(beds)
		# Гряда чуть выше борозды: перепад в 12 сантиметров даёт тень между
		# рядами, и огород читается как вспаханный.
		var bed := _local(body, Vector3(size.x - 0.8, 0.24, 0.95),
			Vector3(0.0, 0.10, z), build.mud, false)
		bed.rotation.x = _wear.randf_range(-0.01, 0.01)
		# Всходы: короткие ряды зелени поперёк гряды.
		var sprouts := maxi(4, int((size.x - 1.2) / 0.55))
		for s: int in sprouts:
			var x := lerpf(-(size.x - 1.6) * 0.5, (size.x - 1.6) * 0.5,
				float(s) / float(sprouts - 1))
			var leaf := _local(body, Vector3(0.20, 0.34, 0.20),
				Vector3(x, 0.32, z), build.needles, false)
			leaf.rotation.y = _wear.randf() * TAU
			leaf.rotation.x = _wear.randf_range(-0.14, 0.14)
	_scarecrow(body, Vector3(size.x * 0.5 - 1.0, 0.0, 0.0))
	var half := size * 0.5
	fence_run(center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y), 0.9)
	fence_run(center + Vector2(-half.x, half.y), center + Vector2(half.x, half.y), 0.9)
	fence_run(center + Vector2(-half.x, -half.y), center + Vector2(-half.x, half.y), 0.9)
	fence_run(center + Vector2(half.x, -half.y), center + Vector2(half.x, half.y), 0.9)


## Пугало: крестовина, соломенное туловище, шляпа. Мелочь, но именно она
## превращает грядки в чей-то огород.
func _scarecrow(body: Node3D, pos: Vector3) -> void:
	_local(body, Vector3(0.11, 2.1, 0.11), pos + Vector3(0.0, 1.05, 0.0), build.timber)
	_local(body, Vector3(1.25, 0.09, 0.09), pos + Vector3(0.0, 1.55, 0.0), build.timber)
	_local(body, Vector3(0.44, 0.70, 0.30), pos + Vector3(0.0, 1.35, 0.0), build.thatch)
	_local(body, Vector3(0.30, 0.30, 0.28), pos + Vector3(0.0, 1.86, 0.0), build.thatch)
	var hat := _local(body, Vector3(0.62, 0.10, 0.62), pos + Vector3(0.0, 2.04, 0.0),
		build.thatch, false)
	hat.rotation.z = 0.18

# --- Валун ---

## Валун из сплюснутой сферы со скальной текстурой. Модель камня из кита была
## гранёным многоугольником одного цвета и рядом со сканом скалы бросалась в глаза.
func boulder(p: Vector2, size: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mesh := SphereMesh.new()
	mesh.radius = size * 0.5
	mesh.height = size
	mesh.radial_segments = 7
	mesh.rings = 4
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = _at(p, size * 0.28)
	node.scale = Vector3(rng.randf_range(0.9, 1.5), rng.randf_range(0.5, 0.85),
		rng.randf_range(0.9, 1.4))
	node.rotation.y = rng.randf() * TAU
	node.material_override = build.plinth
	root.add_child(node)
	node.add_child(VillageBuildings.collider(Vector3(size, size, size)))


# --- Примитивы ---

func _at(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, look.height_at(p.x, p.y) + y, p.y)


func _group(p: Vector2, y: float, yaw: float) -> Node3D:
	var body := Node3D.new()
	body.position = _at(p, y)
	body.rotation.y = yaw
	root.add_child(body)
	return body


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = mat
	root.add_child(node)
	node.add_child(VillageBuildings.collider(size))
	return node


func _local(body: Node3D, size: Vector3, pos: Vector3, mat: Material,
		solid: bool = true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = mat
	body.add_child(node)
	if solid:
		node.add_child(VillageBuildings.collider(size))
	return node


func _cylinder(radius: float, height: float, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = mat
	root.add_child(node)
	node.add_child(VillageBuildings.collider(Vector3(radius * 2.0, height, radius * 2.0)))
	return node


func _flat(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	return mat


## Габарит в плане для списка препятствий: по нему обстановка ищет свободные
## места, чтобы предметы не наезжали друг на друга.
func _block(p: Vector2, size: Vector2) -> void:
	if blockers != null:
		blockers.append(Rect2(p - size * 0.5, size))


# --- Ель ---

## Ель из ствола-конуса и нескольких ярусов лап. Модель из кита — шестигранный
## конус одного цвета: вблизи она и делала картинку игрушечной. Здесь ярусы
## разного радиуса с разворотом дают неровный силуэт и самозатенение.
func conifer(p: Vector2, height: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var body := _group(p, -0.25, rng.randf() * TAU)
	var trunk := CylinderMesh.new()
	trunk.top_radius = height * 0.008
	trunk.bottom_radius = height * 0.032
	trunk.height = height
	var stem := MeshInstance3D.new()
	stem.mesh = trunk
	stem.position = Vector3(0.0, height * 0.5, 0.0)
	stem.material_override = build.timber
	body.add_child(stem)
	stem.add_child(VillageBuildings.collider(
		Vector3(height * 0.07, height, height * 0.07)))
	# Много тонких ярусов вместо шести толстых: у шести конусов силуэт читается
	# как ёлочная игрушка, у четырнадцати с разбросом радиуса — как дерево.
	var tiers := 14
	for i: int in tiers:
		var t := float(i) / float(tiers - 1)
		# Радиус спадает не линейно: у настоящей ели низ раскидистый, а верх
		# вытянут в шпиль.
		var spread := lerpf(1.0, 0.05, pow(t, 0.75)) * rng.randf_range(0.78, 1.15)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = height * 0.24 * spread
		cone.height = height * (0.13 + 0.06 * (1.0 - t))
		cone.radial_segments = 9
		var tier := MeshInstance3D.new()
		tier.mesh = cone
		var lift := lerpf(height * 0.16, height * 0.99, t)
		# Смещение яруса вбок: соосные конусы дают правильный конус вращения,
		# которого в природе не бывает.
		tier.position = Vector3(rng.randf_range(-1.0, 1.0) * height * 0.02, lift,
			rng.randf_range(-1.0, 1.0) * height * 0.02)
		tier.rotation.y = rng.randf() * TAU
		tier.rotation.x = rng.randf_range(-0.09, 0.09)
		tier.rotation.z = rng.randf_range(-0.09, 0.09)
		tier.material_override = build.needles
		body.add_child(tier)
	# Сухие нижние сучья: голый ствол внизу — признак взрослого дерева.
	for i: int in 3:
		var branch := MeshInstance3D.new()
		var bar := CylinderMesh.new()
		bar.top_radius = height * 0.004
		bar.bottom_radius = height * 0.008
		bar.height = height * rng.randf_range(0.10, 0.18)
		branch.mesh = bar
		branch.position = Vector3(0.0, height * rng.randf_range(0.10, 0.15), 0.0)
		branch.rotation = Vector3(0.0, rng.randf() * TAU, PI * 0.42)
		branch.material_override = build.timber
		body.add_child(branch)


# --- Трава ---

## Пучок травы: несколько сужающихся кверху стеблей, развёрнутых по кругу и
## наклонённых наружу. Модель из кита была плоской вырезкой — с любого угла,
## кроме фронтального, она пропадала в линию. Цвет кладём в вершины: у корня
## тёмный, у кончика светлее, поэтому пучок читается объёмным без текстуры.
static func grass_tuft(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_tone := Color(0.13, 0.17, 0.08)
	var tip_tone := Color(0.42, 0.48, 0.22)
	for blade: int in 7:
		var yaw := rng.randf() * TAU
		var lean := rng.randf_range(0.15, 0.5)
		var height := rng.randf_range(0.7, 1.0)
		var half := rng.randf_range(0.035, 0.055)
		var dir := Vector3(sin(yaw), 0.0, cos(yaw))
		var side := Vector3(dir.z, 0.0, -dir.x) * half
		var tip := dir * lean * height + Vector3(0.0, height, 0.0)
		var mid := dir * lean * height * 0.35 + Vector3(0.0, height * 0.55, 0.0)
		var mid_tone := root_tone.lerp(tip_tone, 0.55)
		# Стебель из двух сегментов: один треугольник ломался бы на изгибе.
		_blade(st, -side, side, mid - side * 0.6, mid + side * 0.6,
			root_tone, mid_tone)
		_blade(st, mid - side * 0.6, mid + side * 0.6, tip, tip, mid_tone, tip_tone)
	st.generate_normals()
	return st.commit()


static func _blade(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		low: Color, high: Color) -> void:
	for step: Array in [[a, low], [b, low], [d, high], [a, low], [d, high], [c, high]]:
		st.set_color(step[1])
		st.add_vertex(step[0])


# --- Врата Разлома ---

## Портал: два массива тёсаного камня с уступами, тяжёлая перемычка и полотно
## огня в проёме. Арка из замкового кита была ярко-оранжевой коробкой с зубцами —
## на фоне каменной деревни она читалась как деталь из другой игры.
func rift_gate(p: Vector2, yaw: float) -> void:
	var body := _group(p, 0.0, yaw)
	var span := 2.2
	for side: float in [-1.0, 1.0]:
		# Столб из трёх блоков с уступом: ровный параллелепипед выглядит
		# заготовкой, а ступенчатый — тёсаным камнем.
		_local(body, Vector3(1.9, 2.6, 2.0), Vector3(side * span, 1.3, 0.0),
			build.plinth)
		_local(body, Vector3(1.6, 2.4, 1.7), Vector3(side * span, 3.7, 0.0),
			build.plinth)
		_local(body, Vector3(1.35, 1.6, 1.45), Vector3(side * span, 5.7, 0.0),
			build.plinth)
		# Руны на внутренней грани.
		for i: int in 3:
			_local(body, Vector3(0.10, 0.34, 0.06),
				Vector3(side * (span - 0.85), 2.2 + float(i) * 1.1, 0.78), flame,
				false)
	_local(body, Vector3(6.4, 1.3, 2.1), Vector3(0.0, 7.1, 0.0), build.plinth)
	_local(body, Vector3(5.2, 0.5, 1.6), Vector3(0.0, 7.95, 0.0), build.plinth)
	# Полотно разлома: тонкая плита с сильным свечением. Свет от неё и делает
	# проём воротами, а не дырой в стене.
	var rift := _local(body, Vector3(2.6, 5.6, 0.22), Vector3(0.0, 3.2, 0.0),
		flame, false)
	rift.rotation.z = 0.02
	var glow := OmniLight3D.new()
	glow.position = _at(p, 3.2)
	glow.light_color = Color(1.0, 0.42, 0.12)
	glow.light_energy = 9.0
	glow.omni_range = 22.0
	glow.shadow_enabled = false
	root.add_child(glow)
	# Угли, летящие из проёма.
	var sparks := GPUParticles3D.new()
	sparks.position = _at(p, 1.4)
	sparks.amount = 60
	sparks.lifetime = 3.2
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(1.2, 2.4, 0.1)
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 25.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 2.0
	process.gravity = Vector3(0.0, 0.9, 0.0)
	process.scale_min = 0.2
	process.scale_max = 0.6
	process.color = Color(1.0, 0.55, 0.18)
	sparks.process_material = process
	var ember := QuadMesh.new()
	ember.size = Vector2(0.13, 0.13)
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_mat.albedo_color = Color(1.0, 0.5, 0.15, 0.9)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.45, 0.12)
	ember_mat.emission_energy_multiplier = 5.0
	ember.material = ember_mat
	sparks.draw_pass_1 = ember
	root.add_child(sparks)
	_block(p, Vector2(7.0, 2.6))


# --- Кузнечное ---

## Наковальня: пята, талия, рог. Коробка на коробке не читалась как наковальня —
## а силуэт здесь важнее полигонов.
func anvil(p: Vector2, yaw: float) -> void:
	var body := _group(p, 0.0, yaw)
	_local(body, Vector3(0.85, 0.30, 0.85), Vector3(0.0, 0.15, 0.0), build.timber)
	_local(body, Vector3(0.62, 0.22, 0.62), Vector3(0.0, 0.41, 0.0), iron)
	_local(body, Vector3(0.34, 0.30, 0.40), Vector3(0.0, 0.66, 0.0), iron)
	_local(body, Vector3(1.30, 0.22, 0.46), Vector3(0.0, 0.90, 0.0), iron)
	var horn := _local(body, Vector3(0.44, 0.17, 0.30), Vector3(0.80, 0.90, 0.0), iron)
	horn.rotation.z = -0.08
	_block(p, Vector2(1.4, 0.8))


## Стойка с оружием: клинки и топорища под наклоном в рамe. Оружие, торчащее
## из земли прямыми брусками, и было тем «детским садом».
func weapon_rack(p: Vector2, yaw: float) -> void:
	var body := _group(p, 0.0, yaw)
	for side: float in [-1.0, 1.0]:
		_local(body, Vector3(0.12, 1.5, 0.12), Vector3(side * 0.85, 0.75, 0.0),
			build.timber)
	_local(body, Vector3(1.9, 0.12, 0.14), Vector3(0.0, 1.42, 0.0), build.timber)
	_local(body, Vector3(1.9, 0.12, 0.14), Vector3(0.0, 0.55, 0.0), build.timber)
	for i: int in 4:
		var x := -0.62 + float(i) * 0.42
		var blade := _local(body, Vector3(0.07, 1.25, 0.20), Vector3(x, 0.95, 0.0), iron)
		blade.rotation.z = _wear.randf_range(-0.12, 0.12)
		_local(body, Vector3(0.10, 0.26, 0.10), Vector3(x, 1.62, 0.0), build.timber)
	_block(p, Vector2(2.0, 0.6))


## Тренировочный манекен: столб, перекладина, соломенное туловище и мешок вместо
## головы. Шар на палке выглядел игрушкой.
func dummy(p: Vector2, yaw: float) -> void:
	var body := _group(p, 0.0, yaw)
	_local(body, Vector3(0.16, 1.9, 0.16), Vector3(0.0, 0.95, 0.0), build.timber)
	_local(body, Vector3(1.35, 0.13, 0.13), Vector3(0.0, 1.45, 0.0), build.timber)
	var torso := _local(body, Vector3(0.52, 0.85, 0.38), Vector3(0.0, 1.20, 0.0),
		build.thatch)
	torso.rotation.z = _wear.randf_range(-0.06, 0.06)
	_local(body, Vector3(0.34, 0.34, 0.32), Vector3(0.0, 1.80, 0.0), build.thatch)
	# Обвязка: два обруча по туловищу.
	for level: float in [1.05, 1.38]:
		_local(body, Vector3(0.56, 0.07, 0.42), Vector3(0.0, level, 0.0), iron, false)
	_block(p, Vector2(1.4, 0.7))


## Жаровня на треноге с углями. Отдельно, потому что нужна и у врат, и у горна.
func brazier(p: Vector2) -> void:
	var base := _at(p, 0.0)
	for i: int in 3:
		var leg := _cylinder(0.06, 1.0, base + Vector3(
			sin(float(i) * TAU / 3.0) * 0.28, 0.5,
			cos(float(i) * TAU / 3.0) * 0.28), iron)
		leg.rotation.x = sin(float(i) * TAU / 3.0) * 0.22
		leg.rotation.z = -cos(float(i) * TAU / 3.0) * 0.22
	_cylinder(0.45, 0.30, base + Vector3(0.0, 1.05, 0.0), iron)
	_cylinder(0.38, 0.16, base + Vector3(0.0, 1.20, 0.0), flame)
	var light := OmniLight3D.new()
	light.position = base + Vector3(0.0, 1.4, 0.0)
	light.light_color = Color(1.0, 0.56, 0.22)
	light.light_energy = 3.4
	light.omni_range = 12.0
	light.shadow_enabled = false
	root.add_child(light)
	_block(p, Vector2(1.0, 1.0))


# --- Алтарь и горн ---

## Алтарь: тёсаная плита на ступенчатом основании, свечи и каменный крест.
## Модель из кладбищенского кита была плоской заливкой и рядом с фотосканной
## кладкой часовни выбивалась сильнее всего.
func altar(p: Vector2, yaw: float) -> void:
	var body := _group(p, 0.0, yaw)
	_local(body, Vector3(2.6, 0.28, 1.5), Vector3(0.0, 0.14, 0.0), build.plinth)
	_local(body, Vector3(2.2, 0.30, 1.2), Vector3(0.0, 0.42, 0.0), build.plinth)
	_local(body, Vector3(1.5, 0.55, 0.85), Vector3(0.0, 0.85, 0.0), build.plinth)
	# Столешница шире опоры: свес даёт тень и читается как отдельная плита.
	_local(body, Vector3(2.4, 0.20, 1.35), Vector3(0.0, 1.22, 0.0), build.plinth)
	for side: float in [-1.0, 1.0]:
		_local(body, Vector3(0.13, 0.34, 0.13), Vector3(side * 0.85, 1.49, 0.0),
			build.timber)
		_local(body, Vector3(0.10, 0.13, 0.10), Vector3(side * 0.85, 1.72, 0.0),
			flame, false)
		var candle := OmniLight3D.new()
		candle.position = _at(p, 1.75) + Vector3(side * 0.85, 0.0, 0.0)
		candle.light_color = Color(1.0, 0.74, 0.42)
		candle.light_energy = 1.8
		candle.omni_range = 6.0
		candle.shadow_enabled = false
		root.add_child(candle)
	# Крест за алтарём.
	_local(body, Vector3(0.26, 2.4, 0.26), Vector3(0.0, 1.2, -1.1), build.plinth)
	_local(body, Vector3(1.3, 0.24, 0.24), Vector3(0.0, 2.05, -1.1), build.plinth)
	_block(p, Vector2(2.8, 1.8))


## Горн: каменный массив с арочным устьем, угли внутри и сужающаяся кверху
## труба. Прежде это была чёрная коробка со светящейся плитой — самая грубая
## вещь во всей деревне.
func forge_hearth(p: Vector2, yaw: float) -> void:
	var body := _group(p, 0.0, yaw)
	_local(body, Vector3(2.9, 1.05, 1.9), Vector3(0.0, 0.52, 0.0), build.plinth)
	# Устье: две щеки и перемычка вместо сплошной стены — получается проём.
	for side: float in [-1.0, 1.0]:
		_local(body, Vector3(0.75, 1.1, 1.9), Vector3(side * 1.07, 1.60, 0.0),
			build.plinth)
	_local(body, Vector3(2.9, 0.42, 1.9), Vector3(0.0, 2.36, 0.0), build.plinth)
	_local(body, Vector3(1.4, 0.22, 1.5), Vector3(0.0, 1.16, 0.0), flame, false)
	_local(body, Vector3(1.2, 0.5, 1.2), Vector3(0.0, 1.35, -0.2), iron, false)
	# Труба с уступом: прямой столб выглядит колонной, а не дымоходом.
	_local(body, Vector3(1.9, 1.3, 1.5), Vector3(0.0, 3.2, 0.0), build.plinth)
	_local(body, Vector3(1.3, 1.5, 1.1), Vector3(0.0, 4.6, 0.0), build.plinth)
	_local(body, Vector3(1.5, 0.24, 1.3), Vector3(0.0, 5.45, 0.0), build.plinth)
	var fire := OmniLight3D.new()
	fire.position = _at(p, 1.4)
	fire.light_color = Color(1.0, 0.52, 0.20)
	fire.light_energy = 5.0
	fire.omni_range = 14.0
	fire.shadow_enabled = false
	root.add_child(fire)
	_block(p, Vector2(3.2, 2.2))
