extends Control
## Главное меню и выбор основного героя.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_main()

func _clear() -> void:
	for child: Node in get_children():
		if child is ColorRect:
			continue
		child.queue_free()

func _build_main() -> void:
	_clear()
	var box := UIKit.vbox(10)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -220
	box.offset_right = 220
	box.offset_top = -200
	box.offset_bottom = 200
	add_child(box)
	box.add_child(UIKit.label("SWORD WORLD 3D", 34, UIKit.ACCENT))
	box.add_child(UIKit.label("Пошаговый рогалик: 20 этажей вниз и дом наверху.", 14))
	box.add_child(UIKit.spacer(Vector2(0, 20)))
	if SaveSystem.has_profile_file():
		box.add_child(UIKit.button("Продолжить", func() -> void:
			if SaveSystem.load_profile():
				if SaveSystem.has_run_file():
					_ask_resume_run()
				else:
					SceneRouter.goto_village()))
	box.add_child(UIKit.button("Новая игра", _build_hero_select))
	box.add_child(UIKit.button("Выход", func() -> void: get_tree().quit()))
	box.add_child(UIKit.spacer(Vector2(0, 20)))
	box.add_child(UIKit.label("Управление: WSAD — движение, E — взаимодействие, I — сумки,\n"
		+ "ЛКМ — действие в бою, пробел — конец хода, СКМ — поворот камеры.", 12))

func _ask_resume_run() -> void:
	_clear()
	var box := UIKit.vbox(10)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -260
	box.offset_right = 260
	add_child(box)
	box.add_child(UIKit.label("Найден незавершённый забег", 22, UIKit.ACCENT))
	box.add_child(UIKit.label("Загрузка удалит файл забега — это защита от перезагрузок.", 12))
	box.add_child(UIKit.button("Продолжить забег", func() -> void:
		if SaveSystem.load_run():
			SceneRouter.goto_dungeon("Возвращение в подземелье…")
		else:
			SceneRouter.goto_village()))
	box.add_child(UIKit.button("В деревню (забег будет брошен)", func() -> void:
		SaveSystem.delete_run()
		SceneRouter.goto_village()))

func _build_hero_select() -> void:
	_clear()
	var box := UIKit.vbox(10)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 60
	box.offset_right = -60
	box.offset_top = 60
	box.offset_bottom = -60
	add_child(box)
	box.add_child(UIKit.label("Кто из четверых — ваш?", 26, UIKit.ACCENT))
	box.add_child(UIKit.label("Его дом станет хабом, за него вы будете говорить в деревне "
		+ "и получите +1 к профильной характеристике. В подземелье вы ведёте всех четверых.", 13))
	var row := UIKit.hbox(12)
	box.add_child(row)
	for hero: HeroData in Database.of_class("HeroData"):
		var card := UIKit.panel(UIKit.BG_SOFT)
		card.custom_minimum_size = Vector2(300, 380)
		var inner := UIKit.vbox(6)
		card.add_child(inner)
		inner.add_child(UIKit.label(hero.display_name, 18, hero.tint))
		inner.add_child(UIKit.label(hero.archetype, 14, UIKit.ACCENT))
		var role := UIKit.label(hero.role, 12)
		role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		role.custom_minimum_size = Vector2(270, 40)
		inner.add_child(role)
		var stats: Array[String] = []
		for key: StringName in Stats.ALL:
			stats.append("%s %d" % [Stats.RU[key], int(hero.base_stats.get(key, 10))])
		inner.add_child(UIKit.label(", ".join(stats), 12))
		inner.add_child(UIKit.label("Кость HP: d%d · Профиль: %s" % [hero.hit_die,
			Stats.RU.get(hero.primary_stat, "?")], 12))
		var house := UIKit.label(hero.house_description, 12)
		house.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		house.custom_minimum_size = Vector2(270, 60)
		inner.add_child(house)
		inner.add_child(UIKit.button("Играть за него", func() -> void:
			GameState.new_profile(hero.id)
			SaveSystem.save_profile()
			SceneRouter.goto_village()))
		row.add_child(card)
	box.add_child(UIKit.button("Назад", _build_main))
