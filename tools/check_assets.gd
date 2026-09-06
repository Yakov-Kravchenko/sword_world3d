extends SceneTree
## Что из моделей уже подключено, а что строится процедурно:
##   godot --headless --path . --script res://tools/check_assets.gd

func _initialize() -> void:
	print("===== Модели =====")
	var found := 0
	var total := 0
	for category: String in ModelLibrary.expected().keys():
		print("%s:" % category)
		for model_name: String in ModelLibrary.expected()[category]:
			total += 1
			var path := ModelLibrary.find(category, model_name)
			if path.is_empty():
				print("  процедурно  %s" % model_name)
			else:
				found += 1
				print("  модель      %-16s %s" % [model_name, path])
	print("------------------")
	print("Готовых моделей: %d из %d. Остальное строится примитивами." % [found, total])
	print("Куда класть файлы — assets/models/README.md")
	print("==================")
	quit(0)
