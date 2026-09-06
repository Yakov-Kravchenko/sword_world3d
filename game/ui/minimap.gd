extends Control
## Миникарта этажа: вход, выход, посещённые и зачищенные комнаты, положение отряда.
## Рисуется прямо из FloorPlan — отдельной модели карты не нужно.

const SMALL := Vector2(280.0, 280.0)
const LARGE := Vector2(760.0, 720.0)
const PADDING := 14.0

const COLOR_BG := Color(0.06, 0.06, 0.08, 0.88)
const COLOR_UNKNOWN := Color(0.18, 0.18, 0.21)
const COLOR_VISITED := Color(0.34, 0.33, 0.31)
const COLOR_CLEARED := Color(0.27, 0.42, 0.29)
const COLOR_DANGER := Color(0.62, 0.26, 0.24)
const COLOR_CORRIDOR := Color(0.24, 0.24, 0.26)
const COLOR_ENTRANCE := Color(0.42, 0.78, 0.45)
const COLOR_EXIT := Color(0.92, 0.72, 0.3)
const COLOR_PARTY := Color(0.95, 0.95, 0.92)

var service: RunService
var plan: FloorPlan
var party_cell: Vector2i = Vector2i.ZERO
var expanded: bool = false

var _bounds: Rect2 = Rect2()

func setup(run_service: RunService, floor_plan: FloorPlan) -> void:
	service = run_service
	plan = floor_plan
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compute_bounds()
	_apply_size()

func _compute_bounds() -> void:
	if plan == null or plan.rooms.is_empty():
		_bounds = Rect2(0.0, 0.0, 1.0, 1.0)
		return
	var rect := Rect2(plan.rooms[0].rect)
	for room: FloorPlan.Room in plan.rooms:
		rect = rect.merge(Rect2(room.rect))
	_bounds = rect.grow(2.0)

func toggle() -> void:
	expanded = not expanded
	_apply_size()
	queue_redraw()

func _apply_size() -> void:
	var size := LARGE if expanded else SMALL
	custom_minimum_size = size
	if expanded:
		var screen := get_viewport_rect().size
		position = (screen - size) * 0.5
	else:
		position = Vector2(get_viewport_rect().size.x - size.x - 12.0, 108.0)
	self.size = size

func set_party_cell(cell: Vector2i) -> void:
	if cell == party_cell:
		return
	party_cell = cell
	queue_redraw()

func refresh() -> void:
	queue_redraw()

## Перевод клетки этажа в координаты внутри виджета.
func _to_local(cell: Vector2) -> Vector2:
	var inner := size - Vector2(PADDING, PADDING) * 2.0 - Vector2(0.0, 22.0)
	var scale_factor := minf(inner.x / _bounds.size.x, inner.y / _bounds.size.y)
	var offset := Vector2(PADDING, PADDING) + (inner - _bounds.size * scale_factor) * 0.5
	return offset + (cell - _bounds.position) * scale_factor

func _cell_scale() -> float:
	var inner := size - Vector2(PADDING, PADDING) * 2.0 - Vector2(0.0, 22.0)
	return minf(inner.x / _bounds.size.x, inner.y / _bounds.size.y)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.23, 0.2, 0.9), false, 1.0)
	if plan == null or service == null:
		return
	_draw_corridors()
	for room: FloorPlan.Room in plan.rooms:
		_draw_room(room)
	_draw_markers()
	_draw_legend()

## Коридоры между уже посещёнными комнатами.
func _draw_corridors() -> void:
	for room: FloorPlan.Room in plan.rooms:
		if not service.run.visited_rooms.has(room.index):
			continue
		for other_index: int in room.connections:
			if not service.run.visited_rooms.has(other_index):
				continue
			draw_line(_to_local(Vector2(room.center())),
				_to_local(Vector2(plan.rooms[other_index].center())), COLOR_CORRIDOR, 3.0)

func _draw_room(room: FloorPlan.Room) -> void:
	var visited := service.run.visited_rooms.has(room.index)
	var top_left := _to_local(Vector2(room.rect.position))
	var rect := Rect2(top_left, Vector2(room.rect.size) * _cell_scale())
	if not visited:
		draw_rect(rect, COLOR_UNKNOWN, false, 1.0)
		return
	var encounter := plan.encounter_for_room(room.index)
	var cleared := service.run.cleared_rooms.has(room.index)
	var color := COLOR_VISITED
	if not encounter.is_empty():
		color = COLOR_CLEARED if cleared else COLOR_DANGER
	draw_rect(rect, color, true)
	draw_rect(rect, color.lightened(0.25), false, 1.0)

func _draw_markers() -> void:
	var radius := maxf(3.0, _cell_scale() * 1.6)
	# Вход и выход крупнее и с обводкой, иначе маркер отряда их перекрывает.
	_marker(_to_local(Vector2(plan.entrance_cell)), radius * 1.4, COLOR_ENTRANCE)
	_marker(_to_local(Vector2(plan.exit_cell)), radius * 1.4, COLOR_EXIT)
	# Несобранные объекты в уже посещённых комнатах.
	for i: int in plan.props.size():
		if service.run.looted_props.has(i):
			continue
		var prop: Dictionary = plan.props[i]
		if not service.run.visited_rooms.has(int(prop.get("room", -1))):
			continue
		var tint := Color(0.72, 0.62, 0.38) if StringName(prop.get("kind", &"")) == &"chest" \
			else Color(0.45, 0.6, 0.72)
		draw_circle(_to_local(Vector2(prop["cell"])), radius * 0.55, tint)
	_marker(_to_local(Vector2(party_cell)), radius * 0.85, COLOR_PARTY)

## Кружок с тёмной обводкой — читается поверх любой заливки комнаты.
func _marker(point: Vector2, radius: float, color: Color) -> void:
	draw_circle(point, radius + 1.5, Color(0.04, 0.04, 0.05, 0.9))
	draw_circle(point, radius, color)

## Легенда с образцами цвета: без них карта читается только на память.
func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	var font_size := 12 if expanded else 10
	var y := size.y - 12.0
	if not expanded:
		draw_string(font, Vector2(PADDING, y), "M — крупная карта",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.7, 0.68, 0.64))
		return
	var items: Array[Array] = [
		[COLOR_ENTRANCE, "вход", true],
		[COLOR_EXIT, "выход", true],
		[COLOR_PARTY, "отряд", true],
		[COLOR_VISITED, "пройдено", false],
		[COLOR_CLEARED, "зачищено", false],
		[COLOR_DANGER, "бой", false],
		[COLOR_UNKNOWN, "не открыто", false],
	]
	var x := PADDING
	for item: Array in items:
		var color: Color = item[0]
		var text: String = item[1]
		if bool(item[2]):
			draw_circle(Vector2(x + 5.0, y - 4.0), 5.0, color)
		else:
			draw_rect(Rect2(x, y - 9.0, 10.0, 10.0), color, true)
		x += 15.0
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
			Color(0.82, 0.8, 0.76))
		x += width + 14.0
