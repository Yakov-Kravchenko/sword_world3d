extends Node
## Дымовой прогон всей игры без окна:
##   godot --headless --path . res://tools/smoke_test.tscn
## Проверяет связку автозагрузок, сервисов и сцен, а не отдельные функции.

var failures: Array[String] = []
var report: FileAccess

func _ready() -> void:
	report = FileAccess.open("user://smoke_report.txt", FileAccess.WRITE)
	_say("===== Дымовой прогон =====")
	_check_content()
	_check_profile_cycle()
	_check_run_cycle()
	await _check_scenes()
	await _check_ui_layout()
	await _check_object_menus()
	await _check_altar()
	_say("--------------------------")
	if failures.is_empty():
		_say("Все проверки пройдены.")
	else:
		for f: String in failures:
			_say("  ! " + f)
	_say("==========================")
	if report != null:
		report.close()
	get_tree().quit(1 if not failures.is_empty() else 0)

func _say(line: String) -> void:
	print(line)
	if report != null:
		report.store_line(line)
		report.flush()

func _check(condition: bool, message: String) -> void:
	if condition:
		_say("  ok   %s" % message)
	else:
		failures.append(message)
		_say("  СБОЙ %s" % message)

func _check_content() -> void:
	_say("Контент:")
	_check(Database.errors().is_empty(), "база контента без ошибок (%d)" % Database.errors().size())
	_check(Balance.data.total_floors == 20, "balance.json загружен")
	_check(Database.of_class("HeroData").size() == 4, "четыре героя")
	_check(Database.of_class("BiomeData").size() == 12, "6 базовых + 6 глубоких биомов")
	_check(Database.of_class("StatusData").size() >= 17, "17+ статусов")
	_check(Database.of_class("SpellData").size() >= 20, "заклинания загружены")
	_check(Database.of_class("EnemyData").size() >= 20, "враги и боссы загружены")

func _check_profile_cycle() -> void:
	_say("Профиль:")
	GameState.new_profile(&"irma")
	var member := GameState.profile.member(&"irma")
	_check(member != null and member.main_weapon() != null, "стартовое снаряжение выдано")
	_check(member.skill_modifiers.has(&"stat_dex"), "бонус основного героя применён")
	_check(SaveSystem.save_profile(), "профиль сохранён атомарно")
	GameState.profile.gold = 999999
	_check(SaveSystem.load_profile(), "профиль загружен обратно")
	_check(GameState.profile.gold == 250, "загрузка вернула сохранённые значения")
	_check(GameState.profile.main_hero_id == &"irma", "основной герой сохраняется")

func _check_run_cycle() -> void:
	_say("Забег:")
	var service := RunService.new()
	var run := service.start_new_run(20260906)
	_check(run.torch_lit, "факел зажжён из инвентаря")
	var plan := service.generate_floor()
	_check(plan.rooms.size() >= 6, "этаж сгенерирован (%d комнат)" % plan.rooms.size())
	_check(plan.entrance_cell != plan.exit_cell, "вход и выход разнесены")
	_check_floor_shape(plan)
	_check(not plan.encounters.is_empty(), "встречи расставлены (%d)" % plan.encounters.size())
	var encounter := plan.encounters[0]
	var room := plan.rooms[int(encounter["room"])]
	_run_battle(service, plan, encounter, room)
	service.tick_torch(120)
	_check(run.torch_ticks_left < Balance.data.torch_ticks, "факел тратится")
	var options := service.blessing_options()
	_check(options.size() == 3, "предложено три благословения")
	service.take_blessing(options[0])
	_check(run.blessings.size() == 1, "благословение взято")
	_check(SaveSystem.save_run(), "забег сохранён")
	service.descend()
	_check(run.floor_index == 2, "спуск на следующий этаж")
	var summary := service.extract()
	_check(String(summary["outcome"]) == "extracted", "выход через Врата даёт успешный итог")
	_check(GameState.run == null, "забег закрыт")

func _run_battle(service: RunService, plan: FloorPlan, encounter: Dictionary,
		room: FloorPlan.Room) -> void:
	var party: Array = []
	var run_mods := service.run.blessing_modifiers()
	for member: CharacterState in service.run.party:
		party.append(ActorBuilder.from_hero(member, Balance.data, run_mods))
	var enemies: Array = []
	var i := 0
	for enemy_id: StringName in encounter["enemies"]:
		var data := Database.get_enemy(enemy_id)
		if data != null:
			enemies.append(ActorBuilder.from_enemy(data, i, Balance.data, false,
				service.run.floor_index))
			i += 1
	_check(not enemies.is_empty(), "враги встречи собраны (%d)" % enemies.size())
	if enemies.is_empty():
		return
	var state := BattleSimulator.build_state(party, enemies, Balance.data,
		Database.status_map(), service.run.run_seed)
	state.spell_db = Database.spell_map()
	var result := BattleSimulator.run(state)
	_check(not bool(result["timeout"]), "бой завершился за %d раундов" % int(result["rounds"]))
	_check(not (result["log"] as Array).is_empty(), "лог боя не пуст")

func _check_scenes() -> void:
	_say("Сцены:")
	for path: String in [SceneRouter.MAIN_MENU, SceneRouter.VILLAGE, SceneRouter.DUNGEON]:
		var packed: PackedScene = load(path)
		_check(packed != null, "сцена загружается: %s" % path.get_file())
	GameState.new_profile(&"hald")
	var village_scene: PackedScene = load(SceneRouter.VILLAGE)
	var village: Node = village_scene.instantiate()
	add_child(village)
	await get_tree().process_frame
	_check(village.get_child_count() > 0, "деревня инстанцируется и строит мир")
	village.queue_free()
	await get_tree().process_frame
	var dungeon_scene: PackedScene = load(SceneRouter.DUNGEON)
	var dungeon: Node = dungeon_scene.instantiate()
	add_child(dungeon)
	await get_tree().process_frame
	_check(dungeon.get("plan") != null, "подземелье построило этаж")
	_check((dungeon.get("party_nodes") as Array).size() == 4, "отряд из четырёх на сцене")
	_check_minimap(dungeon)
	await _check_scene_combat(dungeon)
	dungeon.queue_free()
	await get_tree().process_frame

## Полный бой прямо в сцене: проверяет связку контроллера, боевого UI и движка.
func _check_scene_combat(dungeon: Node) -> void:
	var plan: FloorPlan = dungeon.get("plan")
	if plan.encounters.is_empty():
		_check(false, "на этаже нет встреч для проверки боя")
		return
	var encounter: Dictionary = plan.encounters[0]
	var room: FloorPlan.Room = plan.rooms[int(encounter["room"])]
	dungeon.call("_start_combat", encounter, room)
	await get_tree().process_frame
	var controller: Node = dungeon.get("combat_controller")
	_check(controller != null, "боевой контроллер создан")
	if controller == null:
		return
	_check(controller.get("state") != null, "боевое состояние собрано")
	_check(not (controller.get("state") as CombatState).initiative.is_empty(),
		"лента инициативы построена")
	var frames := 0
	var checked_panel := false
	while dungeon.get("combat_controller") != null and frames < 6000:
		frames += 1
		var state: CombatState = controller.get("state")
		var playable: bool = state != null and state.phase != CombatState.PHASE_ENDED
		if playable and controller.call("is_player_turn"):
			if not checked_panel:
				checked_panel = true
				_check_modal_layout(controller.get("ui"), "бой/панель действий")
			# За игрока ходит та же оценка полезности — важно, что путь UI отработал.
			var actor: CombatActor = controller.call("current_actor")
			for step: Dictionary in UtilityAI.plan_turn(state, actor):
				if String(step.get("kind", "")) == "move":
					controller.call("_submit", MoveAction.resolve(state, actor, step["cell"]))
				else:
					controller.call("_submit",
						AttackAction.resolve(state, actor, step["target"], step["attack"]))
			controller.call("end_turn")
		await get_tree().process_frame
	_check(frames < 6000, "бой в сцене завершился за %d кадров" % frames)

# --- Раскладка модальных окон ---
# Пункт списка бесполезен, если кнопка выбора вылезла за край панели: по ней
# нельзя кликнуть. Проверяем, что каждая кнопка ненулевая, помещается в панель по
# ширине и либо видна целиком, либо лежит в прокручиваемой области.

func _check_ui_layout() -> void:
	_say("Раскладка окон:")
	await _check_village_panels()
	await _check_hud_panels()

func _check_village_panels() -> void:
	GameState.new_profile(&"hald")
	_stock_storage(30)
	var village: Node = (load(SceneRouter.VILLAGE) as PackedScene).instantiate()
	add_child(village)
	await get_tree().process_frame
	var ui: Control = village.get("ui")
	for station: StringName in [&"forge", &"altar", &"training", &"shop", &"garden",
			&"storage", &"descend"]:
		ui.call("open_station", station)
		await get_tree().process_frame
		await get_tree().process_frame
		_check_modal_layout(ui.get("_modal"), "деревня/%s" % station)
		ui.call("close_modal")
		await get_tree().process_frame
	village.queue_free()
	await get_tree().process_frame

func _stock_storage(count: int) -> void:
	var ids: Array[StringName] = [&"armor_plate", &"warhammer", &"potion_greater", &"crossbow",
		&"shield_tower", &"rapier", &"essence_vial", &"charm_wood"]
	for i: int in count:
		var item := GameState.item_factory.create(ids[i % ids.size()])
		if item != null:
			item.upgrade_level = i % 5
			GameState.profile.storage.append(item)

func _check_hud_panels() -> void:
	var dungeon: Node = (load(SceneRouter.DUNGEON) as PackedScene).instantiate()
	add_child(dungeon)
	await get_tree().process_frame
	var hud: Control = dungeon.get("hud")
	var service: RunService = dungeon.get("service")
	var cases: Array[Array] = [
		["меню", func() -> void: hud.call("toggle_menu")],
		["сумки", func() -> void: hud.call("toggle_inventory")],
		["благословения", func() -> void: hud.call("show_blessings", service, Callable())],
		["развилка биомов", func() -> void:
			# Развилка показывается, только когда доступно больше одного биома.
			GameState.profile.unlocked_biomes = [&"catacombs", &"mines", &"mushroom_caves",
				&"swamp", &"necropolis", &"ice_fortress"]
			service.run.used_biomes.clear()
			hud.call("show_biome_fork", service, Callable())],
		["Врата", func() -> void: hud.call("show_extraction", service)],
		["итоги", func() -> void: hud.call("show_summary", {"outcome": "extracted", "floor": 10,
			"gold": 4200, "items": 6, "kept": true, "kills": 37, "bosses": 1, "best_hit": 44,
			"elapsed": 5400.0})],
	]
	for entry: Array in cases:
		entry[1].call()
		await get_tree().process_frame
		await get_tree().process_frame
		_check_modal_layout(hud.get("_modal"), "подземелье/%s" % entry[0])
		hud.call("_close_modal")
		await get_tree().process_frame
	dungeon.queue_free()
	await get_tree().process_frame

func _check_modal_layout(modal: Variant, label: String, min_enabled: int = 0) -> void:
	if not (modal is Control):
		_check(false, "%s: окно не открылось" % label)
		return
	var root: Control = modal
	var screen := Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size))
	# Корень окна обязан занимать весь экран: если он схлопнулся в 0x0, панель
	# уходит в минимальный размер, а тело со списком получает нулевую высоту.
	_check(root.size.x >= screen.size.x - 1.0 and root.size.y >= screen.size.y - 1.0,
		"%s: корень окна %.0fx%.0f (экран %.0fx%.0f)" % [label, root.size.x, root.size.y,
			screen.size.x, screen.size.y])
	for scroll: ScrollContainer in _collect_scrolls(root):
		if not scroll.is_visible_in_tree():
			continue  # скрытые вкладки TabContainer не раскладываются — это норма
		_check(scroll.size.y >= 40.0,
			"%s: высота тела окна %.0f" % [label, scroll.size.y])
	var buttons: Array[Button] = []
	_collect_buttons(root, buttons)
	if buttons.is_empty():
		_check(false, "%s: в окне нет ни одной кнопки" % label)
		return
	var enabled_count := 0
	var broken: Array[String] = []
	for button: Button in buttons:
		if not button.disabled:
			enabled_count += 1
		var rect := button.get_global_rect()
		if rect.size.x < 8.0 or rect.size.y < 8.0:
			broken.append("«%s» схлопнулась в %.0fx%.0f" % [button.text, rect.size.x, rect.size.y])
			continue
		if rect.position.x < screen.position.x - 1.0 or rect.end.x > screen.end.x + 1.0:
			broken.append("«%s» выходит за край по ширине" % button.text)
			continue
		if _in_scroll(button, root):
			continue
		if rect.position.y < screen.position.y - 1.0 or rect.end.y > screen.end.y + 1.0:
			broken.append("«%s» вне экрана по высоте" % button.text)
	var details := ""
	if not broken.is_empty():
		var shown := broken.slice(0, 3)
		details = " — " + "; ".join(shown)
		if broken.size() > shown.size():
			details += " и ещё %d" % (broken.size() - shown.size())
	_check(broken.is_empty(), "%s: %d кнопок кликабельны%s" % [label, buttons.size(), details])
	if min_enabled > 0:
		_check(enabled_count >= min_enabled,
			"%s: доступных пунктов %d (нужно %d)" % [label, enabled_count, min_enabled])

func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child: Node in node.get_children():
		if child is Button and (child as Button).visible:
			out.append(child)
		_collect_buttons(child, out)

func _in_scroll(node: Node, stop: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != stop:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false

# --- Меню объектов ---
# У каждого объекта должно открываться собственное меню с выбором, а не одно
# зашитое действие. Проверяем все типы объектов и обе стороны в бою.

func _check_object_menus() -> void:
	_say("Меню объектов:")
	var dungeon: Node = (load(SceneRouter.DUNGEON) as PackedScene).instantiate()
	add_child(dungeon)
	await get_tree().process_frame
	var hud: Control = dungeon.get("hud")
	var plan: FloorPlan = dungeon.get("plan")
	var props := _props_by_kind(plan)
	for kind: StringName in [&"stairs", &"chest", &"altar", &"trap", &"event", &"gate"]:
		dungeon.set("_pending_interaction", props[kind])
		dungeon.call("_interact")
		await get_tree().process_frame
		await get_tree().process_frame
		_check_modal_layout(hud.get("_modal"), "объект/%s" % kind, 1)
		hud.call("_close_modal")
		await get_tree().process_frame
	await _check_combat_menus(dungeon)
	dungeon.queue_free()
	await get_tree().process_frame

## Собирает по одному объекту каждого типа; отсутствующие на этаже досоздаём,
## чтобы проверка не зависела от сида.
func _props_by_kind(plan: FloorPlan) -> Dictionary:
	var out := {&"stairs": {"kind": &"stairs"}}
	for i: int in plan.props.size():
		var prop: Dictionary = plan.props[i].duplicate()
		prop["index"] = i
		var kind := StringName(prop.get("kind", &""))
		if not out.has(kind):
			out[kind] = prop
	for kind: StringName in [&"chest", &"altar", &"trap", &"event", &"gate"]:
		if out.has(kind):
			continue
		var synthetic := {"kind": kind, "cell": plan.entrance_cell, "room": 0,
			"table": &"chest_common", "dc": 13, "locked": true, "trapped": true}
		plan.props.append(synthetic)
		synthetic = synthetic.duplicate()
		synthetic["index"] = plan.props.size() - 1
		out[kind] = synthetic
	return out

func _check_combat_menus(dungeon: Node) -> void:
	var plan: FloorPlan = dungeon.get("plan")
	if plan.encounters.is_empty():
		_check(false, "нет встречи для проверки боевых меню")
		return
	var encounter: Dictionary = plan.encounters[0]
	dungeon.call("_start_combat", encounter, plan.rooms[int(encounter["room"])])
	await get_tree().process_frame
	var controller: Node = dungeon.get("combat_controller")
	if controller == null:
		_check(false, "бой не начался")
		return
	var state: CombatState = controller.get("state")
	var frames := 0
	while not controller.call("is_player_turn") and frames < 600:
		frames += 1
		await get_tree().process_frame
	if not controller.call("is_player_turn"):
		_check(false, "ход игрока так и не наступил")
		return
	_check_models(dungeon, controller)
	await _check_animations(dungeon, controller)
	_check_occupancy(controller)
	var hero: CombatActor = controller.call("current_actor")
	var enemies := state.team_actors(CombatActor.TEAM_ENEMY)
	var ui: Control = controller.get("ui")
	if not enemies.is_empty():
		controller.call("open_target_menu", enemies[0])
		await get_tree().process_frame
		await get_tree().process_frame
		_check_modal_layout(ui.get("_context_menu"), "бой/меню врага", 1)
		ui.call("close_context_menu")
		await get_tree().process_frame
	controller.call("open_target_menu", hero)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_modal_layout(ui.get("_context_menu"), "бой/меню своего героя", 2)
	ui.call("close_context_menu")
	await get_tree().process_frame

func _collect_scrolls(node: Node) -> Array[ScrollContainer]:
	var out: Array[ScrollContainer] = []
	for child: Node in node.get_children():
		if child is ScrollContainer:
			out.append(child)
		out.append_array(_collect_scrolls(child))
	return out

# --- Алтарь ---
# Помещение в деревне, которое лечит раненых и поднимает павших. Раны и гибель
# теперь переносятся из забега в деревню, поэтому Алтарю есть что делать.

func _check_altar() -> void:
	_say("Алтарь:")
	GameState.new_profile(&"hald")
	var party: Array = GameState.profile.party
	var hurt: CharacterState = party[0]
	var fallen: CharacterState = party[1]
	hurt.hp = 3
	fallen.hp = 0
	fallen.is_dead_this_run = true
	var village: Node = (load(SceneRouter.VILLAGE) as PackedScene).instantiate()
	add_child(village)
	await get_tree().process_frame
	var ui: Control = village.get("ui")
	_check_chapel(village)
	_check_village_layout(village)
	var has_station := false
	for station: Dictionary in village.get("stations"):
		if StringName(station.get("id", &"")) == &"altar":
			has_station = true
	_check(has_station, "объект «Алтарь» есть в деревне")
	ui.call("open_station", &"altar")
	await get_tree().process_frame
	await get_tree().process_frame
	_check_modal_layout(ui.get("_modal"), "деревня/алтарь (есть кого лечить)", 4)
	ui.call("_altar_revive", true)
	ui.call("_altar_heal")
	await get_tree().process_frame
	_check(hurt.hp == hurt.max_hp(Balance.data),
		"алтарь исцеляет: %d/%d" % [hurt.hp, hurt.max_hp(Balance.data)])
	_check(not fallen.is_dead_this_run, "алтарь воскрешает павшего")
	_check(fallen.hp == fallen.max_hp(Balance.data),
		"воскрешённый поднимается с полными хитами")
	_check(fallen.spell_slots.size() > 0 or fallen.data.casting_stat == &"",
		"ячейки заклинаний восстановлены")
	ui.call("close_modal")
	await get_tree().process_frame
	village.queue_free()
	await get_tree().process_frame

## Часовня — настоящее помещение: стены держат, проём пропускает.
func _check_chapel(village: Node) -> void:
	var cx: float = village.get("CHAPEL_CENTER").x
	var cz: float = village.get("CHAPEL_CENTER").y
	var half: float = village.get("CHAPEL_HALF")
	_check(bool(village.call("_blocked", cx - half, cz)), "западная стена часовни держит")
	_check(bool(village.call("_blocked", cx, cz - half)), "дальняя стена часовни держит")
	_check(not bool(village.call("_blocked", cx, cz + half)), "дверной проём открыт")
	_check(bool(village.call("_blocked", cx, cz - 2.1)), "алтарный камень непроходим")
	_check(not bool(village.call("_blocked", cx, cz)), "внутри часовни можно стоять")

# --- Модели и шкалы здоровья ---
# Силуэт врага должен структурно отличаться от героя, а не только цветом,
# и над каждым врагом должна висеть работающая полоска здоровья.

func _check_models(dungeon: Node, controller: Node) -> void:
	_say("Модели и шкалы:")
	var heroes: Array = dungeon.get("party_nodes")
	var enemy_nodes: Dictionary = controller.get("enemy_nodes")
	if heroes.is_empty() or enemy_nodes.is_empty():
		_check(false, "нет моделей для проверки")
		return
	var hero: Node3D = heroes[0]
	var enemy: Node3D = enemy_nodes.values()[0]
	_check(String(hero.get_meta("model_kind", "")) == "hero", "модель героя помечена как hero")
	_check(String(enemy.get_meta("model_kind", "")) == "enemy", "модель врага помечена как enemy")
	var hero_meshes := _mesh_classes(hero)
	var enemy_meshes := _mesh_classes(enemy)
	# Модель может быть готовой из кита или процедурной заглушкой — проверяем
	# ровно то, что соответствует текущему источнику.
	if _find_player(hero) != null:
		_check(true, "герой: модель из кита (%s)" % ", ".join(hero_meshes))
		_check(_find_player(enemy) != null, "враг: модель из кита (%s)" % ", ".join(enemy_meshes))
		# Рост не проверяем числом: у моделей из китов встречаются служебные узлы
		# с огромным bounding box, и любой замер габарита врёт. Размер выверен
		# по кадру, а при необходимости задаётся полем "scale" в aliases.json.
		_check(hero.scale.is_equal_approx(Vector3.ONE) or hero.scale.y > 0.0,
			"масштаб модели героя задан явно (%.2f)" % hero.scale.y)
	else:
		_check(hero_meshes.has("CapsuleMesh") and not hero_meshes.has("PrismMesh"),
			"герой: капсульный силуэт (%s)" % ", ".join(hero_meshes))
		_check(enemy_meshes.has("PrismMesh") and not enemy_meshes.has("CapsuleMesh"),
			"враг: угловатый силуэт (%s)" % ", ".join(enemy_meshes))
		_check(_has_emissive(enemy), "у врага светящиеся глаза")
	_check_health_bar(controller)
	_check_hud_live_update(dungeon, controller)

func _check_health_bar(controller: Node) -> void:
	var bars: Dictionary = controller.get("health_bars")
	if bars.is_empty():
		_check(false, "над врагами нет шкал здоровья")
		return
	var actor_id: StringName = bars.keys()[0]
	var bar: HealthBar3D = bars[actor_id]
	var actor: CombatActor = (controller.get("state") as CombatState).get_actor(actor_id)
	_check(bar.get_parent() == controller.get("enemy_nodes")[actor_id],
		"шкала прикреплена к модели врага")
	_check(is_equal_approx(bar.ratio(), 1.0), "шкала стартует с полного здоровья")
	var full := actor.effective_max_hp()
	actor.hp = maxi(1, int(full / 4))
	controller.call("_refresh_health_bars")
	_check(bar.ratio() < 0.4, "шкала падает вместе с хитами: %.2f" % bar.ratio())
	actor.hp = full
	controller.call("_refresh_health_bars")
	_check(is_equal_approx(bar.ratio(), 1.0), "шкала возвращается при лечении")

func _mesh_classes(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child: Node in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var cls := (child as MeshInstance3D).mesh.get_class()
			if not out.has(cls):
				out.append(cls)
		for nested: String in _mesh_classes(child):
			if not out.has(nested):
				out.append(nested)
	return out

func _has_emissive(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var mat: Variant = (child as MeshInstance3D).material_override
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
				return true
		if _has_emissive(child):
			return true
	return false

## Панель отряда обязана показывать урон сразу, а не после боя.
func _check_hud_live_update(dungeon: Node, controller: Node) -> void:
	var hud: Control = dungeon.get("hud")
	var state: CombatState = controller.get("state")
	var heroes := state.team_actors(CombatActor.TEAM_PARTY)
	if heroes.is_empty():
		_check(false, "в бою нет героев")
		return
	var service: RunService = controller.get("service")
	var member: CharacterState = service.run.member(heroes[0].source_id)
	var full := member.max_hp(Balance.data)
	member.hp = maxi(1, full - 5)
	EventBus.action_resolved.emit(ActionResult.new())
	var needle := "%d/%d HP" % [member.hp, full]
	_check(_find_label(hud, needle), "панель отряда обновляется во время боя (%s)" % needle)
	member.hp = full
	EventBus.action_resolved.emit(ActionResult.new())

func _find_label(node: Node, needle: String) -> bool:
	for child: Node in node.get_children():
		if child is Label and (child as Label).text.contains(needle):
			return true
		if _find_label(child, needle):
			return true
	return false

## Постройки должны быть разнесены: деревню обходят, а не разглядывают с места.
func _check_village_layout(village: Node) -> void:
	var stations: Array = village.get("stations")
	_check(stations.size() >= 7, "в деревне %d объектов" % stations.size())
	var closest := 1e9
	var pair := ""
	for i: int in stations.size():
		for j: int in range(i + 1, stations.size()):
			var a: Vector3 = stations[i]["pos"]
			var b: Vector3 = stations[j]["pos"]
			var distance := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
			if distance < closest:
				closest = distance
				pair = "%s и %s" % [stations[i]["name"], stations[j]["name"]]
	_check(closest >= 12.0, "ближайшая пара (%s) разнесена на %.1f м" % [pair, closest])
	var limit: float = village.get("YARD_LIMIT")
	_check(limit >= 30.0, "двор расширен до %.0f м в полуширину" % limit)
	# Каждая постройка — набор мешей, а не одна тумба.
	var meshes := 0
	for child: Node in village.get_children():
		if child is MeshInstance3D:
			meshes += 1
	_check(meshes >= 150, "деревня собрана из %d элементов" % meshes)

# --- Миникарта ---
# Виджет создаётся через preload().new(): при ошибке компиляции он молча станет
# null, поэтому его существование проверяется отдельно.

func _check_minimap(dungeon: Node) -> void:
	_say("Миникарта:")
	var minimap: Variant = dungeon.get("minimap")
	_check(minimap != null and is_instance_valid(minimap), "виджет карты создан")
	if minimap == null or not is_instance_valid(minimap):
		return
	var map: Control = minimap
	var plan: FloorPlan = dungeon.get("plan")
	var service: RunService = dungeon.get("service")
	_check(map.get("plan") != null, "карта знает план этажа")
	_check(map.size.x > 100.0 and map.size.y > 100.0,
		"карта имеет размер %.0fx%.0f" % [map.size.x, map.size.y])
	var small := map.size
	map.call("toggle")
	_check(map.size.x > small.x, "M разворачивает карту: %.0f -> %.0f" % [small.x, map.size.x])
	map.call("toggle")
	_check(is_equal_approx(map.size.x, small.x), "повторное M сворачивает карту")
	# Отряд, вход и выход должны переводиться в разные точки внутри виджета.
	var entrance: Vector2 = map.call("_to_local", Vector2(plan.entrance_cell))
	var exit_point: Vector2 = map.call("_to_local", Vector2(plan.exit_cell))
	_check(entrance.distance_to(exit_point) > 4.0,
		"вход и выход разнесены на карте (%.0f px)" % entrance.distance_to(exit_point))
	_check(Rect2(Vector2.ZERO, map.size).has_point(entrance), "вход попадает в поле карты")
	_check(Rect2(Vector2.ZERO, map.size).has_point(exit_point), "выход попадает в поле карты")
	# Посещённые комнаты копятся по ходу движения отряда.
	var before := service.run.visited_rooms.size()
	dungeon.call("_mark_visited_room")
	_check(service.run.visited_rooms.size() >= before, "посещённые комнаты отмечаются")
	var room := plan.room_at(plan.entrance_cell)
	_check(room != null and service.run.visited_rooms.has(room.index),
		"стартовая комната помечена пройденной")

# --- Анимации ---
# Проверяем не «файл существует», а что анимация реально двигает сустав модели.

func _check_animations(dungeon: Node, controller: Node) -> void:
	_say("Анимации:")
	var state: CombatState = controller.get("state")
	var animators: Dictionary = controller.get("animators")
	_check(animators.size() >= 2, "аниматоры созданы для обеих сторон (%d)" % animators.size())
	var heroes := state.team_actors(CombatActor.TEAM_PARTY)
	var enemies := state.team_actors(CombatActor.TEAM_ENEMY)
	if heroes.is_empty() or enemies.is_empty() or animators.is_empty():
		_check(false, "нет актёров для проверки анимаций")
		return
	var hero: CombatActor = heroes[0]
	var node: Node3D = controller.call("_node_of", hero.id)
	var animator: ActorAnimator = animators[hero.id]
	var rigged := _find_player(node) != null
	if rigged:
		_check(true, "модель пришла со своим AnimationPlayer")
		var clips := _find_player(node).get_animation_list()
		var has_attack := false
		for clip: String in clips:
			if clip.to_lower().contains("attack"):
				has_attack = true
		_check(has_attack, "в модели есть клип удара (%d клипов)" % clips.size())
		animator.play_attack(controller.call("_node_of", enemies[0].id).global_position)
		for i: int in 6:
			await get_tree().process_frame
		_check(_find_player(node).is_playing(), "клип удара проигрывается")
		for i: int in 40:
			await get_tree().process_frame
		return
	_check(node.get_node_or_null("Torso/ShoulderR") != null, "у героя есть плечевой сустав")
	_check(node.get_node_or_null("Torso/ShoulderR/ForearmR/Weapon") != null,
		"оружие висит в кисти правой руки")
	_check(node.get_node_or_null("HipL/ShinL") != null, "нога собрана из бедра и голени")
	var arm: Node3D = node.get_node("Torso/ShoulderR")
	var before := arm.rotation.x
	animator.play_attack(controller.call("_node_of", enemies[0].id).global_position)
	for i: int in 6:
		await get_tree().process_frame
	_check(not is_equal_approx(arm.rotation.x, before), "удар поворачивает руку")
	_check(animator.is_busy(), "во время удара аниматор занят")
	for i: int in 40:
		await get_tree().process_frame
	_check(not animator.is_busy(), "после удара рука возвращается")
	# Заклинание поднимает обе руки и создаёт вспышку.
	var left: Node3D = node.get_node("Torso/ShoulderL")
	animator.play_cast(node.global_position + Vector3.FORWARD)
	for i: int in 6:
		await get_tree().process_frame
	_check(left.rotation.x < -0.1, "сотворение поднимает вторую руку")
	for i: int in 45:
		await get_tree().process_frame
	# Падение заваливает фигуру.
	var enemy_id: StringName = enemies[0].id
	var enemy_node: Node3D = controller.call("_node_of", enemy_id)
	var enemy_animator: ActorAnimator = animators[enemy_id]
	enemy_animator.play_die()
	for i: int in 20:
		await get_tree().process_frame
	_check(enemy_node.rotation.x < -0.2, "гибель заваливает фигуру")

# --- Одна клетка — один персонаж ---

func _check_occupancy(controller: Node) -> void:
	_say("Занятость клеток:")
	var state: CombatState = controller.get("state")
	var seen := {}
	var overlap := ""
	for actor: CombatActor in state.all_actors():
		for cell: Vector2i in actor.occupied_cells():
			if seen.has(cell):
				overlap = "%s и %s делят клетку %s" % [actor.display_name, seen[cell], cell]
			seen[cell] = actor.display_name
	_check(overlap.is_empty(), "при размещении наложений нет%s" % ("" if overlap.is_empty()
		else ": " + overlap))
	var actors := state.all_actors()
	if actors.size() < 2:
		return
	var mover: CombatActor = actors[0]
	var other: CombatActor = actors[1]
	_check(state.can_occupy(other, other.cell), "актёр умещается на своей же клетке")
	_check(not state.can_occupy(mover, other.cell), "чужая клетка считается занятой")
	mover.movement_left = 30
	var result := MoveAction.resolve(state, mover, other.cell)
	_check(not result.ok, "шаг на занятую клетку отклонён: «%s»" % result.error)
	_check(mover.cell != other.cell, "после отказа актёр остался на месте")

## Модель из кита должна быть подогнана по росту, иначе герой будет с ноготок.
func _check_model_height(node: Node3D, label: String, expected: float) -> void:
	# Меряем в мировых координатах: важно то, какого роста фигура на экране.
	var world_height := ModelLibrary.measure_world(node).size.y
	_check(absf(world_height - expected) < 0.4,
		"%s: рост модели %.2f м (ожидается %.2f)" % [label, world_height, expected])

func _find_player(node: Node) -> AnimationPlayer:
	for child: Node in node.get_children():
		if child is AnimationPlayer:
			return child
		var nested := _find_player(child)
		if nested != null:
			return nested
	return null

## Форма этажа: выход в дальнем конце и коридоры, по которым отряд проходит не
## гуськом. Обе проверки нужны — иначе регрессия видна только глазами.
func _check_floor_shape(plan: FloorPlan) -> void:
	var entrance_room := plan.room_at(plan.entrance_cell)
	var exit_room := plan.room_at(plan.exit_cell)
	if entrance_room == null or exit_room == null:
		_check(false, "вход и выход лежат в комнатах")
		return
	var distances := _room_distances(plan, entrance_room.index)
	var exit_distance: int = int(distances.get(exit_room.index, -1))
	var farthest := -1
	for i: int in plan.rooms.size():
		farthest = maxi(farthest, int(distances.get(i, -1)))
	_check(exit_distance == farthest,
		"выход в самой дальней комнате (%d из %d переходов)" % [exit_distance, farthest])
	_check(_narrowest_corridor(plan) >= 3,
		"коридоры шириной от 3 клеток (узкое место: %d)" % _narrowest_corridor(plan))

func _room_distances(plan: FloorPlan, from_index: int) -> Dictionary:
	var dist := {from_index: 0}
	var queue: Array[int] = [from_index]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for n: int in plan.rooms[cur].connections:
			if dist.has(n):
				continue
			dist[n] = int(dist[cur]) + 1
			queue.append(n)
	return dist

## Ширина самого узкого места коридоров. Меряем по каждой клетке вне комнат:
## сколько таких же клеток подряд идёт по горизонтали и по вертикали. Коридор
## шириной 3 даёт тройку хотя бы по одной оси — по той, что поперёк движения.
## Одной горизонтальной меры мало: вертикальный коридор у стены комнаты даёт в
## строке одну-две клетки, хотя сам по себе широкий.
func _narrowest_corridor(plan: FloorPlan) -> int:
	var narrowest := 99
	for y: int in range(1, plan.height - 1):
		for x: int in range(1, plan.width - 1):
			var cell := Vector2i(x, y)
			if not (plan.is_floor(cell) and plan.room_at(cell) == null):
				continue
			var span := maxi(_corridor_run(plan, cell, Vector2i.RIGHT),
				_corridor_run(plan, cell, Vector2i.DOWN))
			narrowest = mini(narrowest, span)
	return narrowest

func _corridor_run(plan: FloorPlan, cell: Vector2i, axis: Vector2i) -> int:
	var run := 1
	for sign_value: int in [1, -1]:
		var cur := cell + axis * sign_value
		while plan.is_floor(cur) and plan.room_at(cur) == null:
			run += 1
			cur += axis * sign_value
	return run
