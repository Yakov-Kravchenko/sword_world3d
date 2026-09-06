extends Node
## Точка входа: ждём готовности автозагрузок и уходим в главное меню.

func _ready() -> void:
	Log.info("Godot %s, рендерер %s" % [Engine.get_version_info()["string"],
		ProjectSettings.get_setting("rendering/renderer/rendering_method")])
	var errors := Database.errors()
	if not errors.is_empty():
		Log.error("Контент загружен с ошибками (%d) — проверьте tools/validate_data.gd" % errors.size())
	await get_tree().process_frame
	SceneRouter.goto_menu()
