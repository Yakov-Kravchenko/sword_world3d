extends SceneTree
## Реальные габариты моделей персонажей: узлы добавляются в дерево, иначе у
## скиненных мешей габарит считается неверно.

func _initialize() -> void:
	await process_frame
	for path: String in ["res://assets/models/kenney_characters/character-a.glb",
			"res://assets/models/kenney_graveyard/character-skeleton.glb"]:
		var node: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(node)
		await process_frame
		print("--- %s ---" % path.get_file())
		_dump(node, 0, node)
		node.queue_free()
		await process_frame
	quit(0)

func _dump(node: Node, depth: int, origin: Node3D) -> void:
	var pad := "  ".repeat(depth)
	if node is VisualInstance3D:
		var box: AABB = (node as VisualInstance3D).get_aabb()
		var world := (node as Node3D).global_transform * box
		print("%s%s [%s] локально %.2f мировой %.2f" % [pad, node.name, node.get_class(),
			box.size.y, world.size.y])
	else:
		print("%s%s [%s]" % [pad, node.name, node.get_class()])
	if depth > 3:
		return
	for child: Node in node.get_children():
		_dump(child, depth + 1, origin)
