extends Node
## Боевой контроллер: строит CombatState из встречи, показывает её на сетке и
## проигрывает ActionResult. Правил не содержит — они в core/combat.

signal finished(victory: bool)

const AI_DELAY := 0.35

var run_scene: Node3D
var service: RunService
var state: CombatState
var engine: CombatEngine
var room: FloorPlan.Room
var cell_size: float = 1.5
var ui: Control
var markers: Node3D
var enemy_nodes: Dictionary = {}      # actor_id -> Node3D
var health_bars: Dictionary = {}      # actor_id -> HealthBar3D
var animators: Dictionary = {}        # actor_id -> ActorAnimator
var _fill_light: OmniLight3D
var _saved_ambient: float = -1.0
var hero_nodes: Dictionary = {}       # actor_id -> Node3D
var reachable_cells: Dictionary = {}
var targeting: StringName = &"none"   # none | spell | ability | help | shove | stabilize
var targeting_payload: Variant = null
var _busy: bool = false
var _speed_multiplier: float = 1.5

func begin(scene: Node3D, run_service: RunService, encounter: Dictionary,
		combat_room: FloorPlan.Room) -> void:
	run_scene = scene
	service = run_service
	room = combat_room
	cell_size = Balance.data.grid_cell_size
	_build_state(encounter)
	_build_visuals()
	_build_ui()
	engine = CombatEngine.new(state)
	engine.turn_started.connect(_on_turn_started)
	engine.action_resolved.connect(_on_action_resolved)
	engine.combat_ended.connect(_on_combat_ended)
	engine.round_started.connect(func(n: int) -> void: ui.set_round(n))
	EventBus.combat_started.emit(state)
	engine.start()

func _build_state(encounter: Dictionary) -> void:
	var plan: FloorPlan = run_scene.plan
	state = CombatState.new()
	state.balance = Balance.data
	state.status_db = Database.status_map()
	state.spell_db = Database.spell_map()
	service.run.combat_index += 1
	state.combat_index = service.run.combat_index
	state.rng = service.run.stream(&"combat", service.run.combat_index)
	var area := room.rect.grow(1)
	state.grid = plan.build_combat_grid(area)
	state.light = LightService.new(state.grid, Balance.data.light_bright_cells,
		Balance.data.light_dim_cells)
	var free := plan.floor_cells_in(room.rect)
	var run_mods := service.run.blessing_modifiers()
	var index := 0
	for member: CharacterState in service.run.party:
		if member.is_dead_this_run:
			continue
		var actor := ActorBuilder.from_hero(member, Balance.data, run_mods)
		state.add_actor(actor)
		actor.cell = _closest_free(free, run_scene._current_cell(), actor)
		index += 1
	var enemy_index := 0
	var elites: Array = encounter.get("elites", [])
	for enemy_id: StringName in encounter.get("enemies", []):
		var data := Database.get_enemy(enemy_id)
		if data == null:
			continue
		var is_elite: bool = elites.has(enemy_id) and enemy_index == 0
		var actor := ActorBuilder.from_enemy(data, enemy_index, Balance.data, is_elite,
			service.run.floor_index)
		state.add_actor(actor)
		actor.cell = _closest_free(free, room.center(), actor)
		enemy_index += 1
		if data.is_boss:
			service.run.stats["bosses"] = int(service.run.stats.get("bosses", 0)) + 1
	if service.run.torch_lit:
		state.light.add_source(state.team_actors(CombatActor.TEAM_PARTY)[0].cell)

## Ближайшая свободная клетка к якорю — простое, но детерминированное размещение.
func _closest_free(free: Array[Vector2i], anchor: Vector2i, actor: CombatActor) -> Vector2i:
	var sorted := free.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return CombatGrid.distance(a, anchor) < CombatGrid.distance(b, anchor))
	for cell: Vector2i in sorted:
		if state.can_occupy(actor, cell):
			return cell
	# Свободных клеток в комнате не осталось — ищем любую свободную на этаже.
	for y: int in state.grid.height:
		for x: int in state.grid.width:
			var cell := Vector2i(x, y)
			if state.can_occupy(actor, cell):
				return cell
	return anchor

func _build_visuals() -> void:
	markers = Node3D.new()
	markers.name = "CombatMarkers"
	run_scene.add_child(markers)
	_add_fill_light()
	for actor: CombatActor in state.all_actors():
		if actor.team == CombatActor.TEAM_ENEMY:
			var data := Database.get_enemy(actor.source_id)
			var elite := actor.display_name.begins_with("Элитный")
			var node := ActorModel.build_enemy(data, elite, actor.tint)
			node.position = FloorBuilder.cell_to_world(actor.cell, cell_size, 0.0)
			run_scene.add_child(node)
			enemy_nodes[actor.id] = node
			_attach_health_bar(actor, node)
			animators[actor.id] = ActorAnimator.attach(node)
	var i := 0
	for actor: CombatActor in state.team_actors(CombatActor.TEAM_PARTY):
		if i < run_scene.party_nodes.size():
			var node: Node3D = run_scene.party_nodes[i]
			node.global_position = FloorBuilder.cell_to_world(actor.cell, cell_size, 0.0)
			hero_nodes[actor.id] = node
			_attach_health_bar(actor, node)
			animators[actor.id] = ActorAnimator.attach(node)
		i += 1

func _build_ui() -> void:
	ui = preload("res://game/ui/combat_ui.gd").new()
	var layer := CanvasLayer.new()
	layer.name = "CombatUI"
	layer.layer = 5
	add_child(layer)
	layer.add_child(ui)
	ui.setup(self)

# --- Ход ---

func _on_turn_started(actor_id: StringName) -> void:
	var actor := state.get_actor(actor_id)
	if actor == null:
		return
	EventBus.turn_started.emit(actor_id)
	ui.set_active_actor(actor)
	_refresh_reachable(actor)
	if actor.team == CombatActor.TEAM_ENEMY:
		_run_ai_turn(actor)

func _refresh_reachable(actor: CombatActor) -> void:
	reachable_cells = MoveAction.reachable(state, actor) if actor.team == CombatActor.TEAM_PARTY else {}
	ui.set_reachable(reachable_cells.size())
	_draw_reachable()

func _run_ai_turn(actor: CombatActor) -> void:
	_busy = true
	var plan := UtilityAI.plan_turn(state, actor)
	for step: Dictionary in plan:
		if state.phase == CombatState.PHASE_ENDED:
			break
		await run_scene.get_tree().create_timer(AI_DELAY / _speed_multiplier).timeout
		match String(step.get("kind", "")):
			"move":
				engine.submit(MoveAction.resolve(state, actor, step["cell"]))
			"attack":
				engine.submit(AttackAction.resolve(state, actor, step["target"], step["attack"]))
	_busy = false
	if state.phase != CombatState.PHASE_ENDED:
		await run_scene.get_tree().create_timer(AI_DELAY / _speed_multiplier).timeout
		engine.end_turn()

func end_turn() -> void:
	if _busy:
		return
	engine.end_turn()

# --- Отображение результата ---

func _on_action_resolved(result: ActionResult) -> void:
	EventBus.action_resolved.emit(result)
	_play_action_animation(result)
	for line: String in result.log_lines:
		ui.append_log(line)
		EventBus.combat_log_appended.emit(line)
	if not result.movement.is_empty():
		var actor := state.get_actor(result.actor_id)
		if actor != null:
			_move_node(actor)
	for event: Dictionary in result.damage_events:
		var target_id := StringName(event.get("target", ""))
		EventBus.damage_dealt.emit(target_id, int(event.get("amount", 0)),
			StringName(event.get("type", "")), bool(event.get("crit", false)))
		var best := int(service.run.stats.get("best_hit", 0))
		service.run.stats["best_hit"] = maxi(best, int(event.get("amount", 0)))
		if bool(event.get("killed", false)):
			_on_actor_killed(target_id)
	for event: Dictionary in result.status_events:
		if bool(event.get("applied", false)):
			EventBus.status_applied.emit(StringName(event.get("target", "")),
				StringName(event.get("status", "")), int(event.get("stacks", 1)))
	_refresh_health_bars()
	ui.refresh()
	var actor := state.current_actor()
	if actor != null and actor.team == CombatActor.TEAM_PARTY:
		_refresh_reachable(actor)

func _move_node(actor: CombatActor) -> void:
	var node: Node3D = hero_nodes.get(actor.id, enemy_nodes.get(actor.id, null))
	if node == null:
		return
	var target := FloorBuilder.cell_to_world(actor.cell, cell_size, node.global_position.y)
	var duration := 0.25 / _speed_multiplier
	var walker := _animator(actor.id)
	if walker != null:
		walker.speed = _speed_multiplier
		walker.face(target)
		walker.play_step(duration)
	var tween := create_tween()
	tween.tween_property(node, "global_position", target, duration)

func _on_actor_killed(actor_id: StringName) -> void:
	EventBus.actor_died.emit(actor_id)
	var actor := state.get_actor(actor_id)
	if actor == null:
		return
	if actor.team == CombatActor.TEAM_ENEMY:
		service.run.stats["kills"] = int(service.run.stats.get("kills", 0)) + 1
		_drop_loot(actor)
		var node: Node3D = enemy_nodes.get(actor_id, null)
		if node != null:
			node.queue_free()
			enemy_nodes.erase(actor_id)
		health_bars.erase(actor_id)
	else:
		var member := service.run.member(actor.source_id)
		if member != null:
			member.is_dead_this_run = true
		ui.append_log("%s погибает. Отряд продолжает спуск." % actor.display_name)

func _drop_loot(actor: CombatActor) -> void:
	var table := Database.get_loot_table(actor.loot_table)
	if table == null:
		return
	var rng := service.run.stream(&"loot", "%d_%s" % [service.run.floor_index, actor.id])
	var modifiers: Dictionary = (Database.get_biome(service.run.current_biome)).loot_modifier.duplicate()
	modifiers[&"crystal_id"] = Database.get_biome(service.run.current_biome).crystal_id
	var blessing_mods := service.run.blessing_modifiers()
	modifiers[&"gold"] = float(modifiers.get(&"gold", 1.0)) * float(blessing_mods.get(&"gold_mult", 1.0))
	var loot := GameState.item_factory.roll_loot(table, service.run.floor_index, rng, modifiers)
	run_scene._collect_loot(loot)

func _on_combat_ended(victory: bool) -> void:
	EventBus.combat_ended.emit(victory)
	_sync_party_state()
	if victory:
		service.run.cleared_rooms.append(room.index)
		if run_scene.minimap != null:
			run_scene.minimap.refresh()
		service.run.stats["rooms_cleared"] = int(service.run.stats.get("rooms_cleared", 0)) + 1
		ui.append_log("Бой окончен. Победа.")
	else:
		ui.append_log("Отряд пал.")
	# Бой длится в тиках факела: раунд = 6 тиков (02-combat.md, раздел 8.2).
	service.tick_torch(state.round_number * Balance.data.round_duration_sec)
	await run_scene.get_tree().create_timer(1.0).timeout
	_teardown()
	finished.emit(victory)

## Переносим результат боя обратно в постоянное состояние героев.
func _sync_party_state() -> void:
	for actor: CombatActor in state.team_actors(CombatActor.TEAM_PARTY, false):
		var member := service.run.member(actor.source_id)
		if member == null:
			continue
		member.hp = actor.hp
		member.spell_slots = actor.spell_slots.duplicate()
		member.is_dead_this_run = actor.is_dead

func _teardown() -> void:
	_remove_fill_light()
	# Полоски героев висят на постоянных моделях отряда — снимаем их вручную.
	for bar: Variant in health_bars.values():
		if is_instance_valid(bar):
			(bar as Node).queue_free()
	health_bars.clear()
	# Аниматоры героев живут на постоянных моделях — снимаем и возвращаем позу.
	for id: Variant in hero_nodes.keys():
		var node: Node3D = hero_nodes[id]
		if is_instance_valid(node):
			node.rotation = Vector3.ZERO
	for animator: Variant in animators.values():
		if is_instance_valid(animator):
			(animator as Node).queue_free()
	animators.clear()
	for node: Node3D in enemy_nodes.values():
		node.queue_free()
	enemy_nodes.clear()
	health_bars.clear()
	if markers != null:
		markers.queue_free()
	if ui != null:
		ui.get_parent().queue_free()
	queue_free()

# --- Ввод игрока ---

func current_actor() -> CombatActor:
	return state.current_actor() if state != null else null

func is_player_turn() -> bool:
	var actor := current_actor()
	return actor != null and actor.team == CombatActor.TEAM_PARTY and not _busy

func handle_click(right_button: bool) -> void:
	if not is_player_turn():
		return
	var cell := cell_under_mouse()
	var actor := current_actor()
	var target := state.actor_at(cell)
	if right_button:
		if targeting != &"none":
			targeting = &"none"
			targeting_payload = null
			ui.set_hint("")
			ui.refresh()
			return
		# ПКМ по актёру — меню всех действий, применимых именно к нему.
		if target != null:
			open_target_menu(target)
		return
	match targeting:
		&"spell":
			_cast(targeting_payload as SpellData, cell)
		&"ability":
			_ability(targeting_payload as AbilityData, target)
		&"help":
			if target != null:
				_submit(SimpleActions.help(actor, target))
		&"shove":
			if target != null:
				_submit(SimpleActions.shove(state, actor, target))
		&"stabilize":
			if target != null:
				_submit(SimpleActions.stabilize(state, actor, target))
		_:
			if target != null and target.team != actor.team:
				attack(target)
			elif reachable_cells.has(cell):
				_submit(MoveAction.resolve(state, actor, cell))
	targeting = &"none"
	targeting_payload = null

func cell_under_mouse() -> Vector2i:
	var cam: Camera3D = run_scene.camera
	var mouse := run_scene.get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return Vector2i(-999, -999)
	var hit := from + dir * (-from.y / dir.y)
	return FloorBuilder.world_to_cell(hit, cell_size)

func attack(target: CombatActor) -> void:
	var actor := current_actor()
	if actor == null or actor.attacks.is_empty():
		return
	_submit(AttackAction.resolve(state, actor, target, actor.attacks[0]))

func _cast(spell: SpellData, cell: Vector2i) -> void:
	if spell == null:
		return
	_submit(SpellAction.resolve(state, current_actor(), spell, cell))

func _ability(ability: AbilityData, target: CombatActor) -> void:
	if ability == null:
		return
	_submit(AbilityAction.resolve(state, current_actor(), ability, target))

func simple_action(id: StringName) -> void:
	var actor := current_actor()
	if actor == null:
		return
	match id:
		&"dash": _submit(SimpleActions.dash(actor))
		&"dodge": _submit(SimpleActions.dodge(actor))
		&"disengage": _submit(SimpleActions.disengage(actor))
		&"help", &"shove", &"stabilize":
			targeting = id
			ui.set_hint("Выберите цель для действия «%s»" % id)

func use_item(item: ItemInstance, target: CombatActor) -> void:
	var actor := current_actor()
	if actor == null or item == null or not (item.data is ConsumableData):
		return
	var result := SimpleActions.use_consumable(state, actor, target if target else actor,
		item.data as ConsumableData)
	if result.ok:
		var member := service.run.member(actor.source_id)
		if member != null:
			member.inventory.take(item.id(), 1)
	_submit(result)

func begin_spell_targeting(spell: SpellData) -> void:
	targeting = &"spell"
	targeting_payload = spell
	ui.set_hint("Куда направить «%s»? ПКМ — отмена" % spell.display_name)

func begin_ability_targeting(ability: AbilityData) -> void:
	if ability.target_kind == &"self" or ability.target_kind == &"none":
		_ability(ability, current_actor())
		return
	targeting = &"ability"
	targeting_payload = ability
	ui.set_hint("Выберите цель для «%s». ПКМ — отмена" % ability.display_name)

func _submit(result: ActionResult) -> void:
	if result == null:
		return
	if not result.ok:
		ui.set_hint(result.error)
		return
	engine.submit(result)
	ui.set_hint("")

# --- Подсветка достижимых клеток ---

func _draw_reachable() -> void:
	if markers == null:
		return
	for child: Node in markers.get_children():
		child.queue_free()
	if reachable_cells.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cell_size * 0.85, 0.02, cell_size * 0.85)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var cells: Array = reachable_cells.keys()
	mm.instance_count = cells.size()
	for i: int in cells.size():
		mm.set_instance_transform(i,
			Transform3D(Basis(), FloorBuilder.cell_to_world(cells[i], cell_size, 0.06)))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.75, 0.95, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	markers.add_child(node)

func set_speed_multiplier(value: float) -> void:
	_speed_multiplier = clampf(value, 0.5, 3.0)

# --- Меню действий по конкретной цели ---
# Собирается из состояния актёра и данных: оружие, заклинания, способности,
# расходники. Недоступные пункты показываются с причиной, а не прячутся.

func open_target_menu(target: CombatActor) -> void:
	var actor := current_actor()
	if actor == null:
		return
	var options: Array = []
	if target.team != actor.team:
		_add_attack_options(actor, target, options)
	else:
		_add_support_options(actor, target, options)
	_add_spell_options(actor, target, options)
	_add_ability_options(actor, target, options)
	if target.id == actor.id:
		_add_self_options(actor, options)
	var subtitle := "HP %d/%d · КБ %d · дистанция %d кл." % [target.hp, target.effective_max_hp(),
		target.effective_ac(), CombatGrid.distance(actor.cell, target.cell)]
	if not target.statuses.is_empty():
		var names: Array[String] = []
		for s: StatusEffect in target.statuses:
			names.append(s.data.display_name)
		subtitle += "\nЭффекты: " + ", ".join(names)
	ui.open_context_menu(target.display_name, subtitle, options)

func _add_attack_options(actor: CombatActor, target: CombatActor, options: Array) -> void:
	var distance := CombatGrid.distance(actor.cell, target.cell)
	for attack: AttackData in actor.attacks:
		var reachable := distance <= attack.range_cells
		var reason := ""
		if actor.action_left <= 0:
			reason = "Действие уже потрачено"
		elif not reachable:
			reason = "Далеко: нужно %d кл., сейчас %d" % [attack.range_cells, distance]
		else:
			var mode: int = AttackAction.compute_mode(state, actor, target, attack)["mode"]
			reason = "%s урона%s" % [attack.damage_dice, Resolver.mode_text(mode)]
		options.append(ContextMenu.option("Атака: %s" % attack.display_name,
			func() -> void: _submit(AttackAction.resolve(state, actor, target, attack)),
			reason, reachable and actor.action_left > 0))
	var adjacent := distance <= 1
	options.append(ContextMenu.option("Толчок",
		func() -> void: _submit(SimpleActions.shove(state, actor, target)),
		"Состязание СИЛ: сдвинуть на клетку" if adjacent else "Цель не вплотную",
		adjacent and actor.action_left > 0))

func _add_support_options(actor: CombatActor, target: CombatActor, options: Array) -> void:
	var adjacent := CombatGrid.distance(actor.cell, target.cell) <= 1
	if target.id != actor.id:
		options.append(ContextMenu.option("Помощь",
			func() -> void: _submit(SimpleActions.help(actor, target)),
			"Преимущество на следующую атаку союзника" if adjacent else "Союзник не рядом",
			adjacent and actor.action_left > 0))
	if target.is_down:
		options.append(ContextMenu.option("Стабилизировать",
			func() -> void: _submit(SimpleActions.stabilize(state, actor, target)),
			"Проверка МДР СЛ %d" % Balance.data.death_save_dc if adjacent else "Цель не рядом",
			adjacent and actor.action_left > 0))
	_add_consumable_options(actor, target, options)

func _add_consumable_options(actor: CombatActor, target: CombatActor, options: Array) -> void:
	var member: CharacterState = service.run.member(actor.source_id)
	if member == null or member.inventory == null:
		return
	if CombatGrid.distance(actor.cell, target.cell) > 1:
		return
	for item: ItemInstance in member.inventory.items():
		if not (item.data is ConsumableData):
			continue
		var data: ConsumableData = item.data
		if data.effect == &"torch":
			continue
		var free := data.use_time == &"action" and actor.action_left > 0 \
			or data.use_time == &"bonus" and actor.bonus_left > 0 or data.use_time == &"free"
		options.append(ContextMenu.option("%s x%d" % [item.display_name(), item.quantity],
			func() -> void: use_item(item, target),
			data.description if not data.description.is_empty() else "Расходник",
			free))

func _add_spell_options(actor: CombatActor, target: CombatActor, options: Array) -> void:
	var distance := CombatGrid.distance(actor.cell, target.cell)
	for spell_id: StringName in actor.spells:
		var spell := Database.get_spell(spell_id)
		if spell == null or spell.level > Balance.data.max_spell_level:
			continue
		if spell.target_team == &"enemy" and target.team == actor.team:
			continue
		if spell.target_team == &"ally" and target.team != actor.team:
			continue
		if spell.target_team == &"self" and target.id != actor.id:
			continue
		var reason := ""
		var ready := true
		if not SpellAction.has_slot(actor, spell.level):
			reason = "Нет свободной ячейки %d уровня" % spell.level
			ready = false
		elif distance > spell.range_cells:
			reason = "Далеко: дальность %d кл." % spell.range_cells
			ready = false
		elif spell.cast_time == &"action" and actor.action_left <= 0:
			reason = "Действие уже потрачено"
			ready = false
		else:
			reason = spell.description if not spell.description.is_empty() else "Заклинание"
		options.append(ContextMenu.option("Заклинание: %s" % spell.display_name,
			func() -> void: _cast(spell, target.cell), reason, ready))

func _add_ability_options(actor: CombatActor, target: CombatActor, options: Array) -> void:
	for ability_id: StringName in actor.abilities:
		var ability := Database.get_ability(ability_id)
		if ability == null:
			continue
		var wants_enemy := ability.target_kind == &"enemy"
		var wants_ally := ability.target_kind == &"ally"
		if wants_enemy and target.team == actor.team:
			continue
		if wants_ally and target.team != actor.team:
			continue
		if ability.target_kind == &"self" and target.id != actor.id:
			continue
		var left := AbilityAction.uses_left(actor, ability)
		var in_range := CombatGrid.distance(actor.cell, target.cell) <= maxi(1, ability.range_cells)
		var reason := ability.description
		var ready := left > 0 and in_range
		if left <= 0:
			reason = "Израсходовано до отдыха"
		elif not in_range:
			reason = "Далеко: дальность %d кл." % ability.range_cells
		options.append(ContextMenu.option("Способность: %s" % ability.display_name,
			func() -> void: _ability(ability, target), reason, ready))

func _add_self_options(actor: CombatActor, options: Array) -> void:
	options.append(ContextMenu.option("Уклонение",
		func() -> void: simple_action(&"dodge"),
		"Атаки по вам с помехой до следующего хода", actor.action_left > 0))
	options.append(ContextMenu.option("Рывок",
		func() -> void: simple_action(&"dash"),
		"Удвоить движение на этот ход", actor.action_left > 0))
	options.append(ContextMenu.option("Отход",
		func() -> void: simple_action(&"disengage"),
		"Движение не провоцирует атак", actor.action_left > 0))
	options.append(ContextMenu.option("Конец хода", func() -> void: end_turn(),
		"Передать ход следующему в ленте инициативы"))

# --- Шкалы здоровья над врагами ---

## Полоска висит над моделью и обновляется после каждого разрешённого действия.
func _attach_health_bar(actor: CombatActor, node: Node3D) -> void:
	var height := 1.8 + 0.45 * float(maxi(0, actor.size_cells - 1))
	# У героев над головой хватит имени без фамилии: полное имя есть в панели отряда.
	var label: String = actor.display_name
	if actor.team == CombatActor.TEAM_PARTY:
		label = actor.display_name.split(" ")[0]
	var bar := HealthBar3D.create(label, actor.effective_max_hp(),
		HealthBar3D.WIDTH * (1.0 + 0.25 * float(maxi(0, actor.size_cells - 1))))
	node.add_child(bar)
	# Модель из кита может быть отмасштабирована подгонкой роста — полоска не
	# должна её наследовать, иначе становится гигантской или исчезает.
	var factor: float = maxf(0.0001, node.scale.y)
	bar.scale = Vector3.ONE / factor
	bar.position = Vector3(0.0, height / factor, 0.0)
	health_bars[actor.id] = bar

func _refresh_health_bars() -> void:
	for actor_id: StringName in health_bars.keys():
		var actor := state.get_actor(actor_id)
		var bar: HealthBar3D = health_bars[actor_id]
		if actor == null or not is_instance_valid(bar):
			continue
		bar.set_hp(actor.hp)

## Заполняющий свет тактического режима (02-combat.md, раздел 2.1): без него
## на сером блокинге в темноте не видно ни моделей, ни сетки.
func _add_fill_light() -> void:
	var center := FloorBuilder.cell_to_world(room.center(), cell_size, 0.0)
	var extent := maxf(float(room.rect.size.x), float(room.rect.size.y)) * cell_size
	_fill_light = OmniLight3D.new()
	_fill_light.position = center + Vector3(0.0, extent * 0.8 + 4.0, 0.0)
	_fill_light.light_color = Color(0.86, 0.88, 1.0)
	_fill_light.light_energy = 3.2
	_fill_light.omni_range = extent * 2.2 + 12.0
	_fill_light.omni_attenuation = 0.6
	_fill_light.shadow_enabled = false
	run_scene.add_child(_fill_light)
	var environment: WorldEnvironment = run_scene.get("environment")
	if environment != null:
		_saved_ambient = environment.environment.ambient_light_energy
		environment.environment.ambient_light_energy = _saved_ambient + 1.6

func _remove_fill_light() -> void:
	if _fill_light != null:
		_fill_light.queue_free()
		_fill_light = null
	var environment: WorldEnvironment = run_scene.get("environment") if run_scene != null else null
	if environment != null and _saved_ambient >= 0.0:
		environment.environment.ambient_light_energy = _saved_ambient
		_saved_ambient = -1.0

# --- Анимации действий ---
# Движок уже разрешил действие, здесь только показ результата.

func _animator(actor_id: StringName) -> ActorAnimator:
	var animator: Variant = animators.get(actor_id, null)
	return animator if animator is ActorAnimator and is_instance_valid(animator) else null

func _node_of(actor_id: StringName) -> Node3D:
	var node: Variant = hero_nodes.get(actor_id, enemy_nodes.get(actor_id, null))
	return node if node is Node3D and is_instance_valid(node) else null

func _play_action_animation(result: ActionResult) -> void:
	var actor_animator := _animator(result.actor_id)
	if actor_animator == null:
		return
	actor_animator.speed = _speed_multiplier
	var target_node: Node3D = null
	if not result.targets.is_empty():
		target_node = _node_of(result.targets[0])
	var aim: Vector3 = target_node.global_position if target_node != null \
		else _node_of(result.actor_id).global_position
	var spell := Database.get_spell(result.action_id)
	if spell != null:
		actor_animator.play_cast(aim, _spell_color(spell))
	elif result.action_id == &"attack" or not result.damage_events.is_empty():
		var crit := false
		for event: Dictionary in result.damage_events:
			crit = crit or bool(event.get("crit", false))
		actor_animator.play_attack(aim, crit)
	for event: Dictionary in result.damage_events:
		var victim := StringName(event.get("target", ""))
		var victim_animator := _animator(victim)
		if victim_animator == null or int(event.get("amount", 0)) <= 0:
			continue
		victim_animator.speed = _speed_multiplier
		if bool(event.get("killed", false)):
			victim_animator.play_die()
		else:
			victim_animator.play_hurt()

static func _spell_color(spell: SpellData) -> Color:
	match spell.damage_type:
		&"fire": return Color(1.0, 0.55, 0.2)
		&"cold": return Color(0.55, 0.8, 1.0)
		&"lightning": return Color(0.75, 0.8, 1.0)
		&"poison", &"acid": return Color(0.55, 0.9, 0.4)
		&"necrotic": return Color(0.6, 0.35, 0.75)
		&"radiant": return Color(1.0, 0.94, 0.7)
	return Color(0.7, 0.75, 1.0) if spell.heal_dice.is_empty() else Color(0.5, 1.0, 0.6)
