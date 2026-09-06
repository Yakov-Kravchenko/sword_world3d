extends Node
## Снимок сцены боя для визуальной проверки:
##   godot --path . res://tools/screenshot.tscn
## Кладёт PNG в user://shot.png. Только инструмент разработчика.

func _ready() -> void:
	GameState.new_profile(&"hald")
	var dungeon: Node = (load(SceneRouter.DUNGEON) as PackedScene).instantiate()
	add_child(dungeon)
	await get_tree().process_frame
	var plan: FloorPlan = dungeon.get("plan")
	if plan.encounters.is_empty():
		get_tree().quit(1)
		return
	# Сначала кадр исследования с миникартой: отмечаем часть комнат пройденными.
	var service: RunService = dungeon.get("service")
	for i: int in mini(4, plan.rooms.size()):
		service.run.visited_rooms.append(plan.rooms[i].index)
	if not plan.encounters.is_empty():
		service.run.cleared_rooms.append(int(plan.encounters[0]["room"]))
		service.run.visited_rooms.append(int(plan.encounters[0]["room"]))
	dungeon.get("minimap").call("set_party_cell", plan.entrance_cell)
	dungeon.get("minimap").call("refresh")
	for i: int in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://map_1.png")
	print("снимок: %s" % ProjectSettings.globalize_path("user://map_1.png"))
	dungeon.get("minimap").call("toggle")
	for i: int in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://map_2.png")
	print("снимок: %s" % ProjectSettings.globalize_path("user://map_2.png"))
	dungeon.get("minimap").call("toggle")
	var encounter: Dictionary = plan.encounters[0]
	dungeon.call("_start_combat", encounter, plan.rooms[int(encounter["room"])])
	for shot: int in 2:
		for i: int in (90 if shot == 0 else 160):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "user://shot_%d.png" % (shot + 1)
		get_viewport().get_texture().get_image().save_png(path)
		print("снимок: %s" % ProjectSettings.globalize_path(path))
	get_tree().quit()
