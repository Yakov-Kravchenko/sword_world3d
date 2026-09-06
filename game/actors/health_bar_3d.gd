class_name HealthBar3D
extends Node3D
## Полоска здоровья над существом. Разворачивается к камере только по оси Y,
## поэтому остаётся горизонтальной и не «ложится» при наклоне тактической камеры.

const WIDTH := 1.5
const HEIGHT := 0.2

var _fill: MeshInstance3D
var _label: Label3D
var _max_hp: int = 1
var _hp: int = 1

static func create(display_name: String, max_hp: int, width: float = WIDTH) -> HealthBar3D:
	var bar := HealthBar3D.new()
	bar.name = "HealthBar"
	bar._build(width)
	bar.setup(display_name, max_hp)
	return bar

func _build(width: float) -> void:
	add_child(_quad(Vector2(width + 0.06, HEIGHT + 0.05), Color(0.05, 0.05, 0.06, 0.9), 0.0))
	_fill = _quad(Vector2(width, HEIGHT), UIKit.GOOD, 0.01)
	add_child(_fill)
	_label = Label3D.new()
	_label.font_size = 44
	_label.pixel_size = 0.0042
	_label.position = Vector3(0.0, HEIGHT * 0.5 + 0.28, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.modulate = Color(0.92, 0.9, 0.86)
	_label.outline_size = 10
	_label.outline_modulate = Color(0.03, 0.03, 0.04)
	add_child(_label)

func _quad(size: Vector2, color: Color, z: float) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position.z = z
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	return node

func setup(display_name: String, max_hp: int) -> void:
	_max_hp = maxi(1, max_hp)
	_hp = _max_hp
	_label.text = display_name
	_apply()

func set_hp(hp: int) -> void:
	_hp = clampi(hp, 0, _max_hp)
	_apply()

func ratio() -> float:
	return float(_hp) / float(maxi(1, _max_hp))

func _apply() -> void:
	var value := ratio()
	# Полоска убывает справа налево: сдвигаем и сжимаем заливку по локальной оси X.
	_fill.scale.x = maxf(0.001, value)
	_fill.position.x = -(1.0 - value) * WIDTH * 0.5
	var mat: StandardMaterial3D = _fill.material_override
	mat.albedo_color = UIKit.hp_color(value)
	_label.text = "%s  %d/%d" % [_label.text.split("  ")[0], _hp, _max_hp]

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var to_camera := camera.global_position - global_position
	if to_camera.length_squared() < 0.0001:
		return
	global_rotation = Vector3(0.0, atan2(to_camera.x, to_camera.z), 0.0)
