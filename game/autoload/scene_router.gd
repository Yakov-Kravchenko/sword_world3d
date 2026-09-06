extends Node
## Переходы между сценами с экраном загрузки (08-architecture.md, раздел 3).

signal scene_changed(path: String)

const MAIN_MENU := "res://game/scenes/main_menu/main_menu.tscn"
const VILLAGE := "res://game/scenes/village/village.tscn"
const DUNGEON := "res://game/scenes/dungeon/dungeon_run.tscn"

var current_path: String = ""
var _overlay: ColorRect
var _label: Label

func _ready() -> void:
	_build_overlay()

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.color = Color(0.02, 0.02, 0.03, 1.0)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	layer.add_child(_overlay)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.text = "Спуск по лестнице…"
	_overlay.add_child(_label)

func goto(path: String, message: String = "Загрузка…") -> void:
	if path == current_path and get_tree().current_scene != null:
		return
	_label.text = message
	_overlay.visible = true
	current_path = path
	await get_tree().process_frame
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		Log.error("Не удалось загрузить сцену %s (%d)" % [path, err])
	await get_tree().process_frame
	_overlay.visible = false
	scene_changed.emit(path)

func goto_menu() -> void:
	goto(MAIN_MENU, "Главное меню")

func goto_village() -> void:
	goto(VILLAGE, "Возвращение в деревню…")

func goto_dungeon(message: String = "Спуск по лестнице…") -> void:
	goto(DUNGEON, message)
