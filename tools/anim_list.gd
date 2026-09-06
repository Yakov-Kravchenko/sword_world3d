extends SceneTree
## Габариты и список клипов моделей:
##   godot --headless --path . -s tools/anim_list.gd

const TARGETS := {"actors": ["hald", "skeleton_warrior"],
	"props": ["chest_common", "chest_treasure"]}

func _init() -> void:
	for category: String in TARGETS.keys():
		for id: String in TARGETS[category]:
			var node := ModelLibrary.build(category, id)
			if node == null:
				print(id, ": нет модели")
				continue
			root.add_child(node)
			var box := ModelLibrary.footprint(node)
			print("%-16s ширина=%.2f высота=%.2f глубина=%.2f низ=%.2f" % [id,
				box.size.x, box.size.y, box.size.z, box.position.y])
			var names: PackedStringArray = []
			for child: Node in node.get_children():
				for sub: Node in child.get_children():
					if sub is AnimationPlayer:
						names = (sub as AnimationPlayer).get_animation_list()
			if not names.is_empty():
				print("   клипов: ", names.size(), " — ", ", ".join(names).substr(0, 120))
	quit()
