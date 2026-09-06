class_name ActorModel
extends RefCounted
## Модели существ с суставами. Это не авторские модели из редактора, а собранная
## из примитивов фигура — но с торсом, головой, двумя руками и двумя ногами,
## каждая на своём шарнире. Именно шарниры позволяют анимировать удары и
## сотворение заклинаний (см. ActorAnimator).
##
## Узлы именованы одинаково у героев и врагов, поэтому анимации общие:
##   Torso, Head, ShoulderL/R -> ForearmL/R, HipL/R -> ShinL/R, Weapon.

const HERO_HEIGHT := 1.8

## Конечность на шарнире: сам узел стоит в суставе, меш смещён вниз на половину
## длины, поэтому поворот узла машет конечностью, а не двигает её вбок.
static func limb(parent: Node3D, joint: Vector3, length: float, thickness: float,
		color: Color, node_name: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = joint
	parent.add_child(pivot)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, length, thickness)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position.y = -length * 0.5
	node.material_override = _material(color, 0.9)
	pivot.add_child(node)
	return pivot

static func _material(color: Color, roughness: float, glow: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.2
	return mat

static func _attach(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color,
		node_name: String = "", glow: bool = false, yaw: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation.y = yaw
	node.material_override = _material(color, 0.9, glow)
	if not node_name.is_empty():
		node.name = node_name
	parent.add_child(node)
	return node

static func _capsule(height: float, radius: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.height = height
	mesh.radius = radius
	return mesh

static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh

static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

static func _prism(size: Vector3) -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = size
	return mesh

# --- Герой: капсульный торс, голова, две руки и две ноги на шарнирах ---

static func build_hero(display_name: String, tint: Color, model_id: StringName = &"") -> Node3D:
	# Готовая модель героя, если она положена в assets/models/actors.
	var external := ModelLibrary.build("actors", String(model_id))
	if external != null:
		external.name = display_name
		external.set_meta("model_kind", "hero")
		return external
	var root := Node3D.new()
	root.name = display_name
	root.set_meta("model_kind", "hero")
	var hip := 0.86
	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position.y = hip
	root.add_child(torso)
	_attach(torso, _capsule(0.62, 0.21), Vector3(0.0, 0.3, 0.0), tint)
	_attach(torso, _box(Vector3(0.5, 0.14, 0.28)), Vector3(0.0, 0.52, 0.0), tint.darkened(0.2))
	_attach(torso, _box(Vector3(0.46, 0.16, 0.3)), Vector3(0.0, 0.02, 0.0), tint.darkened(0.35))
	var head := _attach(torso, _sphere(0.17), Vector3(0.0, 0.74, 0.0), tint.lightened(0.2), "Head")
	_attach(head, _box(Vector3(0.3, 0.1, 0.32)), Vector3(0.0, 0.1, 0.0), tint.darkened(0.4))
	# Плащ за спиной — узнаваемый вертикальный силуэт.
	var cloak := _attach(torso, _box(Vector3(0.5, 0.78, 0.08)), Vector3(0.0, 0.18, 0.17),
		tint.darkened(0.45), "Cloak")
	cloak.rotation.x = deg_to_rad(-4.0)
	for side: float in [-1.0, 1.0]:
		var tag := "R" if side > 0.0 else "L"
		var shoulder := limb(torso, Vector3(side * 0.26, 0.5, 0.0), 0.3, 0.13,
			tint.darkened(0.1), "Shoulder" + tag)
		var forearm := limb(shoulder, Vector3(0.0, -0.3, 0.0), 0.28, 0.11,
			tint.lightened(0.05), "Forearm" + tag)
		_attach(forearm, _sphere(0.075), Vector3(0.0, -0.28, 0.0), tint.lightened(0.25))
		var hip_joint := limb(root, Vector3(side * 0.13, hip, 0.0), 0.44, 0.16,
			tint.darkened(0.3), "Hip" + tag)
		var shin := limb(hip_joint, Vector3(0.0, -0.44, 0.0), 0.42, 0.14,
			tint.darkened(0.15), "Shin" + tag)
		_attach(shin, _box(Vector3(0.18, 0.1, 0.3)), Vector3(0.0, -0.45, 0.05), tint.darkened(0.5))
	# Оружие в правой руке — им и машет анимация удара.
	var hand: Node3D = torso.get_node("ShoulderR/ForearmR")
	var weapon := Node3D.new()
	weapon.name = "Weapon"
	weapon.position = Vector3(0.0, -0.26, 0.0)
	hand.add_child(weapon)
	_attach(weapon, _box(Vector3(0.07, 0.72, 0.07)), Vector3(0.0, -0.3, 0.0), Color(0.66, 0.65, 0.6))
	_attach(weapon, _box(Vector3(0.24, 0.07, 0.09)), Vector3(0.0, 0.02, 0.0), Color(0.4, 0.32, 0.2))
	return root

# --- Враг: та же схема суставов, но угловатые формы и светящиеся глаза ---

static func build_enemy(data: EnemyData, elite: bool, tint: Color) -> Node3D:
	var model_id := String(data.id) if data != null else "enemy_default"
	var external := ModelLibrary.build("actors", model_id)
	if external == null:
		external = ModelLibrary.build("actors", "enemy_default")
	if external != null:
		external.name = data.display_name if data != null else "Враг"
		external.set_meta("model_kind", "enemy")
		return external
	var root := Node3D.new()
	root.name = data.display_name if data != null else "Враг"
	root.set_meta("model_kind", "enemy")
	var shape := _shape_for(data)
	var s: float = shape["scale"]
	var hip: float = 0.8 * s
	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position.y = hip
	torso.rotation.x = deg_to_rad(float(shape["lean"]))
	root.add_child(torso)
	_attach(torso, _box(Vector3(shape["width"], 0.62, shape["depth"]) * s),
		Vector3(0.0, 0.3, 0.0), tint, "", false, deg_to_rad(45.0))
	var head := _attach(torso, _prism(Vector3(0.42, 0.36, 0.42) * s), Vector3(0.0, 0.78 * s, 0.0),
		tint.darkened(0.25), "Head", false, deg_to_rad(45.0))
	for side: float in [-1.0, 1.0]:
		_attach(head, _sphere(0.055 * s), Vector3(side * 0.11 * s, 0.02 * s, -0.17 * s),
			Color(1.0, 0.35, 0.2), "", true)
	for side: float in [-1.0, 1.0]:
		var tag := "R" if side > 0.0 else "L"
		var shoulder := limb(torso, Vector3(side * 0.3 * s, 0.48 * s, 0.0), 0.3 * s, 0.14 * s,
			tint.darkened(0.1), "Shoulder" + tag)
		var forearm := limb(shoulder, Vector3(0.0, -0.3 * s, 0.0), 0.3 * s, 0.12 * s,
			tint.lightened(0.1), "Forearm" + tag)
		_attach(forearm, _prism(Vector3(0.16, 0.26, 0.16) * s), Vector3(0.0, -0.36 * s, 0.0),
			tint.lightened(0.3))
		var hip_joint := limb(root, Vector3(side * 0.15 * s, hip, 0.0), 0.4 * s, 0.16 * s,
			tint.darkened(0.3), "Hip" + tag)
		limb(hip_joint, Vector3(0.0, -0.4 * s, 0.0), 0.38 * s, 0.14 * s,
			tint.darkened(0.15), "Shin" + tag)
	for spike: Dictionary in shape["spikes"]:
		var node := _attach(torso, _prism(Vector3(0.16, 0.42, 0.16) * s),
			(spike["pos"] as Vector3) * s + Vector3(0.0, 0.35 * s, 0.0), tint.lightened(0.2))
		node.rotation_degrees = spike["rot"]
	var weapon := Node3D.new()
	weapon.name = "Weapon"
	weapon.position = Vector3(0.0, -0.3 * s, 0.0)
	(torso.get_node("ShoulderR/ForearmR") as Node3D).add_child(weapon)
	_attach(weapon, _prism(Vector3(0.14, 0.7, 0.12) * s), Vector3(0.0, -0.3 * s, 0.0),
		tint.lightened(0.35))
	if elite or (data != null and data.is_boss):
		_add_crown(root, hip + 1.0 * s, s, tint)
	return root

## Пропорции и приметы по архетипу поведения (02-combat.md, раздел 10.2).
static func _shape_for(data: EnemyData) -> Dictionary:
	var behavior: StringName = data.behavior if data != null else &"aggressive"
	var size: int = data.size_cells if data != null else 1
	var shape := {"width": 0.6, "depth": 0.6, "scale": 1.0, "lean": 0.0, "spikes": []}
	match behavior:
		&"swarm":
			shape["scale"] = 0.74
		&"ranged":
			shape["width"] = 0.48
			shape["depth"] = 0.48
			shape["spikes"] = [{"pos": Vector3(0.0, 0.25, 0.34), "rot": Vector3(-70.0, 0.0, 0.0)}]
		&"guard":
			shape["width"] = 0.82
			shape["depth"] = 0.68
			shape["spikes"] = [{"pos": Vector3(-0.46, 0.16, 0.0), "rot": Vector3(0.0, 0.0, 35.0)},
				{"pos": Vector3(0.46, 0.16, 0.0), "rot": Vector3(0.0, 0.0, -35.0)}]
		&"ambush":
			shape["lean"] = 16.0
			shape["width"] = 0.5
		&"support":
			shape["width"] = 0.54
			shape["spikes"] = [{"pos": Vector3(0.0, 0.86, 0.0), "rot": Vector3.ZERO}]
		_:
			shape["spikes"] = [{"pos": Vector3(-0.4, 0.24, 0.0), "rot": Vector3(0.0, 0.0, 40.0)},
				{"pos": Vector3(0.4, 0.24, 0.0), "rot": Vector3(0.0, 0.0, -40.0)}]
	shape["scale"] = float(shape["scale"]) * (1.0 + 0.35 * float(maxi(0, size - 1)))
	return shape

## Корона шипов у элиты и боссов.
static func _add_crown(root: Node3D, height: float, scale_factor: float, tint: Color) -> void:
	for i: int in 4:
		var angle := TAU * float(i) / 4.0
		var spike := _attach(root, _prism(Vector3(0.12, 0.42, 0.12) * scale_factor),
			Vector3(sin(angle) * 0.22 * scale_factor, height,
				cos(angle) * 0.22 * scale_factor), tint.lightened(0.45), "", true)
		spike.rotation_degrees = Vector3(cos(angle) * 18.0, 0.0, -sin(angle) * 18.0)

## Факел висит вплотную к отряду, и любой из героев, попав между огнём и сценой,
## закрывает её собственной тенью — подземелье уходит в черноту. Поэтому отряд
## из отбрасывающих тень исключён: стены, столбы и враги тени по-прежнему дают.
static func set_casts_shadow(root: Node3D, casts: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node: Node in _walk(root):
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).cast_shadow = mode

static func _walk(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(_walk(child))
	return found
