extends Node
## Диагностика раскладки окон: печатает реальные прямоугольники и якоря.

func _ready() -> void:
	GameState.new_profile(&"hald")
	var village: Node = (load(SceneRouter.VILLAGE) as PackedScene).instantiate()
	add_child(village)
	await get_tree().process_frame
	var ui: Control = village.get("ui")
	print("viewport: %s" % get_viewport().get_visible_rect())
	_line("ui", ui)
	print("родитель ui: %s [%s]" % [ui.get_parent().name, ui.get_parent().get_class()])
	ui.call("open_station", &"garden")
	await get_tree().process_frame
	await get_tree().process_frame
	var modal: Control = ui.get("_modal")
	_line("modal root", modal)
	_line("panel", modal.get_child(1))
	_tree(modal.get_child(1), 1)
	get_tree().quit()

func _line(label: String, c: Control) -> void:
	if c == null:
		print("%s: null" % label)
		return
	print("%s: rect=%s min=%s anchors=(%.2f,%.2f,%.2f,%.2f) offsets=(%.0f,%.0f,%.0f,%.0f)" % [
		label, c.get_global_rect(), c.get_combined_minimum_size(),
		c.anchor_left, c.anchor_top, c.anchor_right, c.anchor_bottom,
		c.offset_left, c.offset_top, c.offset_right, c.offset_bottom])

func _tree(node: Node, depth: int) -> void:
	if depth > 5:
		return
	for child: Node in node.get_children():
		if child is Control:
			var c: Control = child
			print("%s%s [%s] rect=%s" % ["  ".repeat(depth), c.name, c.get_class(),
				c.get_global_rect()])
		_tree(child, depth + 1)
