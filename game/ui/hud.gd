extends Control
## HUD забега: отряд, факел, ресурсы, подсказки и модальные окна.

var service: RunService
var _party_box: VBoxContainer
var _torch_label: Label
var _floor_label: Label
var _resource_label: Label
var _interaction_label: Label
var _notice_log: RichTextLabel
var _modal: Control
var _modal_header: VBoxContainer
var _modal_footer: FlowContainer
var _in_combat: bool = false

func setup(run_service: RunService) -> void:
	service = run_service
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.notice.connect(_on_notice)
	EventBus.torch_state_changed.connect(_on_torch_changed)
	# Панель отряда обязана жить и во время боя: урон приходит через шину событий.
	EventBus.action_resolved.connect(func(_result: ActionResult) -> void: _rebuild_party())
	EventBus.combat_ended.connect(func(_victory: bool) -> void: refresh())
	refresh()

func _build() -> void:
	var top := UIKit.panel(UIKit.BG_SOFT)
	top.position = Vector2(12, 10)
	top.custom_minimum_size = Vector2(430, 0)
	add_child(top)
	var top_box := UIKit.vbox(2)
	top.add_child(top_box)
	_floor_label = UIKit.label("", 16, UIKit.ACCENT)
	_torch_label = UIKit.label("", 13)
	_resource_label = UIKit.label("", 13)
	top_box.add_child(_floor_label)
	top_box.add_child(_torch_label)
	top_box.add_child(_resource_label)

	var party_panel := UIKit.panel(UIKit.BG_SOFT)
	party_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	party_panel.position = Vector2(12, -8)
	party_panel.offset_top = -190
	party_panel.offset_bottom = -12
	party_panel.offset_left = 12
	party_panel.offset_right = 300
	add_child(party_panel)
	_party_box = UIKit.vbox(6)
	party_panel.add_child(_party_box)

	var log_panel := UIKit.panel(UIKit.BG_SOFT)
	log_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	log_panel.offset_left = -430
	log_panel.offset_right = -12
	log_panel.offset_top = -140
	log_panel.offset_bottom = -12
	add_child(log_panel)
	_notice_log = UIKit.rich("", 12)
	_notice_log.custom_minimum_size = Vector2(400, 110)
	log_panel.add_child(_notice_log)

	_interaction_label = UIKit.label("", 16, UIKit.ACCENT)
	_interaction_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_interaction_label.offset_top = -220
	_interaction_label.offset_bottom = -196
	_interaction_label.offset_left = -240
	_interaction_label.offset_right = 240
	_interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_interaction_label)

func refresh() -> void:
	if service == null or service.run == null:
		return
	var run := service.run
	var biome := Database.get_biome(run.current_biome)
	_floor_label.text = "Этаж %d / %d — %s (акт %d)" % [run.floor_index,
		Balance.data.total_floors, biome.display_name if biome else "?",
		run.act(Balance.data)]
	_update_torch()
	var mats: Array[String] = []
	for id: Variant in run.run_materials.keys():
		var res := Database.get_item(StringName(id))
		mats.append("%s %d" % [res.display_name if res else String(id), int(run.run_materials[id])])
	_resource_label.text = "Добыча забега: %d золота" % run.run_gold
	if not mats.is_empty():
		_resource_label.text += " · " + ", ".join(mats)
	_rebuild_party()

func _update_torch() -> void:
	var run := service.run
	if not run.torch_lit:
		_torch_label.text = "Факел погас — темнота: помеха на все атаки (Q — зажечь новый)"
		_torch_label.add_theme_color_override("font_color", UIKit.DANGER)
		return
	var warn := run.torch_ticks_left <= Balance.data.torch_warn_ticks
	_torch_label.text = "Факел: %d тиков%s" % [run.torch_ticks_left,
		"  ⚠ вот-вот погаснет" if warn else ""]
	_torch_label.add_theme_color_override("font_color",
		UIKit.DANGER if warn else UIKit.TEXT)

func _rebuild_party() -> void:
	for child: Node in _party_box.get_children():
		child.queue_free()
	for member: CharacterState in service.run.party:
		var row := UIKit.vbox(1)
		var max_hp := member.max_hp(Balance.data)
		var title := "%s — %s" % [member.data.display_name if member.data else String(member.hero_id),
			("ПАЛ" if member.is_dead_this_run else "%d/%d HP" % [member.hp, max_hp])]
		row.add_child(UIKit.label(title, 13,
			UIKit.DANGER if member.is_dead_this_run else UIKit.TEXT))
		if not member.is_dead_this_run:
			row.add_child(UIKit.bar(member.hp, max_hp,
				UIKit.hp_color(float(member.hp) / maxf(1.0, float(max_hp))), 260))
			if member.spell_slots.size() > 0:
				var slots: Array[String] = []
				for i: int in member.spell_slots.size():
					if member.spell_slots[i] > 0:
						slots.append("%d ур.: %d" % [i + 1, member.spell_slots[i]])
				if not slots.is_empty():
					row.add_child(UIKit.label("Ячейки — " + ", ".join(slots), 11))
		_party_box.add_child(row)

func has_modal() -> bool:
	return _modal != null

func set_interaction(text: String) -> void:
	_interaction_label.text = text

func set_combat(active: bool) -> void:
	_in_combat = active
	_interaction_label.visible = not active

func _on_notice(text: String) -> void:
	_notice_log.append_text(text + "\n")

func _on_torch_changed(_ticks: int) -> void:
	_update_torch()

# --- Модальные окна ---
# Все окна строятся одинаково: заголовок в шапке, пункты в прокручиваемом теле,
# кнопки решения в подвале. Так ни один пункт не оказывается за краем панели.

func _close_modal() -> void:
	if _modal != null:
		_modal.queue_free()
		_modal = null
	_modal_header = null
	_modal_footer = null

func _open_modal(width: float, height: float) -> VBoxContainer:
	_close_modal()
	_modal = UIKit.modal_root()
	add_child(_modal)
	var parts := UIKit.modal_window(_modal, width, height)
	_modal_header = parts["header"]
	_modal_footer = parts["footer"]
	return parts["content"]

## Контекстное меню объекта. Живёт в том же слоте, что и окна, поэтому
## исследование на паузе, пока игрок выбирает.
func open_context_menu(title: String, subtitle: String, options: Array,
		at: Vector2 = Vector2(-1.0, -1.0)) -> void:
	_close_modal()
	_modal = ContextMenu.build(self, title, subtitle, options,
		func() -> void: _close_modal(), at)

## Заголовок окна — в шапке, чтобы он не уезжал вместе с прокруткой.
func _modal_title(text: String, subtitle: String = "") -> void:
	_modal_header.add_child(UIKit.label(text, 22, UIKit.ACCENT))
	if not subtitle.is_empty():
		var line := UIKit.label(subtitle, 12)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_modal_header.add_child(line)

## Кнопки решения — в подвал: они видны всегда, сколько бы ни было пунктов.
func _modal_action(text: String, callback: Callable) -> Button:
	var button := UIKit.button(text, callback)
	button.custom_minimum_size = Vector2(190, 34)
	_modal_footer.add_child(button)
	return button

func toggle_menu() -> void:
	if _modal != null:
		_close_modal()
		return
	_open_modal(460, 300)
	_modal_title("Пауза", "Забег сериализуется целиком: сид, позиции, HP, инвентарь.")
	_modal_action("Продолжить", _close_modal)
	_modal_action("Сохранить и выйти", func() -> void:
		SaveSystem.save_run()
		SaveSystem.save_profile()
		_close_modal()
		SceneRouter.goto_menu())
	_modal_action("Бросить забег", func() -> void:
		_close_modal()
		show_summary(service.wipe()))

func toggle_inventory() -> void:
	if _modal != null:
		_close_modal()
		return
	var box := _open_modal(760, 620)
	_modal_title("Сумки отряда")
	for member: CharacterState in service.run.party:
		var name := member.data.display_name if member.data else String(member.hero_id)
		var carried := member.inventory.total_weight()
		var limit := member.carry_limit(Balance.data)
		box.add_child(UIKit.label("%s — %.1f / %.1f кг%s" % [name, carried, limit,
			"  (перегруз)" if carried > limit else ""], 15, UIKit.ACCENT))
		var equipment: Array[String] = []
		for slot: Variant in member.equipment.keys():
			var item: ItemInstance = member.equipment[slot]
			if item != null:
				equipment.append("%s: %s" % [slot, item.display_name()])
		box.add_child(UIKit.label("Экипировано — "
			+ (", ".join(equipment) if not equipment.is_empty() else "пусто"), 12))
		for item: ItemInstance in member.inventory.items():
			box.add_child(UIKit.label("· %s x%d (%.1f кг)" % [item.display_name(),
				item.quantity, item.weight()], 12))
		box.add_child(UIKit.spacer(Vector2(0, 4)))
	if not service.run.run_items.is_empty():
		box.add_child(UIKit.label("Добыча забега (потеряется при гибели отряда)", 15, UIKit.DANGER))
		for item: ItemInstance in service.run.run_items:
			box.add_child(UIKit.label("· " + item.display_name(), 12))
	_modal_action("Закрыть", _close_modal)

## Выбор благословения на этажах 5, 10, 15, 20.
func show_blessings(run_service: RunService, on_done: Callable) -> void:
	var options := run_service.blessing_options()
	var box := _open_modal(820, 480)
	_modal_title("Благословение глубины",
		"Действует до конца забега. При гибели отряда теряется.")
	var row := UIKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for blessing: BlessingData in options:
		row.add_child(_blessing_card(run_service, blessing, on_done))
	if run_service.run.reroll_available:
		_modal_action("Перебросить (1 раз за забег)", func() -> void:
			run_service.run.reroll_available = false
			show_blessings(run_service, on_done))

func _blessing_card(run_service: RunService, blessing: BlessingData,
		on_done: Callable) -> PanelContainer:
	var card := UIKit.panel(UIKit.BG_SOFT)
	card.custom_minimum_size = Vector2(230, 230)
	var inner := UIKit.vbox(6)
	card.add_child(inner)
	inner.add_child(UIKit.label(blessing.display_name, 16, _rarity_color(blessing.rarity)))
	inner.add_child(UIKit.label(_rarity_name(blessing.rarity), 11, _rarity_color(blessing.rarity)))
	var desc := UIKit.label(blessing.description, 12)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(205, 90)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(desc)
	inner.add_child(UIKit.button("Взять", func() -> void:
		run_service.take_blessing(blessing)
		_close_modal()
		refresh()
		if on_done.is_valid():
			on_done.call()))
	return card

func _rarity_color(rarity: StringName) -> Color:
	match rarity:
		&"rare": return Color(0.45, 0.65, 0.95)
		&"epic": return Color(0.72, 0.45, 0.95)
		&"cursed": return Color(0.9, 0.35, 0.3)
	return UIKit.TEXT

func _rarity_name(rarity: StringName) -> String:
	match rarity:
		&"rare": return "Редкое"
		&"epic": return "Эпическое"
		&"cursed": return "Проклятое"
	return "Обычное"

## Карта развилки перед сегментом: 2–3 карточки биома (04-dungeon.md, раздел 2.2).
func show_biome_fork(run_service: RunService, on_done: Callable) -> void:
	var options := run_service.biome_choices(3)
	if options.size() <= 1:
		if options.size() == 1:
			run_service.choose_biome((options[0] as BiomeData).id)
		if on_done.is_valid():
			on_done.call()
		return
	var box := _open_modal(880, 480)
	_modal_title("Куда спускаться", "Биом не повторяется в забеге, пока не исчерпан пул.")
	var row := UIKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for biome: BiomeData in options:
		row.add_child(_biome_card(run_service, biome, on_done))

func _biome_card(run_service: RunService, biome: BiomeData, on_done: Callable) -> PanelContainer:
	var card := UIKit.panel(UIKit.BG_SOFT)
	card.custom_minimum_size = Vector2(250, 260)
	var inner := UIKit.vbox(6)
	card.add_child(inner)
	inner.add_child(UIKit.label(biome.display_name, 17, biome.floor_color.lightened(0.5)))
	for line: Array in [["Угроза", biome.threat_line, UIKit.DANGER],
			["Награда", biome.reward_line, UIKit.GOOD],
			["Риск", biome.risk_line, UIKit.TEXT]]:
		var text := UIKit.label("%s: %s" % [line[0], line[1]], 12, line[2])
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(225, 46)
		inner.add_child(text)
	inner.add_child(UIKit.button("Сюда", func() -> void:
		run_service.choose_biome(biome.id)
		_close_modal()
		if on_done.is_valid():
			on_done.call()))
	return card

## Врата Возврата: главное решение забега (04-dungeon.md, раздел 2.4).
func show_extraction(run_service: RunService) -> void:
	var run := run_service.run
	var box := _open_modal(760, 470)
	_modal_title("Врата Возврата", "Решение принимается один раз и отменить его нельзя.")
	var mats: Array[String] = []
	for id: Variant in run.run_materials.keys():
		var res := Database.get_item(StringName(id))
		mats.append("%s x%d" % [res.display_name if res else String(id), int(run.run_materials[id])])
	box.add_child(UIKit.label("Накоплено: %d золота, предметов: %d" % [run.run_gold,
		run.run_items.size()], 14))
	box.add_child(UIKit.label("Материалы: " + (", ".join(mats) if not mats.is_empty() else "нет"), 12))
	var hp_line: Array[String] = []
	for member: CharacterState in run.party:
		hp_line.append("%s %d/%d" % [member.data.display_name if member.data else "?",
			member.hp, member.max_hp(Balance.data)])
	box.add_child(UIKit.label("Состояние отряда: " + ", ".join(hp_line), 12))
	box.add_child(UIKit.label("Благословений будет потеряно: %d" % run.blessings.size(), 12))
	_modal_action("Уйти с добычей", func() -> void:
		_close_modal()
		show_summary(run_service.extract()))
	if run.floor_index < Balance.data.total_floors:
		_modal_action("Идти дальше", func() -> void:
			_close_modal()
			run_service.descend()
			if run_service.is_segment_start():
				show_biome_fork(run_service, func() -> void:
					SaveSystem.save_run()
					SceneRouter.goto_dungeon("Спуск на этаж %d…" % run_service.run.floor_index))
				return
			SceneRouter.goto_dungeon("Спуск на этаж %d…" % run_service.run.floor_index))
	else:
		box.add_child(UIKit.label("Дальше пути нет — это дно Разлома.", 12, UIKit.ACCENT))

func show_summary(summary: Dictionary) -> void:
	var box := _open_modal(660, 500)
	var title: String = {"extracted": "Возвращение с добычей", "wiped": "Отряд пал",
		"completed": "Разлом пройден"}.get(String(summary.get("outcome", "")), "Забег окончен")
	_modal_title(title)
	box.add_child(UIKit.label("Глубина: этаж %d" % int(summary.get("floor", 0)), 14))
	box.add_child(UIKit.label("Время: %d мин" % int(float(summary.get("elapsed", 0.0)) / 60.0), 13))
	box.add_child(UIKit.label("Убито врагов: %d" % int(summary.get("kills", 0)), 13))
	box.add_child(UIKit.label("Побеждено боссов: %d" % int(summary.get("bosses", 0)), 13))
	box.add_child(UIKit.label("Лучший удар: %d" % int(summary.get("best_hit", 0)), 13))
	var kept := bool(summary.get("kept", false))
	box.add_child(UIKit.label("Золото забега: %d — %s" % [int(summary.get("gold", 0)),
		"сохранено" if kept else "потеряно"], 14, UIKit.GOOD if kept else UIKit.DANGER))
	box.add_child(UIKit.label("Предметов: %d — %s" % [int(summary.get("items", 0)),
		"на складе" if kept else "потеряны"], 13, UIKit.GOOD if kept else UIKit.DANGER))
	box.add_child(UIKit.label("Снаряжение героев возвращается всегда.", 12))
	_modal_action("В деревню", func() -> void:
		_close_modal()
		SceneRouter.goto_village())
