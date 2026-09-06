extends Node
## Проверка разворота и внешнего вида моделей актёров:
##   godot --path . res://tools/model_probe.tscn
## Камера стоит в +Z — ровно там, где в подземелье висит камера за спиной отряда
## при движении вперёд. На снимке должны быть спины, а не лица.

const IDS: Array[String] = ["hald", "irma", "vern", "mara", "skeleton_warrior",
	"bone_archer", "lich_acolyte", "gravedigger"]

func _ready() -> void:
	var world := Node3D.new()
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, 150.0, 0.0)
	light.light_energy = 1.3
	world.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.18, 0.2, 0.26)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.8)
	e.ambient_light_energy = 0.7
	env.environment = e
	world.add_child(env)
	var x := -float(IDS.size() - 1) * 1.1 / 2.0
	for id: String in IDS:
		var node := ActorModel.build_hero(id, Color(0.7, 0.7, 0.75), StringName(id))
		node.position = Vector3(x, 0.0, 0.0)
		world.add_child(node)
		ActorAnimator.attach(node)
		x += 1.1
	var camera := Camera3D.new()
	camera.fov = 40.0
	camera.position = Vector3(0.0, 1.2, 6.0)
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	camera.current = true
	await _shot("user://probe_back.png")
	camera.position = Vector3(0.0, 1.2, -6.0)
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	await _shot("user://probe_front.png")
	get_tree().quit()

func _shot(path: String) -> void:
	for i: int in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("снимок: ", path)
