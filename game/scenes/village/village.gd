extends Node3D
## Хаб от первого лица: дом основного героя и постройки вокруг
## (06-hub.md). Камера — 1-е лицо, как требует ТЗ.

const MOVE_SPEED := 4.0
const MOUSE_SENSITIVITY := 0.0025
const INTERACT_RANGE := 3.6
const PLAYER_RADIUS := 0.45
const YARD_LIMIT := 33.0
const BODY_HEIGHT := 1.8
const SPRINT_FACTOR := 1.9
const GRAVITY := 24.0
const JUMP_SPEED := 5.4
const CROUCH_HEIGHT := 1.05
const CROUCH_FACTOR := 0.45

## Планировка деревни. Постройки стоят вдоль улицы, а не по кругу пустого поля:
## так двор читается как поселение, и между домами появляются перспективы.
## Река режет двор с юга, поэтому вход в деревню идёт через мост.
const SPAWN := Vector2(0.0, 31.0)
const BRIDGE_SOUTH := Vector2(0.0, 27.0)
const BRIDGE_NORTH := Vector2(0.0, 9.0)

const PLACES := {
	&"garden": Vector2(-17.0, 4.0),
	&"storage": Vector2(16.0, 4.0),
	&"forge": Vector2(-14.0, -10.0),
	&"shop": Vector2(14.0, -10.0),
	&"training": Vector2(-12.0, -23.0),
	&"descend": Vector2(0.0, -29.0),
}
const CHAPEL_CENTER := Vector2(16.0, -22.0)

## Площадка под постройку: внутри — ровно, снаружи — плавный съезд к рельефу.
const PAD_RADIUS := 7.0
const PAD_BLEND := 5.0

var camera: Camera3D
var player: CharacterBody3D
var pitch: float = 0.0
var ui: Control
var look: VillageLook
var stations: Array[Dictionary] = []
var _blockers: Array[Rect2] = []
var _focused: Dictionary = {}
var _mouse_captured: bool = false
var _capsule: CapsuleShape3D
var _crouching := false
var _roads: Array = []

func _ready() -> void:
	if GameState.profile == null:
		GameState.new_profile(&"hald")
	var started := Time.get_ticks_msec()
	_build_world()
	_build_stations()
	_build_roads()
	# Обстановка идёт последней: ей нужны и препятствия от построек, и линии улиц.
	VillageDressing.new(look, _blockers, _roads, PLACES).dress()
	# Материалы правим после того, как всё построено: пройтись надо по готовой сцене.
	VillageLook.polish_materials(self)
	_build_ui()
	_capture_mouse(true)
	if "--shots" in OS.get_cmdline_user_args():
		_capture_shots()
		return
	Log.debug("perf village_build: %d мс" % (Time.get_ticks_msec() - started))
	EventBus.notify("День %d в деревне. WASD — идти, Shift — бег, Ctrl — присед, пробел — прыжок, E — взаимодействие, Esc — курсор." % GameState.profile.day)

func _build_world() -> void:
	look = VillageLook.new(self, YARD_LIMIT)
	# Площадки выравниваются до генерации рельефа: дом, поставленный на склон,
	# повис бы одним углом в воздухе.
	for place: Vector2 in PLACES.values():
		look.add_pad(place, PAD_RADIUS, PAD_BLEND)
	look.add_pad(CHAPEL_CENTER, PAD_RADIUS, PAD_BLEND)
	# Коридоры улиц врезаются до генерации меша: положить дорогу на готовый
	# рельеф — значит получить ленту, идущую волнами по холмам.
	_roads = _street_lines()
	for line: PackedVector2Array in _roads:
		look.add_path(line, 5.0, 4.5)
	# Небо, свет, ландшафт, река, ограда и лес — в VillageLook.
	look.build()
	_build_chapel()
	# Игрок — CharacterBody3D с капсулой: прямоугольники-препятствия описывали
	# постройки лишь приблизительно, и сквозь стены можно было пройти. Теперь
	# столкновения считает физика по настоящей геометрии.
	player = CharacterBody3D.new()
	player.position = look.ground(SPAWN) + Vector3(0.0, BODY_HEIGHT * 0.5, 0.0)
	player.floor_max_angle = deg_to_rad(50.0)
	player.floor_snap_length = 0.6
	var hull := CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.38
	_capsule.height = BODY_HEIGHT
	hull.shape = _capsule
	player.add_child(hull)
	add_child(player)
	camera = Camera3D.new()
	# Глаза чуть ниже макушки капсулы.
	camera.position = Vector3(0.0, BODY_HEIGHT * 0.5 - 0.18, 0.0)
	camera.fov = 75.0
	camera.far = 900.0
	player.add_child(camera)

## blocking=true добавляет коробку в список препятствий. Список остался для
## расстановки обстановки — по нему VillageDressing ищет свободные места;
## столкновения игрока считает физика.
func _box(size: Vector3, pos: Vector3, color: Color, blocking: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	node.material_override = mat
	add_child(node)
	if blocking:
		_blockers.append(Rect2(
			pos.x - size.x * 0.5 - PLAYER_RADIUS, pos.z - size.z * 0.5 - PLAYER_RADIUS,
			size.x + PLAYER_RADIUS * 2.0, size.z + PLAYER_RADIUS * 2.0))
	return node

## Постройки, а не тумбы: каждый объект собирается VillageProps и отдаёт точку,
## у которой игрок с ним взаимодействует. Стоят они вдоль улицы, и высоту берут
## с выровненной площадки — на рельефе фундамент иначе повиснет.
func _build_stations() -> void:
	var props := VillageProps.new(self, PLAYER_RADIUS)
	var defs: Array[Dictionary] = [
		{"id": &"forge", "name": "Кузница",
			"pos": props.build_forge(look.ground(PLACES[&"forge"]))},
		{"id": &"training", "name": "Тренировочный зал",
			"pos": props.build_training(look.ground(PLACES[&"training"]))},
		{"id": &"shop", "name": "Лавка",
			"pos": props.build_shop(look.ground(PLACES[&"shop"]))},
		{"id": &"garden", "name": "Сад",
			"pos": props.build_garden(look.ground(PLACES[&"garden"]))},
		{"id": &"storage", "name": "Склад",
			"pos": props.build_storage(look.ground(PLACES[&"storage"]))},
		{"id": &"descend", "name": "Спуск в Разлом",
			"pos": props.build_descend(look.ground(PLACES[&"descend"]))},
		{"id": &"altar", "name": "Алтарь",
			"pos": look.ground(CHAPEL_CENTER + Vector2(0.0, 0.4)) + Vector3(0.0, 0.9, 0.0)},
	]
	_blockers.append_array(props.blockers)
	for def: Dictionary in defs:
		var node := Node3D.new()
		node.position = def["pos"]
		node.name = String(def["name"])
		add_child(node)
		var entry := def.duplicate()
		entry["node"] = node
		stations.append(entry)
		var label := Label3D.new()
		label.text = String(def["name"])
		label.font_size = 64
		label.pixel_size = 0.008
		label.position = def["pos"] + Vector3(0.0, 2.2, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 12
		label.outline_modulate = Color(0.03, 0.03, 0.04)
		add_child(label)

## Улицы: главная идёт с юга на север через мост, от неё отходят подъезды к
## постройкам. Линии нужны и дорожному покрытию, и обстановке — фонари с
## лотками расставляются относительно них.
## Линии улиц. Нужны дважды и раньше рельефа: сначала по ним врезаются коридоры
## в ландшафт, потом по ним же кладётся мостовая и расставляется обстановка.
func _street_lines() -> Array:
	return [
		PackedVector2Array([Vector2(0.0, 32.5), BRIDGE_SOUTH]),
		PackedVector2Array([BRIDGE_NORTH, Vector2(0.0, 2.0), Vector2(1.0, -8.0),
			Vector2(0.0, -18.0), Vector2(0.0, -27.0)]),
		PackedVector2Array([Vector2(0.0, 4.0), Vector2(-8.0, 4.5), PLACES[&"garden"]]),
		PackedVector2Array([Vector2(0.0, 4.0), Vector2(8.0, 4.5), PLACES[&"storage"]]),
		PackedVector2Array([Vector2(0.5, -8.0), Vector2(-7.0, -9.5), PLACES[&"forge"]]),
		PackedVector2Array([Vector2(0.5, -8.0), Vector2(7.0, -9.5), PLACES[&"shop"]]),
		PackedVector2Array([Vector2(0.0, -18.0), Vector2(-7.0, -21.0), PLACES[&"training"]]),
		PackedVector2Array([Vector2(0.0, -18.0), Vector2(8.0, -21.0), CHAPEL_CENTER]),
	]


func _build_roads() -> void:
	for line: PackedVector2Array in _roads:
		look.build_road(line, 4.2 if line.size() > 2 else 3.6)
	look.build_bridge(BRIDGE_SOUTH, BRIDGE_NORTH, 3.2)

func _build_ui() -> void:
	ui = preload("res://game/ui/village_ui.gd").new()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(ui)
	ui.setup(self)

## Движение через физику: скорость задаём сами, столкновения и уклоны считает
## move_and_slide. Гравитация нужна, чтобы сходить по склонам и с моста.
func _physics_process(delta: float) -> void:
	if ui == null or ui.has_modal():
		return
	_apply_stance(delta)
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	var speed := MOVE_SPEED
	if _crouching:
		speed *= CROUCH_FACTOR
	elif Input.is_action_pressed("sprint"):
		speed *= SPRINT_FACTOR
	var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, player.rotation.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	player.velocity.x = dir.x * speed
	player.velocity.z = dir.z * speed
	if player.is_on_floor():
		player.velocity.y = 0.0
		# Пригнувшись не прыгаем: иначе присед превращается в способ
		# запрыгивать туда, куда стоя не пролезть.
		if Input.is_action_just_pressed("jump") and not _crouching:
			player.velocity.y = JUMP_SPEED
	else:
		player.velocity.y -= GRAVITY * delta
	player.move_and_slide()
	# Страховка: если игрок провалился под ландшафт, возвращаем его на землю.
	var ground := look.height_at(player.position.x, player.position.z)
	if player.position.y < ground - 4.0:
		player.position.y = ground + BODY_HEIGHT
	player.position.x = clampf(player.position.x, -YARD_LIMIT, YARD_LIMIT)
	player.position.z = clampf(player.position.z, -YARD_LIMIT, YARD_LIMIT)
	_update_focus()


## Присед: капсула сжимается плавно, а не рывком. Разжимаем её только если над
## головой есть место — иначе игрок распрямился бы внутрь перекрытия.
func _apply_stance(delta: float) -> void:
	var wants := Input.is_action_pressed("crouch")
	if not wants and _crouching and not _headroom():
		wants = true
	_crouching = wants
	var target := CROUCH_HEIGHT if _crouching else BODY_HEIGHT
	var before := _capsule.height
	_capsule.height = move_toward(_capsule.height, target, delta * 4.5)
	# Центр капсулы держим так, чтобы ноги оставались на месте.
	player.position.y -= (before - _capsule.height) * 0.5
	camera.position.y = _capsule.height * 0.5 - 0.18


func _headroom() -> bool:
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(player.position,
		player.position + Vector3(0.0, BODY_HEIGHT * 0.5 + 0.15, 0.0))
	query.exclude = [player.get_rid()]
	return space.intersect_ray(query).is_empty()



func _update_focus() -> void:
	_focused = {}
	var best := INTERACT_RANGE
	for station: Dictionary in stations:
		var node: Node3D = station["node"]
		var d := player.position.distance_to(node.position)
		if d < best:
			best = d
			_focused = station
	ui.set_prompt("" if _focused.is_empty() else "E — %s" % _focused["name"])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		var motion := event as InputEventMouseMotion
		player.rotation.y -= motion.relative.x * MOUSE_SENSITIVITY
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENSITIVITY, -1.3, 1.3)
		camera.rotation.x = pitch
	if event.is_action_pressed("interact") and not _focused.is_empty() and not ui.has_modal():
		_capture_mouse(false)
		ui.open_station(StringName(_focused["id"]))
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		if ui.has_modal():
			ui.close_modal()
			_capture_mouse(true)
		else:
			_capture_mouse(not _mouse_captured)

func _capture_mouse(value: bool) -> void:
	_mouse_captured = value
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE

func resume_look() -> void:
	_capture_mouse(true)

# --- Часовня «Алтарь» ---
# Отдельное помещение во дворе дома: четыре стены с дверным проёмом, крыша,
# алтарный камень и тёплый свет. Стены держат игрока, войти можно только в проём.

const CHAPEL_HALF := 2.6            # половина внутреннего размера, равна модулю кита
const CHAPEL_WALL := 0.5
const CHAPEL_HEIGHT := 3.6
const DOORWAY_WIDTH := 2.6

## Часовня собирается от нуля десятком вызовов кита, поэтому высоту площадки
## добавляем целиком к готовым узлам: протаскивать смещение через каждый вызов
## пришлось бы в двадцати местах.
func _build_chapel() -> void:
	var base := look.height_at(CHAPEL_CENTER.x, CHAPEL_CENTER.y)
	var first := get_child_count()
	_build_chapel_geometry()
	for i: int in range(first, get_child_count()):
		var node := get_child(i)
		if node is Node3D:
			(node as Node3D).position.y += base

func _build_chapel_geometry() -> void:
	var props := VillageProps.new(self, PLAYER_RADIUS)
	if props.kit != null:
		_build_chapel_kit(props)
		_blockers.append_array(props.blockers)
		return
	var cx := CHAPEL_CENTER.x
	var cz := CHAPEL_CENTER.y
	var span := CHAPEL_HALF * 2.0
	var stone := Color(0.21, 0.2, 0.22)
	var floor_color := Color(0.28, 0.27, 0.26)
	_box(Vector3(span, 0.1, span), Vector3(cx, 0.06, cz), floor_color)
	var chapel_props := VillageProps.new(self, PLAYER_RADIUS)
	chapel_props.gable_roof(Vector3(cx, CHAPEL_HEIGHT + 0.85, cz), Vector2(span, span), 1.7,
		Color(0.19, 0.18, 0.2))
	# Три глухие стены.
	_box(Vector3(CHAPEL_WALL, CHAPEL_HEIGHT, span), Vector3(cx - CHAPEL_HALF, CHAPEL_HEIGHT * 0.5, cz), stone, true)
	_box(Vector3(CHAPEL_WALL, CHAPEL_HEIGHT, span), Vector3(cx + CHAPEL_HALF, CHAPEL_HEIGHT * 0.5, cz), stone, true)
	_box(Vector3(span, CHAPEL_HEIGHT, CHAPEL_WALL), Vector3(cx, CHAPEL_HEIGHT * 0.5, cz - CHAPEL_HALF), stone, true)
	# Четвёртая — с проёмом наружу, во двор.
	var piece := (span - DOORWAY_WIDTH) * 0.5
	var edge := cx - CHAPEL_HALF
	_box(Vector3(piece, CHAPEL_HEIGHT, CHAPEL_WALL),
		Vector3(edge + piece * 0.5, CHAPEL_HEIGHT * 0.5, cz + CHAPEL_HALF), stone, true)
	_box(Vector3(piece, CHAPEL_HEIGHT, CHAPEL_WALL),
		Vector3(cx + CHAPEL_HALF - piece * 0.5, CHAPEL_HEIGHT * 0.5, cz + CHAPEL_HALF), stone, true)
	# Перемычка над проёмом — чтобы дверь читалась как дверь.
	_box(Vector3(DOORWAY_WIDTH, 0.7, CHAPEL_WALL),
		Vector3(cx, CHAPEL_HEIGHT - 0.35, cz + CHAPEL_HALF), stone)
	# Алтарный камень у дальней стены и свет над ним.
	_box(Vector3(2.2, 1.0, 1.0), Vector3(cx, 0.5, cz - 2.1), Color(0.62, 0.58, 0.5), true)
	_box(Vector3(1.4, 0.18, 0.6), Vector3(cx, 1.09, cz - 2.1), Color(0.85, 0.78, 0.55))
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.4, 1.8, 0.4), Vector3(cx + side * 2.4, 0.9, cz - 2.1), stone, true)
	var glow := OmniLight3D.new()
	glow.position = Vector3(cx, 2.4, cz - 2.0)
	glow.light_color = Color(1.0, 0.82, 0.55)
	glow.light_energy = 2.6
	glow.omni_range = 9.0
	glow.shadow_enabled = false
	add_child(glow)

## Часовня на кладбищенском ките: каменные стены с проёмом, колонны, алтарь,
## свечи и скамьи. Помещение остаётся проходимым — внутрь надо входить.
func _build_chapel_kit(props: VillageProps) -> void:
	var kit := props.kit
	var unit := VillageKit.KIT_SCALE
	var center := Vector3(CHAPEL_CENTER.x, 0.0, CHAPEL_CENTER.y)
	var cell := center / unit
	var half := 1.0
	props.box(Vector3(3.0 * unit, 0.12, 3.0 * unit), center + Vector3(0.0, 0.06, 0.0),
		Color(0.3, 0.29, 0.28))
	# Стены в два ряда, в южной стене — проём.
	for level: int in 2:
		var y := 0.73 * float(level)
		kit.stone_run(cell + Vector3(-half, y, -half), 0, 3)
		kit.stone_run(cell + Vector3(-half, y, half), 2, 3, -1 if level == 1 else 1)
		kit.stone_run(cell + Vector3(-half, y, -half), 1, 3)
		kit.stone_run(cell + Vector3(half, y, -half), 3, 3)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			props.box(Vector3(0.6, 3.4, 0.6),
				center + Vector3(sx * half * unit, 1.7, sz * half * unit), Color(0.34, 0.33, 0.31))
	props.block_rect(center + Vector3(0.0, 0.0, -half * unit), Vector2(3.0 * unit, 0.6))
	for sx: float in [-1.0, 1.0]:
		props.block_rect(center + Vector3(sx * half * unit, 0.0, 0.0), Vector2(0.6, 3.0 * unit))
	props._kit_roof(center + Vector3(0.0, 1.55 * unit, 0.0), Vector2(3.2, 3.2), 1.4,
		Color(0.22, 0.21, 0.24))
	# Убранство: алтарь, свечи, крест, скамьи, светильники у входа.
	var altar := center + Vector3(0.0, 0.0, -1.6)
	# Алтарь, свечи и крест собирает VillageGear: модель из кладбищенского кита
	# была плоской заливкой и рядом с кладкой часовни выбивалась сильнее всего.
	kit.gear().altar(Vector2(altar.x, altar.z), 0.0)
	for i: int in 2:
		for sx: float in [-1.0, 1.0]:
			kit.gear().bench(Vector2(center.x + sx * 1.6, center.z + 0.6 + float(i) * 1.6), 0.0)
	for sx: float in [-1.0, 1.0]:
		kit.gear().lamp_post(Vector2(center.x + sx * 3.4, center.z + 4.6))
	props.block_rect(altar, Vector2(2.8, 1.8))
	var glow_light := OmniLight3D.new()
	glow_light.position = altar + Vector3(0.0, 2.2, 0.6)
	glow_light.light_color = Color(1.0, 0.82, 0.55)
	glow_light.light_energy = 2.8
	glow_light.omni_range = 10.0
	glow_light.shadow_enabled = false
	add_child(glow_light)

## Режим съёмки: игра сама рендерит кадры из заданных точек и выходит. Снимать
## окно с экрана оказалось ненадёжно — фокус уходит другим приложениям, — а
## отсюда камера ставится точно и повторяемо. Включается флагом: `-- --shots`.
func _capture_shots() -> void:
	var shots := [
		{"name": "01_plan", "pos": Vector3(0.0, 165.0, 25.0), "rot": Vector3(-82.0, 0.0, 0.0)},
		{"name": "02_plan_wide", "pos": Vector3(0.0, 300.0, 90.0), "rot": Vector3(-72.0, 0.0, 0.0)},
		{"name": "03_entry", "pos": Vector3(0.0, 4.6, 33.0), "rot": Vector3(-7.0, 0.0, 0.0)},
		{"name": "04_bridge", "pos": Vector3(0.0, 3.6, 24.0), "rot": Vector3(-4.0, 0.0, 0.0)},
		{"name": "05_street", "pos": Vector3(0.0, 3.4, 8.0), "rot": Vector3(-3.0, 0.0, 0.0)},
		{"name": "06_square", "pos": Vector3(11.0, 4.4, 2.0), "rot": Vector3(-8.0, -72.0, 0.0)},
		{"name": "07_house", "pos": Vector3(6.0, 3.0, -4.0), "rot": Vector3(-2.0, -95.0, 0.0)},
		{"name": "08_river", "pos": Vector3(-20.0, 5.0, 30.0), "rot": Vector3(-10.0, 55.0, 0.0)},
		{"name": "09_north", "pos": Vector3(0.0, 4.0, -20.0), "rot": Vector3(-5.0, 180.0, 0.0)},
	]
	var cam := Camera3D.new()
	cam.fov = 72.0
	cam.far = 900.0
	add_child(cam)
	cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var out := "C:/Users/Makar/AppData/Local/Temp/claude/C--Users-Makar-Documents-Sword-World-3D/f5cda29b-25cf-40d7-815d-9d86fa6b9bbf/scratchpad/shots/"
	DirAccess.make_dir_recursive_absolute(out)
	for shot: Dictionary in shots:
		cam.position = shot["pos"]
		cam.rotation_degrees = shot["rot"]
		# Несколько кадров паузы: SDFGI, объёмный туман и TAA накапливаются
		# между кадрами, и первый после переноса камеры выходит грязным.
		for i: int in 12:
			await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(out + String(shot["name"]) + ".png")
	get_tree().quit()
