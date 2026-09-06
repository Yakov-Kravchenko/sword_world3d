class_name ContextMenu
extends RefCounted
## Контекстное меню объекта: список действий, из которых игрок выбирает сам.
## Пункт описывается словарём:
##   {"label": String, "hint": String, "enabled": bool, "callback": Callable}
## Недоступный пункт не прячется, а показывается с причиной — так игрок видит,
## что действие существует и чего ему не хватает.

const WIDTH := 380.0
const OPTION_HEIGHT := 34.0
const HINT_HEIGHT := 16.0

static func option(label: String, callback: Callable, hint: String = "",
		enabled: bool = true) -> Dictionary:
	return {"label": label, "hint": hint, "enabled": enabled, "callback": callback}

## Строит меню внутри host и возвращает корень, чтобы вызывающий мог его закрыть.
static func build(host: Control, title: String, subtitle: String, options: Array,
		close_callback: Callable, at: Vector2 = Vector2(-1.0, -1.0)) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	host.add_child(root)

	var panel := UIKit.panel(UIKit.BG)
	panel.custom_minimum_size = Vector2(WIDTH, 0.0)
	root.add_child(panel)
	var box := UIKit.vbox(6)
	panel.add_child(box)
	box.add_child(UIKit.label(title, 18, UIKit.ACCENT))
	if not subtitle.is_empty():
		var sub := UIKit.label(subtitle, 12)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size = Vector2(WIDTH - 24.0, 0.0)
		box.add_child(sub)
	for entry: Dictionary in options:
		_add_option(box, entry, close_callback)
	box.add_child(UIKit.button("Отмена", func() -> void: close_callback.call(), 13))
	_place(panel, host, _estimated_height(subtitle, options), at)
	return root

static func _add_option(box: VBoxContainer, entry: Dictionary, close_callback: Callable) -> void:
	var enabled := bool(entry.get("enabled", true))
	var callback: Callable = entry.get("callback", Callable())
	var button := UIKit.button(String(entry.get("label", "?")), func() -> void:
		# Меню закрывается до действия: пункт может открыть следующее окно.
		close_callback.call()
		if callback.is_valid():
			callback.call(), 14)
	button.disabled = not enabled
	var hint := String(entry.get("hint", ""))
	button.tooltip_text = hint
	box.add_child(button)
	if not hint.is_empty():
		var line := UIKit.label(hint, 11, UIKit.TEXT if enabled else UIKit.DANGER)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(WIDTH - 24.0, 0.0)
		box.add_child(line)

static func _estimated_height(subtitle: String, options: Array) -> float:
	var height := 34.0 + (22.0 if not subtitle.is_empty() else 0.0) + 40.0
	for entry: Dictionary in options:
		height += OPTION_HEIGHT
		if not String(entry.get("hint", "")).is_empty():
			height += HINT_HEIGHT
	return height

## Меню появляется у курсора, но целиком помещается на экране.
static func _place(panel: Control, host: Control, height: float, at: Vector2) -> void:
	var screen := host.get_viewport_rect().size
	var target := at
	if target.x < 0.0:
		target = (screen - Vector2(WIDTH, height)) * 0.5
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(
		clampf(target.x, 8.0, maxf(8.0, screen.x - WIDTH - 8.0)),
		clampf(target.y, 8.0, maxf(8.0, screen.y - height - 8.0)))
