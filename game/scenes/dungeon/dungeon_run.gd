extends Node3D
## Корень забега: строит этаж, водит отряд в режиме исследования и передаёт
## управление боевому контроллеру при встрече.

enum Mode { LOADING, EXPLORE, COMBAT, DIALOG }

const MOVE_SPEED := 4.5
const SPRINT_MULT := 1.6
## Строй отряда в локальных координатах лидера: «перёд» — это -Z, поэтому
## спутники стоят по +Z. Ширина строя 2.6 м против коридора в 3 клетки (4.5 м) —
## отряд идёт клином, а не гуськом.
const FORMATION: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(-1.3, 0.0, 0.9),
	Vector3(1.3, 0.0, 0.9),
	Vector3(0.0, 0.0, 1.9),
]
const INTERACT_RANGE := 2.2

var service: RunService
var plan: FloorPlan
var biome: BiomeData
var cell_size: float = 1.5
var mode: int = Mode.LOADING

var builder: FloorBuilder
var party_nodes: Array[Node3D] = []
var leader: Node3D
var camera: Camera3D
var camera_yaw: float = 0.0
var camera_pitch: float = -0.45
var torch_light: OmniLight3D
var environment: WorldEnvironment
var combat_controller: Node
var hud: Control
var minimap: Control
## Аниматоры отряда в режиме исследования: держат клип ходьбы и стойки.
var _walk_animators: Array[ActorAnimator] = []
## Круги под ногами: показывают, что герой — персонаж игрока.
var _rings: Array[SelectionRing3D] = []
var _torch_accumulator: float = 0.0
var _pending_interaction: Dictionary = {}
## Разовые результаты действий над ящиками: индекс пропа -> уже сделано.
var _chest_unlocked: Dictionary = {}
var _chest_checked: Dictionary = {}

func _ready() -> void:
	service = RunService.new()
	if GameState.run == null:
		service.start_new_run()
	else:
		service.attach(GameState.run)
	cell_size = Balance.data.grid_cell_size
	_build_world()
	_spawn_party()
	_build_ui()
	mode = Mode.EXPLORE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.notify("Этаж %d — %s" % [service.run.floor_index, biome.display_name])

func _build_world() -> void:
	biome = Database.get_biome(service.run.current_biome)
	plan = service.generate_floor()
	builder = FloorBuilder.new()
	builder.name = "Floor"
	add_child(builder)
	builder.build(plan, biome, cell_size)
	_build_environment()
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 60.0
	add_child(camera)

func _build_environment() -> void:
	environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = biome.fog_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = biome.ambient_color
	env.ambient_light_energy = 1.0
	# Плотный туман: и стиль, и обрезка дальности отрисовки (08-architecture.md 8.2).
	env.fog_enabled = true
	env.fog_light_color = biome.fog_color
	env.fog_density = biome.fog_density
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

func _spawn_party() -> void:
	var start := FloorBuilder.cell_to_world(plan.entrance_cell, cell_size, 0.9)
	for i: int in service.run.party.size():
		var member: CharacterState = service.run.party[i]
		var node := _make_actor_node(member.data.display_name if member.data else "Герой",
			member.data.tint if member.data else Color.WHITE, 1.8, member.hero_id)
		node.position = start + _formation_offset(i)
		add_child(node)
		party_nodes.append(node)
		_walk_animators.append(ActorAnimator.attach(node))
		ActorModel.set_casts_shadow(node, false)
		var ring := SelectionRing3D.create()
		node.add_child(ring)
		_rings.append(ring)
	leader = party_nodes[0]
	# В исследовании «ходит» тот, кем управляешь, — лидер.
	set_active_ring(service.run.party[0].hero_id)
	torch_light = OmniLight3D.new()
	torch_light.light_color = Color(1.0, 0.72, 0.42)
	torch_light.light_energy = 2.4
	torch_light.omni_range = Balance.data.light_dim_cells * cell_size
	torch_light.shadow_enabled = true   # единственный источник теней в кадре
	torch_light.position = Vector3(0.4, 1.7, 0.5)   # факел над плечом, а не внутри груди
	leader.add_child(torch_light)
	_update_followers(1.0)
	_update_camera(0.0)

## Герои строятся отдельной моделью — силуэт должен отличаться от вражеского.
func _make_actor_node(label: String, tint: Color, _height: float, hero_id: StringName = &"") -> Node3D:
	return ActorModel.build_hero(label, tint, hero_id)

func _build_ui() -> void:
	hud = preload("res://game/ui/hud.gd").new()
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	layer.add_child(hud)
	hud.setup(service)
	minimap = preload("res://game/ui/minimap.gd").new()
	layer.add_child(minimap)
	minimap.setup(service, plan)

func _process(delta: float) -> void:
	if mode == Mode.EXPLORE and not hud.has_modal():
		_process_explore(delta)
	_update_camera(delta)

func _process_explore(delta: float) -> void:
	service.run.elapsed_seconds += delta
	_torch_accumulator += delta
	while _torch_accumulator >= 1.0:
		_torch_accumulator -= 1.0
		service.tick_torch(1)
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if input.length() > 0.01:
		var speed := MOVE_SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
		var basis_dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera_yaw)
		_try_move(leader, basis_dir.normalized() * speed * delta)
		leader.rotation.y = atan2(-basis_dir.x, -basis_dir.z)
	_set_walking(input.length() > 0.01)
	_update_followers(delta)
	_mark_visited_room()
	_check_room_trigger()
	_update_interaction()

## Движение с проверкой проходимости по сетке — без физических тел.
func _try_move(node: Node3D, motion: Vector3) -> void:
	var target := node.global_position + motion
	var horizontal := Vector3(target.x, node.global_position.y, node.global_position.z)
	if _walkable_at(horizontal):
		node.global_position.x = target.x
	var vertical := Vector3(node.global_position.x, node.global_position.y, target.z)
	if _walkable_at(vertical):
		node.global_position.z = target.z

func _walkable_at(pos: Vector3) -> bool:
	return plan.is_floor(FloorBuilder.world_to_cell(pos, cell_size))

func _update_followers(delta: float) -> void:
	var weight := clampf(delta * 5.0, 0.0, 1.0)
	for i: int in range(1, party_nodes.size()):
		var member: CharacterState = service.run.party[i]
		var node := party_nodes[i]
		node.visible = not member.is_dead_this_run
		node.global_position = node.global_position.lerp(_formation_slot(i), weight)
		# Строй смотрит туда же, куда лидер: спутник, доворачивающийся по своему
		# шагу, на месте разворачивался как попало.
		node.rotation.y = lerp_angle(node.rotation.y, leader.rotation.y, weight)

## Место спутника в строю в мировых координатах.
func _formation_slot(index: int) -> Vector3:
	var offset := _formation_offset(index).rotated(Vector3.UP, leader.rotation.y)
	# На повороте и в узком месте место в строю может уткнуться в стену — тогда
	# спутник подтягивается ближе к лидеру, вплоть до его собственной клетки.
	for factor: float in [1.0, 0.66, 0.33]:
		var candidate := leader.global_position + offset * factor
		if _walkable_at(candidate):
			return candidate
	return leader.global_position

func _formation_offset(index: int) -> Vector3:
	return FORMATION[index] if index < FORMATION.size() else FORMATION[FORMATION.size() - 1]

func _update_camera(delta: float) -> void:
	if camera == null or leader == null:
		return
	if mode == Mode.COMBAT:
		_update_camera_combat(delta)
		return
	var offset := Vector3(0.0, 4.2, 6.0).rotated(Vector3.UP, camera_yaw)
	var desired: Vector3 = leader.global_position + offset
	camera.global_position = camera.global_position.lerp(desired, clampf(delta * 8.0, 0.05, 1.0)) \
		if delta > 0.0 else desired
	camera.look_at(leader.global_position + Vector3.UP * 1.2, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		camera_yaw -= (event as InputEventMouseMotion).relative.x * 0.005
	if mode == Mode.COMBAT and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_LEFT or button == MOUSE_BUTTON_RIGHT:
			if combat_controller != null:
				combat_controller.handle_click(button == MOUSE_BUTTON_RIGHT)
			return
	if event.is_action_pressed("end_turn") and mode == Mode.COMBAT and combat_controller != null:
		combat_controller.end_turn()
	if event.is_action_pressed("interact") and mode == Mode.EXPLORE:
		_interact()
	if event.is_action_pressed("toggle_dev_mode"):
		_toggle_dev_mode()
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and key_event.keycode == KEY_Q and not service.run.torch_lit:
		if service.light_new_torch():
			EventBus.notify("Зажжён новый факел.")
		else:
			EventBus.notify("Факелов не осталось.")
	if event.is_action_pressed("toggle_inventory") and mode != Mode.COMBAT:
		hud.toggle_inventory()
	if event.is_action_pressed("toggle_map") and minimap != null:
		minimap.toggle()
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		hud.toggle_menu()

# --- Взаимодействия и триггеры ---

## Отмечаем комнату посещённой — по этому списку рисуется миникарта.
func _mark_visited_room() -> void:
	var cell := _current_cell()
	if minimap != null:
		minimap.set_party_cell(cell)
	var room := plan.room_at(cell)
	if room == null or service.run.visited_rooms.has(room.index):
		return
	service.run.visited_rooms.append(room.index)
	minimap.refresh()

func _current_cell() -> Vector2i:
	return FloorBuilder.world_to_cell(leader.global_position, cell_size)

func _update_interaction() -> void:
	_pending_interaction = {}
	var cell := _current_cell()
	if cell == plan.exit_cell:
		_pending_interaction = {"kind": &"stairs"}
	else:
		for i: int in plan.props.size():
			var prop: Dictionary = plan.props[i]
			if service.run.looted_props.has(i):
				continue
			if CombatGrid.distance(cell, prop["cell"]) <= 1:
				_pending_interaction = prop.duplicate()
				_pending_interaction["index"] = i
				break
	hud.set_interaction(_interaction_label())

func _interaction_label() -> String:
	if _pending_interaction.is_empty():
		return ""
	match StringName(_pending_interaction.get("kind", &"")):
		&"stairs": return "E — лестница вниз"
		&"chest": return "E — ящик%s" % (" (заперт)" if bool(_pending_interaction.get("locked", false))
			and not _chest_unlocked.has(_prop_index()) else "")
		&"altar": return "E — алтарь"
		&"trap": return "E — ловушка"
		&"event": return "E — старое святилище"
		&"gate": return "E — Врата Возврата"
	return ""

## E открывает меню объекта, а не выполняет одно зашитое действие: у каждого
## объекта свой набор вариантов, и выбор делает игрок.
func _interact() -> void:
	if _pending_interaction.is_empty():
		return
	match StringName(_pending_interaction.get("kind", &"")):
		&"stairs": _menu_stairs()
		&"chest": _menu_chest(_pending_interaction)
		&"altar": _menu_altar(_pending_interaction)
		&"trap": _menu_trap(_pending_interaction)
		&"event": _menu_event(_pending_interaction)
		&"gate": _menu_gate()

func _prop_index() -> int:
	return int(_pending_interaction.get("index", -1))

## Лучший в отряде по характеристике — проверку делает он (02-combat.md, разд. 3.4).
func _best_hero(stat_key: StringName) -> CharacterState:
	var best: CharacterState = null
	for member: CharacterState in service.run.alive_party():
		if best == null or member.stat_mod(stat_key) > best.stat_mod(stat_key):
			best = member
	return best

func _spend_prop(index: int) -> void:
	if index < 0 or service.run.looted_props.has(index):
		return
	service.run.looted_props.append(index)
	builder.hide_prop(index)
	hud.refresh()

func _prop_stream(name: StringName, index: int) -> RngStream:
	return service.run.stream(name, "%d_%d" % [service.run.floor_index, index])

# --- Лестница вниз ---

func _menu_stairs() -> void:
	var blocker := _descent_blocker()
	var options: Array = [
		ContextMenu.option("Спуститься на этаж %d" % (service.run.floor_index + 1),
			func() -> void: _try_descend(), blocker, blocker.is_empty()),
		ContextMenu.option("Осмотреть этаж", func() -> void:
			EventBus.notify(_floor_survey()), "Что осталось незачищенным"),
	]
	hud.open_context_menu("Лестница вниз", "Обратно подняться будет нельзя.", options)

func _descent_blocker() -> String:
	for e: Dictionary in plan.encounters:
		if service.run.cleared_rooms.has(int(e["room"])):
			continue
		var role := plan.rooms[int(e["room"])].role
		if role == FloorPlan.ROLE_GUARDIAN or role == FloorPlan.ROLE_BOSS \
				or role == FloorPlan.ROLE_HERALD:
			return "Спуск охраняет страж этажа — сначала одолейте его"
	return ""

func _floor_survey() -> String:
	var fights := 0
	for e: Dictionary in plan.encounters:
		if not service.run.cleared_rooms.has(int(e["room"])):
			fights += 1
	var chests := 0
	var others := 0
	for i: int in plan.props.size():
		if service.run.looted_props.has(i):
			continue
		if StringName(plan.props[i].get("kind", &"")) == &"chest":
			chests += 1
		else:
			others += 1
	return "Осталось: боёв %d, ящиков %d, прочих объектов %d." % [fights, chests, others]

# --- Ящик ---

func _menu_chest(prop: Dictionary) -> void:
	var index := _prop_index()
	var locked := bool(prop.get("locked", false)) and not _chest_unlocked.has(index)
	var checked := _chest_checked.has(index)
	var options: Array = []
	if locked:
		var picker := _best_hero(Stats.DEX)
		options.append(ContextMenu.option("Вскрыть замок (ЛОВ, СЛ 15)",
			func() -> void: _pick_lock(index),
			"Лучший в отряде: %s. Неудача стоит времени факела" % _hero_name(picker)))
	options.append(ContextMenu.option("Открыть", func() -> void: _open_chest(prop),
		"Замок заперт" if locked else ("Ловушка обезврежена" if checked else "Содержимое неизвестно"),
		not locked))
	options.append(ContextMenu.option("Осмотреть замок (МДР, СЛ 13)",
		func() -> void: _inspect_chest(index),
		"Уже осмотрен" if checked else "Найти иглу до того, как она найдёт вас",
		not checked))
	hud.open_context_menu("Ящик", "Запертый ящик придётся вскрывать.", options)

func _pick_lock(index: int) -> void:
	var hero := _best_hero(Stats.DEX)
	if hero == null:
		return
	var rng := _prop_stream(&"lock", index)
	var actor := ActorBuilder.from_hero(hero, Balance.data)
	var check := Resolver.ability_check(rng, actor, Stats.DEX, 15, true)
	if bool(check["success"]):
		_chest_unlocked[index] = true
		EventBus.notify("%s вскрывает замок. %s" % [actor.display_name, check["text"]])
	else:
		service.tick_torch(20)
		EventBus.notify("Замок не поддался. %s" % check["text"])
	_menu_chest(_pending_interaction)

func _inspect_chest(index: int) -> void:
	var hero := _best_hero(Stats.WIS)
	if hero == null:
		return
	var rng := _prop_stream(&"inspect", index)
	var actor := ActorBuilder.from_hero(hero, Balance.data)
	var check := Resolver.ability_check(rng, actor, Stats.WIS, 13, true)
	if bool(check["success"]):
		_chest_checked[index] = true
		var trapped := bool(_pending_interaction.get("trapped", false))
		EventBus.notify("%s: %s" % [actor.display_name,
			"в замке была игла, она вынута" if trapped else "ловушек нет"])
	else:
		EventBus.notify("%s ничего не разглядел. %s" % [actor.display_name, check["text"]])
	_menu_chest(_pending_interaction)

func _hero_name(hero: CharacterState) -> String:
	if hero == null:
		return "никто"
	return hero.data.display_name if hero.data else String(hero.hero_id)

func _open_chest(prop: Dictionary) -> void:
	var index := int(prop["index"])
	if bool(prop.get("trapped", false)) and not _chest_checked.has(index):
		_spring_chest_trap(index)
	var rng := _prop_stream(&"loot", index)
	var table := Database.get_loot_table(StringName(prop.get("table", &"chest_common")))
	if table == null:
		return
	var modifiers := biome.loot_modifier.duplicate()
	modifiers[&"crystal_id"] = biome.crystal_id
	var blessing_mods := service.run.blessing_modifiers()
	modifiers[&"gold"] = float(modifiers.get(&"gold", 1.0)) * float(blessing_mods.get(&"gold_mult", 1.0))
	modifiers[&"ore"] = float(modifiers.get(&"ore", 1.0)) * float(blessing_mods.get(&"ore_mult", 1.0))
	_collect_loot(GameState.item_factory.roll_loot(table, service.run.floor_index, rng, modifiers))
	_spend_prop(index)

func _spring_chest_trap(index: int) -> void:
	var rng := _prop_stream(&"chest_trap", index)
	var victim: CharacterState = rng.pick(service.run.alive_party())
	if victim == null:
		return
	var damage := _hurt_hero(victim, int(Dice.roll("1d6", rng)["total"]) + service.run.floor_index)
	EventBus.notify("Игла в замке: %s получает %d урона" % [_hero_name(victim), damage])

func _collect_loot(loot: Dictionary) -> void:
	service.run.add_gold(int(loot.get("gold", 0)))
	var lines: Array[String] = ["Найдено: %d золота" % int(loot.get("gold", 0))]
	for id: Variant in (loot.get("materials", {}) as Dictionary).keys():
		var amount := int(loot["materials"][id])
		service.run.add_material(StringName(id), amount)
		var res := Database.get_item(StringName(id))
		lines.append("%s x%d" % [res.display_name if res else String(id), amount])
	for item: ItemInstance in loot.get("items", []):
		service.run.run_items.append(item)
		lines.append(item.display_name())
		EventBus.item_acquired.emit(item)
	EventBus.notify(", ".join(lines))

# --- Алтарь ---

func _menu_altar(prop: Dictionary) -> void:
	var index := int(prop.get("index", -1))
	var torches := 0
	for member: CharacterState in service.run.party:
		torches += member.inventory.count_of(&"torch")
	var options: Array = [
		ContextMenu.option("Отдохнуть", func() -> void:
			service.rest()
			_spend_prop(index), "Хиты и ячейки заклинаний восстановятся полностью"),
		ContextMenu.option("Разжечь факел от пламени алтаря", func() -> void:
			service.run.light_torch(Balance.data.torch_ticks)
			EventBus.torch_state_changed.emit(service.run.torch_ticks_left)
			EventBus.notify("Факел разгорелся от пламени алтаря — припасы целы.")
			_spend_prop(index), "Свежий факел, не тратя запас (в сумках: %d)" % torches),
	]
	hud.open_context_menu("Алтарь", "Пламя алтаря погаснет после первого же дара.", options)

# --- Ловушка ---

func _menu_trap(prop: Dictionary) -> void:
	var index := int(prop.get("index", -1))
	var dc := int(prop.get("dc", 13))
	var scout := _best_hero(Stats.DEX)
	var options: Array = [
		ContextMenu.option("Обезвредить (ЛОВ, СЛ %d)" % dc,
			func() -> void: _disarm_trap(prop),
			"Пробует %s. Провал — урон всему, кто рядом" % _hero_name(scout)),
		ContextMenu.option("Обойти стороной", func() -> void:
			_spend_prop(index)
			EventBus.notify("Отряд обходит ловушку по стенке."),
			"Безопасно, но механизм останется взведённым"),
	]
	hud.open_context_menu("Ловушка", "Механизм взведён и хорошо виден.", options)

func _disarm_trap(prop: Dictionary) -> void:
	var index := int(prop["index"])
	var dc := int(prop.get("dc", 13))
	var rng := _prop_stream(&"trap", index)
	var best := _best_hero(Stats.DEX)
	if best == null:
		return
	var actor := ActorBuilder.from_hero(best, Balance.data)
	var check := Resolver.ability_check(rng, actor, Stats.DEX, dc, true)
	_spend_prop(index)
	if bool(check["success"]):
		EventBus.notify("%s обезвредил ловушку. %s" % [actor.display_name, check["text"]])
		return
	var damage := _hurt_hero(best, int(Dice.roll("2d6", rng)["total"]) + service.run.floor_index)
	EventBus.notify("Ловушка сработала: %s получает %d урона" % [actor.display_name, damage])
	hud.refresh()

# --- Комната-событие: интерактивная сцена с выбором (04-dungeon.md, раздел 8) ---

func _menu_event(prop: Dictionary) -> void:
	var index := int(prop.get("index", -1))
	var rng := _prop_stream(&"event", index)
	var options: Array = [
		ContextMenu.option("Обыскать нишу", func() -> void:
			var gold := int(Dice.roll("4d6+10", rng)["total"])
			service.run.add_gold(gold)
			EventBus.notify("Тайник забытого рудокопа: +%d золота" % gold)
			_spend_prop(index), "Немного золота, без риска"),
		ContextMenu.option("Испить из родника", func() -> void:
			for member: CharacterState in service.run.alive_party():
				member.hp = mini(member.max_hp(Balance.data), member.hp + 8)
			EventBus.notify("Родник с чистой водой: отряд восстанавливает 8 HP")
			_spend_prop(index), "Отряд восстановит по 8 хитов"),
		ContextMenu.option("Забрать подношение", func() -> void:
			var item := GameState.item_factory.create_rolled(&"potion_greater",
				service.run.floor_index, rng)
			if item != null:
				service.run.run_items.append(item)
				EventBus.notify("В нише лежит: %s" % item.display_name())
			var toll := _best_hero(Stats.CON)
			if toll != null:
				var loss := _hurt_hero(toll, maxi(1, int(toll.hp * 0.25)), 1)
				EventBus.notify("Что-то взяло своё: %s теряет %d хитов" % [_hero_name(toll), loss])
			_spend_prop(index), "Предмет, но кто-то из отряда заплатит четвертью хитов"),
	]
	hud.open_context_menu("Старое святилище",
		"Три ниши, взять можно только из одной.", options)

# --- Врата Возврата ---

func _menu_gate() -> void:
	hud.open_context_menu("Врата Возврата",
		"Подъёмник наверх. Решение принимается один раз.", [
			ContextMenu.option("Открыть створ и решить",
				func() -> void: hud.show_extraction(service),
				"Сводка добычи и выбор: уйти или идти дальше"),
		])
func _try_descend() -> void:
	var encounter_left := false
	for e: Dictionary in plan.encounters:
		if not service.run.cleared_rooms.has(int(e["room"])):
			var room := plan.rooms[int(e["room"])]
			if room.role == FloorPlan.ROLE_GUARDIAN or room.role == FloorPlan.ROLE_BOSS \
					or room.role == FloorPlan.ROLE_HERALD:
				encounter_left = true
				break
	if encounter_left:
		EventBus.notify("Спуск охраняет страж этажа. Сначала одолейте его.")
		return
	if service.should_offer_blessing():
		hud.show_blessings(service, func() -> void: _go_next_floor())
		return
	_go_next_floor()

func _go_next_floor() -> void:
	if service.can_extract():
		hud.show_extraction(service)
		return
	if service.run.floor_index >= Balance.data.total_floors:
		hud.show_summary(service.finish(&"completed", true))
		return
	service.descend()
	if service.is_segment_start():
		hud.show_biome_fork(service, func() -> void:
			SaveSystem.save_run()
			SceneRouter.goto_dungeon("Спуск на этаж %d…" % service.run.floor_index))
		return
	SceneRouter.goto_dungeon("Спуск на этаж %d…" % service.run.floor_index)

# --- Бой ---

func _check_room_trigger() -> void:
	if mode != Mode.EXPLORE:
		return
	var cell := _current_cell()
	var room := plan.room_at(cell)
	if room == null:
		return
	if service.run.cleared_rooms.has(room.index):
		return
	var encounter := plan.encounter_for_room(room.index)
	if encounter.is_empty():
		return
	_start_combat(encounter, room)

func _start_combat(encounter: Dictionary, room: FloorPlan.Room) -> void:
	mode = Mode.COMBAT
	combat_controller = preload("res://game/scenes/dungeon/combat_controller.gd").new()
	combat_controller.name = "Combat"
	add_child(combat_controller)
	combat_controller.finished.connect(_on_combat_finished)
	combat_controller.begin(self, service, encounter, room)
	hud.set_combat(true)

func _on_combat_finished(victory: bool) -> void:
	combat_controller = null
	hud.set_combat(false)
	hud.refresh()
	if not victory or service.run.is_wiped():
		hud.show_summary(service.wipe())
		return
	mode = Mode.EXPLORE
	# Синхронизируем видимость павших героев.
	_update_followers(1.0)

func _update_camera_combat(delta: float) -> void:
	if combat_controller == null or combat_controller.state == null:
		return
	var actor: CombatActor = combat_controller.current_actor()
	var focus: Vector3 = leader.global_position
	if actor != null:
		focus = FloorBuilder.cell_to_world(actor.cell, cell_size, 0.0)
	var desired: Vector3 = focus + Vector3(0.0, 11.0, 8.0).rotated(Vector3.UP, camera_yaw)
	camera.global_position = camera.global_position.lerp(desired, clampf(delta * 4.0, 0.05, 1.0))
	camera.look_at(focus, Vector3.UP)

## Ходьба всего отряда: спутники идут следом, поэтому клип у них общий с лидером.
func _set_walking(moving: bool) -> void:
	for animator: ActorAnimator in _walk_animators:
		if is_instance_valid(animator):
			animator.set_moving(moving)

## Зелёный круг под тем, чей сейчас ход: в исследовании это лидер, в бою —
## существо, которое ходит. Остальные герои остаются с синим кругом.
func set_active_ring(actor_id: StringName) -> void:
	for i: int in _rings.size():
		if i >= service.run.party.size():
			break
		var member: CharacterState = service.run.party[i]
		_rings[i].set_active(member.hero_id == actor_id)

func ring_of_hero(index: int) -> SelectionRing3D:
	return _rings[index] if index >= 0 and index < _rings.size() else null

## Режим разработчика (F1): любая атака наносит GameState.DEV_DAMAGE. Флаг живёт
## в сессии, поэтому переживает спуск на новый этаж, но не попадает в сохранение.
## Идущий бой подхватывает переключение сразу — перезаходить не нужно.
func _toggle_dev_mode() -> void:
	GameState.dev_mode = not GameState.dev_mode
	if combat_controller != null:
		combat_controller.apply_dev_mode()
	hud.refresh()
	EventBus.notify("Режим разработчика %s." % ("включён" if GameState.dev_mode else "выключен"))
	Log.info("dev_mode=%s" % GameState.dev_mode)

## Урон герою вне боя: ловушки, иглы в замках, плата за находку. В режиме
## разработчика отряд бессмертен, и гасить урон надо здесь тоже — в бою за это
## отвечает CombatActor.invulnerable, но сюда бой не заходит.
## floor_hp — нижняя граница здоровья: у платы за находку она равна 1, такой
## урон не убивает и без всякого режима. Возвращает урон, который реально прошёл.
func _hurt_hero(victim: CharacterState, damage: int, floor_hp: int = 0) -> int:
	if victim == null or GameState.dev_mode:
		return 0
	victim.hp = maxi(floor_hp, victim.hp - damage)
	if victim.hp <= 0:
		victim.is_dead_this_run = true
	return damage
