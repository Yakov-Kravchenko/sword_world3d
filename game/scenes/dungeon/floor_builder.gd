class_name FloorBuilder
extends Node3D
## Материализует FloorPlan в ноды: пол и стены через MultiMesh (один вызов отрисовки
## на слой), пропсы отдельными мешами (08-architecture.md, раздел 8.2).

const WALL_HEIGHT := 3.0

var cell_size: float = 1.5
var plan: FloorPlan
var biome: BiomeData

var _floor_mm: MultiMeshInstance3D
var _wall_mm: MultiMeshInstance3D
var _props := {}   # индекс пропа -> Node3D

static func cell_to_world(cell: Vector2i, size: float, y: float = 0.0) -> Vector3:
	return Vector3(cell.x * size, y, cell.y * size)

static func world_to_cell(pos: Vector3, size: float) -> Vector2i:
	return Vector2i(int(round(pos.x / size)), int(round(pos.z / size)))

func build(floor_plan: FloorPlan, biome_data: BiomeData, size: float) -> void:
	plan = floor_plan
	biome = biome_data
	cell_size = size
	_clear()
	_build_floor()
	_build_walls()
	_build_props()

func _clear() -> void:
	for child: Node in get_children():
		child.queue_free()
	_props.clear()

func _material(color: Color, rough: float = 0.95) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = 0.0
	# Нормал-мапы и металл не используем: экономия VRAM и времени художника.
	return mat

func _build_floor() -> void:
	var cells: Array[Vector2i] = []
	for y: int in plan.height:
		for x: int in plan.width:
			var c := Vector2i(x, y)
			if plan.is_floor(c):
				cells.append(c)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cell_size, 0.2, cell_size)
	_floor_mm = _make_multimesh(mesh, _material(biome.floor_color), cells, -0.1)
	add_child(_floor_mm)

func _build_walls() -> void:
	var cells: Array[Vector2i] = []
	for y: int in plan.height:
		for x: int in plan.width:
			var c := Vector2i(x, y)
			if plan.is_floor(c):
				continue
			if _touches_floor(c):
				cells.append(c)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cell_size, WALL_HEIGHT, cell_size)
	_wall_mm = _make_multimesh(mesh, _material(biome.wall_color), cells, WALL_HEIGHT * 0.5)
	add_child(_wall_mm)

func _touches_floor(cell: Vector2i) -> bool:
	for dy: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if plan.is_floor(cell + Vector2i(dx, dy)):
				return true
	return false

func _make_multimesh(mesh: Mesh, material: Material, cells: Array[Vector2i],
		y: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = cells.size()
	for i: int in cells.size():
		mm.set_instance_transform(i, Transform3D(Basis(), cell_to_world(cells[i], cell_size, y)))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	return node

func _build_props() -> void:
	var stairs := _prop_mesh(Vector3(cell_size, 0.4, cell_size), Color(0.85, 0.75, 0.35))
	stairs.position = cell_to_world(plan.exit_cell, cell_size, 0.2)
	stairs.name = "StairsDown"
	add_child(stairs)
	for i: int in plan.props.size():
		var prop: Dictionary = plan.props[i]
		var cell: Vector2i = prop["cell"]
		var node: Node3D = null
		match StringName(prop["kind"]):
			&"chest":
				node = _prop_mesh(Vector3(0.9, 0.6, 0.6), Color(0.55, 0.38, 0.2))
			&"altar":
				node = _prop_mesh(Vector3(1.0, 1.0, 1.0), Color(0.5, 0.65, 0.75))
			&"gate":
				node = _prop_mesh(Vector3(1.4, 2.4, 0.4), Color(0.75, 0.65, 0.3))
			&"event":
				node = _prop_mesh(Vector3(0.7, 1.2, 0.7), Color(0.6, 0.5, 0.7))
			&"trap":
				node = _prop_mesh(Vector3(cell_size * 0.8, 0.05, cell_size * 0.8),
					Color(0.35, 0.3, 0.28))
		if node == null:
			continue
		node.position = cell_to_world(cell, cell_size, 0.3)
		node.set_meta("prop_index", i)
		node.name = "Prop%d" % i
		add_child(node)
		_props[i] = node
	for cell: Vector2i in plan.static_lights:
		var light := OmniLight3D.new()
		light.position = cell_to_world(cell, cell_size, 2.0)
		light.light_color = Color(0.9, 0.7, 0.45)
		light.light_energy = 1.2
		light.omni_range = 9.0
		light.shadow_enabled = false  # тени только у факела: 1 источник теней в кадре
		add_child(light)

func _prop_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color, 0.8)
	return node

func hide_prop(index: int) -> void:
	if _props.has(index):
		(_props[index] as Node3D).visible = false

func prop_node(index: int) -> Node3D:
	return _props.get(index, null)
