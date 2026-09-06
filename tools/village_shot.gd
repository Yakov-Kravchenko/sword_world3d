extends Node
## Снимки деревни для визуальной проверки:
##   godot --path . res://tools/village_shot.tscn

func _ready() -> void:
	GameState.new_profile(&"hald")
	var village: Node3D = (load(SceneRouter.VILLAGE) as PackedScene).instantiate()
	add_child(village)
	await get_tree().process_frame
	# Общий план сверху.
	var overview := Camera3D.new()
	overview.fov = 62.0
	overview.far = 200.0
	overview.position = Vector3(0.0, 46.0, 44.0)
	add_child(overview)
	overview.look_at(Vector3(0.0, 0.0, -6.0), Vector3.UP)
	overview.current = true
	await _shot("user://village_1.png")
	var player: Node3D = village.get("player")
	var camera: Camera3D = village.get("camera")
	camera.current = true
	var views := [
		{"pos": Vector3(22.0, 1.7, 30.0), "yaw": 0.0, "file": "user://view_storage.png"},
		{"pos": Vector3(-26.0, 1.7, 6.0), "yaw": 0.0, "file": "user://view_forge.png"},
		{"pos": Vector3(0.0, 1.7, -20.0), "yaw": 0.0, "file": "user://view_descend.png"},
		{"pos": Vector3(18.0, 1.7, -12.0), "yaw": 0.0, "file": "user://view_chapel.png"},
		{"pos": Vector3(26.0, 1.7, 4.0), "yaw": 0.0, "file": "user://view_shop.png"},
		{"pos": Vector3(-17.0, 1.7, -14.0), "yaw": 0.0, "file": "user://view_training.png"},
	]
	for view: Dictionary in views:
		player.position = view["pos"]
		player.rotation.y = deg_to_rad(float(view["yaw"]))
		await _shot(String(view["file"]))
	get_tree().quit()

func _shot(path: String) -> void:
	for i: int in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("снимок: %s" % ProjectSettings.globalize_path(path))
