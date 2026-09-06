extends SceneTree
## Список клипов и габаритов модели: godot --headless --path . -s tools/anim_list.gd

func _init() -> void:
	for id: String in ["hald", "skeleton_warrior"]:
		var node := ModelLibrary.instantiate("actors", id)
		if node == null:
			print(id, ": нет модели")
			continue
		root.add_child(node)
		var box := ModelLibrary.footprint(node)
		print("--- ", id, "  высота=", box.size.y, " ширина=", box.size.x, " низ=", box.position.y)
		var names: PackedStringArray = []
		for child: Node in node.get_children():
			if child is AnimationPlayer:
				names = (child as AnimationPlayer).get_animation_list()
		print("клипов: ", names.size())
		print(", ".join(names))
	quit()
