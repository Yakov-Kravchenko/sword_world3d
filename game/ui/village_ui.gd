extends Control
## Интерфейс деревни: кузница, тренировочный зал, лавка, сад, склад, спуск.

var village: Node3D
var _prompt: Label
var _header: Label
var _modal: Control
var _shop_stock: Array = []
var _modal_footer: FlowContainer

func setup(scene: Node3D) -> void:
	village = scene
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UIKit.panel(UIKit.BG_SOFT)
	top.position = Vector2(12, 10)
	add_child(top)
	_header = UIKit.label("", 14)
	top.add_child(_header)
	_prompt = UIKit.label("", 18, UIKit.ACCENT)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -120
	_prompt.offset_bottom = -96
	_prompt.offset_left = -260
	_prompt.offset_right = 260
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt)
	EventBus.notice.connect(func(text: String) -> void: _prompt.text = text)
	refresh_header()

func refresh_header() -> void:
	var p := GameState.profile
	var mats: Array[String] = []
	for id: Variant in p.materials.keys():
		if int(p.materials[id]) <= 0:
			continue
		var res := Database.get_item(StringName(id))
		mats.append("%s %d" % [res.display_name if res else String(id), int(p.materials[id])])
	_header.text = "День %d · Уровень отряда %d · Золото %d%s" % [p.day, p.party_level, p.gold,
		("  ·  " + ", ".join(mats)) if not mats.is_empty() else ""]

func set_prompt(text: String) -> void:
	if _modal == null:
		_prompt.text = text

func has_modal() -> bool:
	return _modal != null

func close_modal() -> void:
	if _modal != null:
		_modal.queue_free()
		_modal = null
	_modal_footer = null
	refresh_header()

## Окно постройки: заголовок в шапке, пункты в прокручиваемом теле, кнопки в подвале.
func _panel(width: float, height: float, title: String) -> VBoxContainer:
	close_modal()
	_modal = UIKit.modal_root()
	add_child(_modal)
	var parts := UIKit.modal_window(_modal, width, height)
	_modal_footer = parts["footer"]
	(parts["header"] as VBoxContainer).add_child(UIKit.label(title, 22, UIKit.ACCENT))
	return parts["content"]

## Кнопка решения — в подвал, она видна при любом числе пунктов в списке.
func _action(text: String, callback: Callable) -> Button:
	var button := UIKit.button(text, callback)
	button.custom_minimum_size = Vector2(190, 34)
	_modal_footer.add_child(button)
	return button

func _footer(_box: VBoxContainer = null) -> void:
	_action("Закрыть", func() -> void:
		close_modal()
		village.resume_look())

func open_station(id: StringName) -> void:
	match id:
		&"forge": _open_forge()
		&"altar": _open_altar()
		&"training": _open_training()
		&"shop": _open_shop()
		&"garden": _open_garden()
		&"storage": _open_storage()
		&"descend": _open_descend()

# --- Кузница: улучшение +1...+8 ---

func _open_forge() -> void:
	var box := _panel(820, 560, "Кузница")
	box.add_child(UIKit.label("Улучшение снаряжения до +%d. Стоимость и шанс растут с уровнем."
		% Balance.data.upgrade_max_level, 12))
	var list := box
	for member: CharacterState in GameState.profile.party:
		list.add_child(UIKit.label(member.data.display_name if member.data else String(member.hero_id),
			15, UIKit.ACCENT))
		for slot: Variant in member.equipment.keys():
			var item: ItemInstance = member.equipment[slot]
			if item == null or not item.data.is_equipment():
				continue
			list.add_child(_forge_row(item))
	_footer(box)

func _forge_row(item: ItemInstance) -> HBoxContainer:
	var row := UIKit.hbox(8)
	if item.upgrade_level >= Balance.data.upgrade_max_level:
		row.add_child(UIKit.row_label("%s — максимум" % item.display_name(), 13, UIKit.GOOD))
		return row
	var cost := GameState.item_factory.upgrade_cost(item)
	var chance := GameState.item_factory.upgrade_chance(int(cost["level"]))
	var ore := Database.get_item(StringName(cost["ore_id"]))
	row.add_child(UIKit.row_label("%s   —   %d зол. + %s x%d, шанс %d%%" % [item.display_name(),
		int(cost["gold"]), ore.display_name if ore else String(cost["ore_id"]),
		int(cost["ore"]), int(round(chance * 100.0))], 13))
	row.add_child(UIKit.row_button("Улучшить", func() -> void: _do_upgrade(item), 12, 120.0))
	return row

func _do_upgrade(item: ItemInstance) -> void:
	var cost := GameState.item_factory.upgrade_cost(item)
	var profile := GameState.profile
	var materials := {StringName(cost["ore_id"]): int(cost["ore"])}
	var result := profile.spend(int(cost["gold"]), materials)
	if not result.ok:
		EventBus.notify(result.error)
		return
	var rng := RngStream.new(RngStream.hash_combine(profile.profile_seed,
		"upgrade_%d_%d" % [profile.day, item.uid]), &"upgrade")
	var chance := GameState.item_factory.upgrade_chance(int(cost["level"]))
	var success := rng.randf_value() <= chance
	if success:
		item.upgrade_level += 1
		EventBus.notify("%s улучшен до +%d" % [item.data.display_name, item.upgrade_level])
	else:
		EventBus.notify("Улучшение сорвалось: ресурсы потрачены, предмет цел")
	EventBus.upgrade_attempted.emit(item, success)
	SaveSystem.save_profile()
	_open_forge()

# --- Тренировочный зал: уровень отряда и деревья навыков ---

func _open_training() -> void:
	var profile := GameState.profile
	var box := _panel(880, 620, "Тренировочный зал")
	var next_level := profile.party_level + 1
	if next_level <= Balance.data.max_party_level:
		var idx := next_level - 2
		var price: int = Balance.data.level_costs[idx] if idx < Balance.data.level_costs.size() else 0
		var requirement: String = String(Balance.data.level_requirements[idx]) \
			if idx < Balance.data.level_requirements.size() else ""
		var met := profile.level_requirement_met(next_level, Balance.data)
		box.add_child(UIKit.label("Уровень %d -> %d: %d золота. Требование: %s (%s)" % [
			profile.party_level, next_level, price, requirement,
			"выполнено" if met else "не выполнено"], 13, UIKit.GOOD if met else UIKit.DANGER))
		var button := UIKit.button("Повысить уровень отряда", func() -> void: _level_up(price))
		button.disabled = not met or profile.gold < price
		box.add_child(button)
	else:
		box.add_child(UIKit.label("Достигнут потолок релиза: уровень %d. Уровни 10-12 придут с обновлением."
			% Balance.data.max_party_level, 13))
	box.add_child(UIKit.spacer())
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 430)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	for member: CharacterState in profile.party:
		tabs.add_child(_skill_tab(member))
	_footer(box)

func _level_up(price: int) -> void:
	var profile := GameState.profile
	if not profile.spend(price).ok:
		EventBus.notify("Не хватает золота")
		return
	profile.party_level += 1
	for member: CharacterState in profile.party:
		member.level = profile.party_level
		member.skill_points += 2
		member.restore_full(Balance.data)
	EventBus.notify("Отряд достиг уровня %d. Каждому герою +2 очка навыков." % profile.party_level)
	SaveSystem.save_profile()
	_open_training()

## Вкладка дерева строится из данных: число рядов и веток не зашито в вёрстку.
func _skill_tab(member: CharacterState) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = member.data.display_name if member.data else String(member.hero_id)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UIKit.vbox(4)
	scroll.add_child(list)
	list.add_child(UIKit.label("Очки навыков: %d" % member.skill_points, 14, UIKit.ACCENT))
	var current_branch: StringName = &""
	for node: SkillNodeData in GameState.skill_tree.nodes_for(member.hero_id):
		if node.branch != current_branch:
			current_branch = node.branch
			list.add_child(UIKit.label("Ветка: %s" % ("ствол" if current_branch == &"trunk"
				else String(current_branch).to_upper()), 13, UIKit.ACCENT))
		list.add_child(_skill_row(member, node))
	list.add_child(UIKit.spacer())
	list.add_child(UIKit.button("Сбросить дерево (штраф 30%)", func() -> void:
		var refund := GameState.skill_tree.respec(member)
		GameState.profile.add_gold(refund)
		EventBus.notify("Дерево сброшено, возвращено %d золота" % refund)
		SaveSystem.save_profile()
		_open_training(), 12))
	return scroll

func _skill_row(member: CharacterState, node: SkillNodeData) -> HBoxContainer:
	var row := UIKit.hbox(8)
	var owned := member.unlocked_nodes.has(node.id)
	var price := GameState.skill_tree.price(node)
	row.add_child(UIKit.row_label("Ряд %d · %s — %s" % [node.row, node.display_name, node.description],
		12, UIKit.GOOD if owned else UIKit.TEXT))
	if owned:
		row.add_child(UIKit.row_label("открыт", 12, UIKit.GOOD))
		return row
	var check := GameState.skill_tree.can_unlock(node, member, GameState.profile.gold)
	var button := UIKit.row_button("%d зол. · %d очк." % [price, node.skill_points], func() -> void:
		_unlock_node(member, node), 12, 150.0)
	button.disabled = not check.ok
	button.tooltip_text = check.error
	row.add_child(button)
	return row

func _unlock_node(member: CharacterState, node: SkillNodeData) -> void:
	var check := GameState.skill_tree.can_unlock(node, member, GameState.profile.gold)
	if not check.ok:
		EventBus.notify(check.error)
		return
	GameState.profile.add_gold(-int(check.value))
	GameState.skill_tree.unlock(node, member)
	EventBus.notify("Открыт узел «%s»" % node.display_name)
	SaveSystem.save_profile()
	_open_training()

# --- Лавка ---

func _open_shop() -> void:
	var profile := GameState.profile
	if _shop_stock.is_empty():
		var generator := ShopGenerator.new(GameState.item_factory)
		_shop_stock = generator.generate(profile.profile_seed, profile.day,
			int(profile.building_levels.get("shop", 1)),
			int(profile.stats.get("deepest_floor", 1)))
	var main := profile.member(profile.main_hero_id)
	var charisma: int = main.stat_mod(Stats.CHA) if main != null else 0
	var box := _panel(860, 600, "Лавка")
	box.add_child(UIKit.label("Ассортимент меняется каждый день. ХАР %s влияет на цены (%+d)."
		% [main.data.display_name if main and main.data else "героя", charisma], 12))
	var list := box
	list.add_child(UIKit.label("Купить", 15, UIKit.ACCENT))
	for item: ItemInstance in _shop_stock:
		list.add_child(_shop_buy_row(item, charisma))
	list.add_child(UIKit.spacer())
	list.add_child(UIKit.label("Продать со склада", 15, UIKit.ACCENT))
	for item: ItemInstance in profile.storage:
		list.add_child(_shop_sell_row(item, charisma))
	_footer(box)

func _shop_buy_row(item: ItemInstance, charisma: int) -> HBoxContainer:
	var row := UIKit.hbox(8)
	var price := Prices.buy_price(item, charisma)
	row.add_child(UIKit.row_label("%s x%d   —   %d зол." % [item.display_name(),
		item.quantity, price], 12))
	var button := UIKit.row_button("Купить", func() -> void: _buy(item, price), 12, 110.0)
	button.disabled = GameState.profile.gold < price
	row.add_child(button)
	return row

func _buy(item: ItemInstance, price: int) -> void:
	if not GameState.profile.spend(price).ok:
		EventBus.notify("Не хватает золота")
		return
	GameState.profile.storage.append(item)
	_shop_stock.erase(item)
	EventBus.notify("Куплено: %s" % item.display_name())
	SaveSystem.save_profile()
	_open_shop()

func _shop_sell_row(item: ItemInstance, charisma: int) -> HBoxContainer:
	var row := UIKit.hbox(8)
	var price := Prices.sell_price(item, charisma)
	row.add_child(UIKit.row_label("%s x%d" % [item.display_name(), item.quantity], 12))
	row.add_child(UIKit.row_button("Продать за %d" % price, func() -> void:
		GameState.profile.storage.erase(item)
		GameState.profile.add_gold(price)
		EventBus.notify("Продано: %s" % item.display_name())
		SaveSystem.save_profile()
		_open_shop(), 12, 150.0))
	return row

# --- Сад ---

func _open_garden() -> void:
	var profile := GameState.profile
	var box := _panel(620, 380, "Сад")
	var level := int(profile.building_levels.get("garden", 1))
	box.add_child(UIKit.label("Уровень сада: %d. Каждый день грядки дают травы." % level, 13))
	box.add_child(UIKit.button("Собрать урожай (раз в день)", func() -> void:
		var rng := RngStream.new(RngStream.hash_combine(profile.profile_seed,
			"garden_%d" % profile.day), &"garden")
		if int(profile.stats.get("last_harvest_day", -1)) == profile.day:
			EventBus.notify("Сегодня грядки уже собраны")
			return
		profile.stats["last_harvest_day"] = profile.day
		var count := rng.randi_range(1, 1 + level)
		var potion := GameState.item_factory.create(&"potion_minor", count)
		if potion != null:
			profile.storage.append(potion)
		EventBus.notify("Собрано зелий: %d" % count)
		SaveSystem.save_profile()
		_open_garden()))
	var upgrade_cost := 500 * level
	var upgrade := UIKit.button("Улучшить сад (%d зол.)" % upgrade_cost, func() -> void:
		if profile.spend(upgrade_cost).ok:
			profile.building_levels["garden"] = level + 1
			EventBus.notify("Сад улучшен до уровня %d" % (level + 1))
			SaveSystem.save_profile()
			_open_garden())
	upgrade.disabled = profile.gold < upgrade_cost
	box.add_child(upgrade)
	_footer(box)

# --- Склад: раздача снаряжения героям ---

func _open_storage() -> void:
	var profile := GameState.profile
	var box := _panel(880, 620, "Склад")
	box.add_child(UIKit.label("Содержимое склада сохраняется всегда, даже при гибели отряда.", 12))
	var list := box
	if profile.storage.is_empty():
		list.add_child(UIKit.label("Пусто.", 13))
	for item: ItemInstance in profile.storage.duplicate():
		list.add_child(_storage_row(item))
	_footer(box)

func _storage_row(item: ItemInstance) -> HBoxContainer:
	var row := UIKit.hbox(6)
	row.add_child(UIKit.row_label("%s x%d" % [item.display_name(), item.quantity], 12))
	for member: CharacterState in GameState.profile.party:
		var name := member.data.display_name.split(" ")[0] if member.data else String(member.hero_id)
		row.add_child(UIKit.row_button(name, func() -> void: _give(item, member), 11, 96.0))
	return row

func _give(item: ItemInstance, member: CharacterState) -> void:
	if item.data.is_equipment():
		var slot: StringName = (item.data as WeaponData).slot if item.data is WeaponData \
			else (item.data as ArmorData).slot
		var previous: ItemInstance = member.equipment.get(slot, null)
		member.equipment[slot] = item
		GameState.profile.storage.erase(item)
		if previous != null:
			GameState.profile.storage.append(previous)
		EventBus.notify("%s экипирует %s" % [member.data.display_name, item.display_name()])
	else:
		var result := member.inventory.add(item)
		if not result.ok:
			EventBus.notify(result.error)
			return
		GameState.profile.storage.erase(item)
		EventBus.notify("%s забирает %s" % [member.data.display_name, item.display_name()])
	SaveSystem.save_profile()
	_open_storage()

# --- Спуск в Разлом ---

func _open_descend() -> void:
	var box := _panel(760, 560, "Спуск в Разлом")
	box.add_child(UIKit.label("20 этажей, два акта. Врата Возврата на этажах %s."
		% ", ".join(Array(Balance.data.extraction_floors).map(func(v: int) -> String: return str(v))), 13))
	box.add_child(UIKit.label("Снаряжение возвращается всегда. Теряется только добытое внизу.", 12))
	var torches := 0
	for member: CharacterState in GameState.profile.party:
		torches += member.inventory.count_of(&"torch")
	var wounded := _wounded_members()
	var fallen := _fallen_members()
	var warnings: Array[String] = []
	if torches == 0:
		warnings.append("В отряде нет факелов — вы уйдёте в темноту.")
	if not fallen.is_empty():
		warnings.append("Павших героев: %d — их поднимет Алтарь." % fallen.size())
	if not wounded.is_empty():
		warnings.append("Раненых героев: %d — их исцелит Алтарь." % wounded.size())
	if not warnings.is_empty():
		var line := UIKit.label("\n".join(warnings), 12, UIKit.DANGER)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)
	box.add_child(UIKit.label("Факелов у отряда: %d" % torches, 12))
	box.add_child(UIKit.spacer())
	for member: CharacterState in GameState.profile.party:
		box.add_child(_altar_row(member))
	var ready := fallen.size() < GameState.profile.party.size()
	var start := _action("Начать забег", func() -> void:
		GameState.run = null
		SaveSystem.delete_run()
		SceneRouter.goto_dungeon("Спуск на первый этаж…"))
	start.disabled = not ready
	start.tooltip_text = "" if ready else "Весь отряд пал — сначала загляните к Алтарю"
	_footer()

# --- Алтарь: исцеление и воскрешение ---
# Раны и гибель героев переносятся из забега в деревню, и снимает их только Алтарь.

func _wounded_members() -> Array[CharacterState]:
	var out: Array[CharacterState] = []
	for member: CharacterState in GameState.profile.party:
		if not member.is_dead_this_run and member.hp < member.max_hp(Balance.data):
			out.append(member)
	return out

func _fallen_members() -> Array[CharacterState]:
	var out: Array[CharacterState] = []
	for member: CharacterState in GameState.profile.party:
		if member.is_dead_this_run:
			out.append(member)
	return out

func _open_altar() -> void:
	var box := _panel(760, 560, "Алтарь")
	box.add_child(UIKit.label("Камень помнит каждого, кто спускался. Здесь отряд приходит в себя.", 12))
	box.add_child(UIKit.spacer())
	for member: CharacterState in GameState.profile.party:
		box.add_child(_altar_row(member))
	var wounded := _wounded_members()
	var fallen := _fallen_members()
	var heal := _action("Исцелить раненых", func() -> void: _altar_heal())
	heal.disabled = wounded.is_empty()
	heal.tooltip_text = "Все целы" if wounded.is_empty() else "Раненых: %d" % wounded.size()
	var revive := _action("Воскресить павших", func() -> void: _altar_revive())
	revive.disabled = fallen.is_empty()
	revive.tooltip_text = "Павших нет" if fallen.is_empty() else "Павших: %d" % fallen.size()
	var full := _action("Полное восстановление", func() -> void:
		_altar_revive(true)
		_altar_heal())
	full.disabled = wounded.is_empty() and fallen.is_empty()
	_footer()

func _altar_row(member: CharacterState) -> HBoxContainer:
	var row := UIKit.hbox(8)
	var name := member.data.display_name if member.data else String(member.hero_id)
	var max_hp := member.max_hp(Balance.data)
	if member.is_dead_this_run:
		row.add_child(UIKit.row_label("%s — пал в подземелье" % name, 13, UIKit.DANGER))
		return row
	var slots: Array[String] = []
	for i: int in member.spell_slots.size():
		if member.spell_slots[i] > 0:
			slots.append("%d ур.: %d" % [i + 1, member.spell_slots[i]])
	var suffix := ("  ·  ячейки " + ", ".join(slots)) if not slots.is_empty() else ""
	row.add_child(UIKit.row_label("%s — %d/%d HP%s" % [name, member.hp, max_hp, suffix], 13,
		UIKit.GOOD if member.hp >= max_hp else UIKit.ACCENT))
	row.add_child(UIKit.bar(member.hp, max_hp,
		UIKit.hp_color(float(member.hp) / maxf(1.0, float(max_hp))), 220))
	return row

func _altar_heal() -> void:
	var healed := 0
	for member: CharacterState in GameState.profile.party:
		if member.is_dead_this_run:
			continue
		if member.hp < member.max_hp(Balance.data) or member.spell_slots.is_empty():
			healed += 1
		member.restore_full(Balance.data)
	EventBus.notify("Алтарь исцеляет отряд: восстановлено героев — %d" % healed)
	SaveSystem.save_profile()
	_open_altar()

## silent=true — часть «полного восстановления», отдельное уведомление не нужно.
func _altar_revive(silent: bool = false) -> void:
	var names: Array[String] = []
	for member: CharacterState in _fallen_members():
		member.is_dead_this_run = false
		member.restore_full(Balance.data)
		names.append(member.data.display_name if member.data else String(member.hero_id))
	if not names.is_empty():
		EventBus.notify("Алтарь возвращает павших: %s" % ", ".join(names))
	SaveSystem.save_profile()
	if not silent:
		_open_altar()
