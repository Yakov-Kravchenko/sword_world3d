class_name UIKit
extends RefCounted
## Общие элементы интерфейса: тёмная палитра, читаемые панели, никакой вёрстки в .tscn.

const BG := Color(0.07, 0.07, 0.09, 0.92)
const BG_SOFT := Color(0.11, 0.11, 0.14, 0.9)
const ACCENT := Color(0.85, 0.68, 0.35)
const TEXT := Color(0.88, 0.86, 0.82)
const DANGER := Color(0.85, 0.32, 0.32)
const GOOD := Color(0.45, 0.78, 0.45)

static func panel(color: Color = BG, radius: int = 6) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.border_color = Color(0.25, 0.23, 0.2, 0.8)
	style.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", style)
	return p

static func label(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func rich(text: String, size: int = 13) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = false
	r.scroll_following = true
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("default_color", TEXT)
	return r

## Подпись строки списка: переносится по словам и отдаёт остаток ширины кнопкам,
## иначе длинный текст выталкивает кнопку выбора за край панели.
static func row_label(text: String, size: int = 12, color: Color = TEXT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(120, 0)
	return l

static func button(text: String, callback: Callable, size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 30)
	if callback.is_valid():
		b.pressed.connect(callback)
	return b

## Кнопка внутри строки списка: не растягивается и не выталкивается подписью.
static func row_button(text: String, callback: Callable, size: int = 12,
		minimum_width: float = 130.0) -> Button:
	var b := button(text, callback, size)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.custom_minimum_size = Vector2(minimum_width, 28)
	b.clip_text = true
	return b

static func bar(value: float, maximum: float, color: Color, width: float = 150.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = maxf(1.0, maximum)
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(width, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.16, 0.15, 0.16)
	bg.set_corner_radius_all(3)
	p.add_theme_stylebox_override("fill", fill)
	p.add_theme_stylebox_override("background", bg)
	return p

static func vbox(separation: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v

static func hbox(separation: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h

## Ряд, который сам переносит элементы на следующую строку по ширине панели.
## Панель действий и лента инициативы обязаны переноситься, иначе часть кнопок
## уходит за край и по ним нельзя кликнуть.
static func flow(separation: int = 4) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", separation)
	f.add_theme_constant_override("v_separation", separation)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f

static func spacer(minimum: Vector2 = Vector2(0, 6)) -> Control:
	var c := Control.new()
	c.custom_minimum_size = minimum
	return c

## Затемняющая подложка модальных окон.
static func modal_root() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	return root

## Модальное окно. Размер задаётся долей экрана, а не пикселями, поэтому окно
## одинаково открывается на любом разрешении и не уезжает за край. Содержимое
## прокручивается, строка решения всегда остаётся видимой — иначе часть пунктов
## оказывается вне панели и по ним нельзя кликнуть.
static func modal_window(root: Control, width: float, height: float) -> Dictionary:
	const REFERENCE := Vector2(1600.0, 900.0)
	var ratio := Vector2(clampf(width / REFERENCE.x, 0.35, 0.94),
		clampf(height / REFERENCE.y, 0.35, 0.94))
	var wrapper := panel(BG)
	wrapper.anchor_left = 0.5 - ratio.x * 0.5
	wrapper.anchor_right = 0.5 + ratio.x * 0.5
	wrapper.anchor_top = 0.5 - ratio.y * 0.5
	wrapper.anchor_bottom = 0.5 + ratio.y * 0.5
	wrapper.offset_left = 0.0
	wrapper.offset_top = 0.0
	wrapper.offset_right = 0.0
	wrapper.offset_bottom = 0.0
	root.add_child(wrapper)
	var column := vbox(8)
	wrapper.add_child(column)
	var header := vbox(4)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var content := vbox(6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var footer := flow(8)
	footer.alignment = FlowContainer.ALIGNMENT_END
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(footer)
	return {"wrapper": wrapper, "header": header, "content": content, "footer": footer}

static func hp_color(ratio: float) -> Color:
	if ratio > 0.6:
		return GOOD
	if ratio > 0.3:
		return ACCENT
	return DANGER
