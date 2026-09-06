class_name HealthBar3D
extends Node3D
## Полоска здоровья над существом. Плоскость полоски держим параллельно экрану:
## при развороте только по оси Y она под перспективой уезжает наискось тем
## сильнее, чем дальше существо от центра кадра. Билборд самих квадов не годится
## — заливка сдвигается по локальной оси X, а билборд её как раз и подменяет.

const WIDTH := 1.1
const HEIGHT := 0.2
## Цвет рамки под полоской. По нему видно ранг существа ещё до контекстного
## меню: серая — рядовой, оранжевая — страж этажа и вестник, голубая — босс акта.
const FRAME_PLAIN := Color(0.05, 0.05, 0.06, 0.9)
const FRAME_KEEPER := Color(0.92, 0.55, 0.15, 0.95)
const FRAME_BOSS := Color(0.35, 0.72, 0.95, 0.95)

var _fill: MeshInstance3D
var _label: Label3D
var _max_hp: int = 1
var _width: float = WIDTH
var _hp: int = 1

static func create(display_name: String, max_hp: int, width: float = WIDTH,
		frame: Color = FRAME_PLAIN, height: float = HEIGHT) -> HealthBar3D:
	var bar := HealthBar3D.new()
	bar.name = "HealthBar"
	bar._build(width, frame, height)
	bar.setup(display_name, max_hp)
	return bar

func _build(width: float, frame: Color, height: float) -> void:
	_width = width
	# Рамка шире и выше заливки — у крупных рангов она и работает подсветкой.
	var border := maxf(0.06, height * 0.45)
	add_child(_quad(Vector2(width + border, height + border), frame, 0.0))
	_fill = _quad(Vector2(width, height), UIKit.GOOD, 0.01)
	add_child(_fill)
	_label = Label3D.new()
	_label.font_size = 44
	_label.pixel_size = 0.0042
	_label.position = Vector3(0.0, height * 0.5 + 0.28, 0.0)
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
	_fill.position.x = -(1.0 - value) * _width * 0.5
	var mat: StandardMaterial3D = _fill.material_override
	mat.albedo_color = UIKit.hp_color(value)
	_label.text = "%s  %d/%d" % [_label.text.split("  ")[0], _hp, _max_hp]


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	global_rotation = camera.global_rotation
