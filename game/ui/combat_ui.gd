extends Control
## Боевой интерфейс: лента инициативы, панель действий, лог с расшифровкой бросков.

var controller: Node
var _initiative_box: HFlowContainer
var _round_label: Label
var _actor_label: Label
var _resources_label: Label
var _hint_label: Label
var _actions_box: VBoxContainer
var _log: RichTextLabel
var _context_menu: Control

func setup(combat_controller: Node) -> void:
	controller = combat_controller
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _build() -> void:
	var top := UIKit.panel(UIKit.BG_SOFT)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 470
	top.offset_right = -12
	top.offset_top = 10
	add_child(top)
	var top_box := UIKit.vbox(4)
	top.add_child(top_box)
	_round_label = UIKit.label("Раунд 1", 15, UIKit.ACCENT)
	top_box.add_child(_round_label)
	_initiative_box = UIKit.flow(4)
	top_box.add_child(_initiative_box)

	var panel := UIKit.panel(UIKit.BG)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 320
	panel.offset_right = -450
	panel.offset_top = -210
	panel.offset_bottom = -12
	add_child(panel)
	var box := UIKit.vbox(4)
	panel.add_child(box)
	_actor_label = UIKit.label("", 17, UIKit.ACCENT)
	_resources_label = UIKit.label("", 13)
	_hint_label = UIKit.label("", 13, UIKit.ACCENT)
	box.add_child(_actor_label)
	box.add_child(_resources_label)
	box.add_child(_hint_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_actions_box = UIKit.vbox(4)
	_actions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_actions_box)

	var log_panel := UIKit.panel(UIKit.BG_SOFT)
	log_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	log_panel.offset_left = -430
	log_panel.offset_right = -12
	log_panel.offset_top = -330
	log_panel.offset_bottom = -150
	add_child(log_panel)
	_log = UIKit.rich("", 12)
	_log.custom_minimum_size = Vector2(400, 160)
	log_panel.add_child(_log)

func set_round(number: int) -> void:
	_round_label.text = "Раунд %d" % number
	_rebuild_initiative()

func append_log(line: String) -> void:
	_log.append_text(line + "\n")

## Контекстное меню цели живёт поверх боевого интерфейса.
func open_context_menu(title: String, subtitle: String, options: Array,
		rank: String = "") -> void:
	close_context_menu()
	_context_menu = ContextMenu.build(self, title, subtitle, options,
		func() -> void: close_context_menu(), get_global_mouse_position() + Vector2(12.0, 12.0),
		rank)

func close_context_menu() -> void:
	if _context_menu != null:
		_context_menu.queue_free()
		_context_menu = null

func has_context_menu() -> bool:
	return _context_menu != null

func set_hint(text: String) -> void:
	_hint_label.text = text

func set_reachable(count: int) -> void:
	if count > 0:
		set_hint("ЛКМ — шаг или атака, ПКМ по существу — меню его действий, пробел — конец хода.")

func refresh() -> void:
	_rebuild_initiative()
	var actor: CombatActor = controller.current_actor()
	if actor != null:
		_update_resources(actor)

func set_active_actor(actor: CombatActor) -> void:
	_rebuild_initiative()
	var suffix := "" if actor.team == CombatActor.TEAM_PARTY else "  (ход врага)"
	_actor_label.text = "%s%s" % [actor.display_name, suffix]
	_update_resources(actor)
	_rebuild_actions(actor)

func _update_resources(actor: CombatActor) -> void:
	var statuses := ""
	if not actor.statuses.is_empty():
		var names: Array[String] = []
		for s: StatusEffect in actor.statuses:
			names.append(s.data.display_name + ("x%d" % s.stacks if s.stacks > 1 else ""))
		statuses = "  ·  " + ", ".join(names)
	_resources_label.text = "HP %d/%d · КБ %d · движение %d · действие %d · бонус %d · реакция %d%s" % [
		actor.hp, actor.effective_max_hp(), actor.effective_ac(), actor.movement_left,
		actor.action_left, actor.bonus_left, actor.reaction_left, statuses]

func _rebuild_initiative() -> void:
	for child: Node in _initiative_box.get_children():
		child.queue_free()
	var state: CombatState = controller.state
	if state == null:
		return
	for i: int in state.initiative.size():
		var actor := state.get_actor(state.initiative[i])
		if actor == null or actor.is_dead:
			continue
		var is_current := i == state.turn_index % maxi(1, state.initiative.size())
		var color := UIKit.ACCENT if is_current else (
			UIKit.GOOD if actor.team == CombatActor.TEAM_PARTY else UIKit.DANGER)
		var chip := UIKit.panel(Color(0.14, 0.14, 0.17, 0.95), 4)
		var text := "%s %d" % [actor.display_name.left(14), actor.hp]
		chip.add_child(UIKit.label(("> " if is_current else "") + text, 12, color))
		_initiative_box.add_child(chip)

## Панель действий строится из данных: заклинания и способности приходят из data/.
## Кнопки лежат в переносящемся ряду, поэтому ни одна не уезжает за край панели.
func _rebuild_actions(actor: CombatActor) -> void:
	for child: Node in _actions_box.get_children():
		child.queue_free()
	if actor.team != CombatActor.TEAM_PARTY:
		return
	var row := UIKit.flow()
	_actions_box.add_child(row)
	row.add_child(UIKit.button("Атака (ЛКМ по врагу)", func() -> void:
		set_hint("Кликните по врагу в пределах досягаемости"), 12))
	row.add_child(UIKit.button("Рывок", func() -> void: controller.simple_action(&"dash"), 12))
	row.add_child(UIKit.button("Уклонение", func() -> void: controller.simple_action(&"dodge"), 12))
	row.add_child(UIKit.button("Отход", func() -> void: controller.simple_action(&"disengage"), 12))
	row.add_child(UIKit.button("Помощь", func() -> void: controller.simple_action(&"help"), 12))
	row.add_child(UIKit.button("Толчок", func() -> void: controller.simple_action(&"shove"), 12))
	row.add_child(UIKit.button("Стабилизировать", func() -> void:
		controller.simple_action(&"stabilize"), 12))
	row.add_child(UIKit.button("Конец хода (пробел)", func() -> void: controller.end_turn(), 12))
	_add_spells(actor)
	_add_abilities(actor)
	_add_consumables(actor)

func _add_spells(actor: CombatActor) -> void:
	if actor.spells.is_empty():
		return
	_actions_box.add_child(UIKit.label("Заклинания", 13, UIKit.ACCENT))
	var row := UIKit.flow()
	_actions_box.add_child(row)
	for spell_id: StringName in actor.spells:
		var spell := Database.get_spell(spell_id)
		if spell == null or spell.level > Balance.data.max_spell_level:
			continue
		var label := "%s (%s)" % [spell.display_name,
			"заговор" if spell.is_cantrip() else "%d ур." % spell.level]
		var button := UIKit.button(label, func() -> void:
			controller.begin_spell_targeting(spell), 12)
		button.disabled = not SpellAction.has_slot(actor, spell.level)
		button.tooltip_text = spell.description
		row.add_child(button)

func _add_abilities(actor: CombatActor) -> void:
	if actor.abilities.is_empty():
		return
	_actions_box.add_child(UIKit.label("Способности", 13, UIKit.ACCENT))
	var row := UIKit.flow()
	_actions_box.add_child(row)
	for ability_id: StringName in actor.abilities:
		var ability := Database.get_ability(ability_id)
		if ability == null:
			continue
		var left := AbilityAction.uses_left(actor, ability)
		var label := ability.display_name
		if ability.uses_per_rest > 0:
			label += " (%d/%d)" % [left, ability.uses_per_rest]
		var button := UIKit.button(label, func() -> void:
			controller.begin_ability_targeting(ability), 12)
		button.disabled = left <= 0
		button.tooltip_text = ability.description
		row.add_child(button)

func _add_consumables(actor: CombatActor) -> void:
	var member: CharacterState = controller.service.run.member(actor.source_id)
	if member == null or member.inventory == null:
		return
	var items: Array[ItemInstance] = []
	for item: ItemInstance in member.inventory.items():
		if item.data is ConsumableData and (item.data as ConsumableData).effect != &"torch":
			items.append(item)
	if items.is_empty():
		return
	_actions_box.add_child(UIKit.label("Расходники", 13, UIKit.ACCENT))
	var row := UIKit.flow()
	_actions_box.add_child(row)
	for item: ItemInstance in items:
		row.add_child(UIKit.button("%s x%d" % [item.display_name(), item.quantity],
			func() -> void: controller.use_item(item, actor), 12))
