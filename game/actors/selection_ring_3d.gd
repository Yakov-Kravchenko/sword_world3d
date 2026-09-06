class_name SelectionRing3D
extends Node3D
## Круг под ногами существа. Синий — персонаж игрока, зелёный — тот, чей сейчас
## ход. Лежит на полу чуть выше него, чтобы не мерцать с плитой.

const PARTY := Color(0.36, 0.62, 0.95)
const ACTIVE := Color(0.36, 0.85, 0.42)
const RADIUS := 0.52
const THICKNESS := 0.11
const LIFT := 0.05

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _color: Color = PARTY
var _active: bool = false
var _phase: float = 0.0

static func create(color: Color = PARTY) -> SelectionRing3D:
	var ring := SelectionRing3D.new()
	ring.name = "SelectionRing"
	ring._build()
	ring.set_color(color)
	return ring

func _build() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = RADIUS - THICKNESS
	mesh.outer_radius = RADIUS
	mesh.rings = 24
	mesh.ring_segments = 6
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.position.y = LIFT
	# Круг — подсказка игроку, а не часть сцены: тени от него не нужны.
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_mesh.material_override = _material
	add_child(_mesh)

func set_color(color: Color) -> void:
	_color = color
	_apply()

## Ход существа: круг зеленеет и начинает пульсировать.
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	_phase = 0.0
	if not active:
		_mesh.scale = Vector3.ONE
	_apply()

func is_active() -> bool:
	return _active

func _apply() -> void:
	var color := ACTIVE if _active else _color
	_material.albedo_color = Color(color.r, color.g, color.b, 0.85 if _active else 0.5)
	_material.emission = color
	_material.emission_energy_multiplier = 1.6 if _active else 0.6

func _process(delta: float) -> void:
	if not _active:
		return
	_phase += delta * 3.0
	var wave := 0.5 + 0.5 * sin(_phase)
	_mesh.scale = Vector3.ONE * (1.0 + 0.06 * wave)
	_material.emission_energy_multiplier = 1.2 + 0.9 * wave
