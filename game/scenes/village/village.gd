extends Node3D
## Хаб от первого лица: дом основного героя и постройки вокруг
## (06-hub.md). Камера — 1-е лицо, как требует ТЗ.

const MOVE_SPEED := 4.0
const MOUSE_SENSITIVITY := 0.0025
const INTERACT_RANGE := 3.6
const PLAYER_RADIUS := 0.45
const YARD_LIMIT := 33.0

var camera: Camera3D
var player: Node3D
var pitch: float = 0.0
var ui: Control
var stations: Array[Dictionary] = []
var _blockers: Array[Rect2] = []
var _focused: Dictionary = {}
var _mouse_captured: bool = false

func _ready() -> void:
	if GameState.profile == null:
		GameState.new_profile(&"hald")
	_build_world()
	_build_stations()
	_build_ui()
	_capture_mouse(true)
	EventBus.notify("День %d в деревне. E — взаимодействие, Esc — курсор." % GameState.profile.day)

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.44, 0.5)
	e.ambient_light_energy = 1.9
	e.fog_enabled = true
	e.fog_light_color = Color(0.12, 0.13, 0.16)
	e.fog_density = 0.008
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(0.95, 0.88, 0.75)
	sun.shadow_enabled = true
	add_child(sun)
	var yard := YARD_LIMIT * 2.0 + 4.0
	_box(Vector3(yard, 0.4, yard), Vector3(0.0, -0.2, 0.0), Color(0.33, 0.31, 0.27))
	for i: int in 4:
		var angle := i * PI * 0.5
		var offset := Vector3(sin(angle), 0.0, cos(angle)) * (YARD_LIMIT + 1.5)
		var size := Vector3(yard, 6.0, 0.8) if i % 2 == 0 else Vector3(0.8, 6.0, yard)
		_box(size, offset + Vector3(0.0, 3.0, 0.0), Color(0.17, 0.16, 0.15))
	_build_chapel()
	player = Node3D.new()
	player.position = Vector3(0.0, 1.7, 29.0)
	add_child(player)
	camera = Camera3D.new()
	camera.fov = 75.0
	player.add_child(camera)

## blocking=true добавляет коробку в список препятствий: стены должны держать
## игрока, иначе в помещение нельзя войти через дверной проём.
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

func _blocked(x: float, z: float) -> bool:
	for rect: Rect2 in _blockers:
		if rect.has_point(Vector2(x, z)):
			return true
	return false

## Постройки, а не тумбы: каждый объект собирается VillageProps и отдаёт точку,
## у которой игрок с ним взаимодействует. Расстояния между ними большие —
## деревню надо обходить, а не разглядывать с одного места.
func _build_stations() -> void:
	var props := VillageProps.new(self, PLAYER_RADIUS)
	var defs: Array[Dictionary] = [
		{"id": &"forge", "name": "Кузница",
			"pos": props.build_forge(Vector3(-26.0, 0.0, -4.0))},
		{"id": &"training", "name": "Тренировочный зал",
			"pos": props.build_training(Vector3(-17.0, 0.0, -22.0))},
		{"id": &"shop", "name": "Лавка",
			"pos": props.build_shop(Vector3(26.0, 0.0, -4.0))},
		{"id": &"garden", "name": "Сад",
			"pos": props.build_garden(Vector3(-22.0, 0.0, 20.0))},
		{"id": &"storage", "name": "Склад",
			"pos": props.build_storage(Vector3(22.0, 0.0, 19.0))},
		{"id": &"descend", "name": "Спуск в Разлом",
			"pos": props.build_descend(Vector3(0.0, 0.0, -29.0))},
		{"id": &"altar", "name": "Алтарь",
			"pos": Vector3(CHAPEL_CENTER.x, 0.9, CHAPEL_CENTER.y + 0.4),
			"path_to": Vector3(CHAPEL_CENTER.x, 0.0, CHAPEL_CENTER.y + CHAPEL_HALF + 1.5)},
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
		# К часовне дорожка ведёт ко входу, а не сквозь стену.
		_pave_path(props, Vector3(0.0, 0.0, 4.0), def.get("path_to", def["pos"]))

## Дорожка от центральной площади к постройке — без неё в большом дворе теряешься.
func _pave_path(props: VillageProps, from: Vector3, to: Vector3) -> void:
	var flat_from := Vector3(from.x, 0.0, from.z)
	var flat_to := Vector3(to.x, 0.0, to.z)
	var steps := int(flat_from.distance_to(flat_to) / 1.2)
	for i: int in range(1, maxi(1, steps)):
		var point := flat_from.lerp(flat_to, float(i) / float(steps))
		# Плитки перекрываются и лежат вровень с землёй, иначе читаются как
		# отдельные плиты, парящие над двором.
		props.box(Vector3(2.0, 0.04, 2.0), point + Vector3(0.0, 0.005, 0.0),
			Color(0.3, 0.29, 0.26))
func _build_ui() -> void:
	ui = preload("res://game/ui/village_ui.gd").new()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(ui)
	ui.setup(self)

func _process(delta: float) -> void:
	if ui.has_modal():
		return
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if input.length() > 0.01:
		var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, player.rotation.y)
		var step := dir.normalized() * MOVE_SPEED * delta
		# Оси проверяем раздельно, чтобы можно было скользить вдоль стены.
		var next_x := clampf(player.position.x + step.x, -YARD_LIMIT, YARD_LIMIT)
		if not _blocked(next_x, player.position.z):
			player.position.x = next_x
		var next_z := clampf(player.position.z + step.z, -YARD_LIMIT, YARD_LIMIT)
		if not _blocked(player.position.x, next_z):
			player.position.z = next_z
	_update_focus()

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

const CHAPEL_CENTER := Vector2(18.0, -20.0)
const CHAPEL_HALF := 2.6            # половина внутреннего размера, равна модулю кита
const CHAPEL_WALL := 0.5
const CHAPEL_HEIGHT := 3.6
const DOORWAY_WIDTH := 2.6

func _build_chapel() -> void:
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
			kit.piece("column-large", cell + Vector3(sx * half, 0.0, sz * half), 0,
				VillageKit.GRAVE)
	props.block_rect(center + Vector3(0.0, 0.0, -half * unit), Vector2(3.0 * unit, 0.6))
	for sx: float in [-1.0, 1.0]:
		props.block_rect(center + Vector3(sx * half * unit, 0.0, 0.0), Vector2(0.6, 3.0 * unit))
	props._kit_roof(center + Vector3(0.0, 1.55 * unit, 0.0), Vector2(3.2, 3.2), 1.4,
		Color(0.22, 0.21, 0.24))
	# Убранство: алтарь, свечи, крест, скамьи, светильники у входа.
	var altar := center + Vector3(0.0, 0.0, -1.6)
	kit.piece("altar-stone", altar / unit, 0, VillageKit.GRAVE)
	kit.piece("candle-multiple", (altar + Vector3(-0.6, 1.3, 0.0)) / unit, 0, VillageKit.GRAVE)
	kit.piece("candle-multiple", (altar + Vector3(0.6, 1.3, 0.0)) / unit, 0, VillageKit.GRAVE)
	kit.piece("cross", (center + Vector3(0.0, 1.6, -3.2)) / unit, 0, VillageKit.GRAVE)
	for i: int in 2:
		for sx: float in [-1.0, 1.0]:
			kit.piece("bench", (center + Vector3(sx * 1.6, 0.0, 0.6 + float(i) * 1.6)) / unit,
				0, VillageKit.GRAVE)
	for sx: float in [-1.0, 1.0]:
		kit.piece("lightpost-single", (center + Vector3(sx * 3.4, 0.0, 4.6)) / unit, 0,
			VillageKit.GRAVE)
	props.block_rect(altar, Vector2(2.8, 1.8))
	var glow_light := OmniLight3D.new()
	glow_light.position = altar + Vector3(0.0, 2.2, 0.6)
	glow_light.light_color = Color(1.0, 0.82, 0.55)
	glow_light.light_energy = 2.8
	glow_light.omni_range = 10.0
	glow_light.shadow_enabled = false
	add_child(glow_light)
