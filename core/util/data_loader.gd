class_name DataLoader
extends RefCounted
## Заполняет типизированный Resource из словаря (JSON контента data/).
## Приводит типы по метаданным свойств, поэтому в JSON пишутся обычные строки и массивы.

static var _class_paths: Dictionary = {}

static func _ensure_class_map() -> void:
	if not _class_paths.is_empty():
		return
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		_class_paths[String(entry.get("class", ""))] = String(entry.get("path", ""))

static func class_path(cls: String) -> String:
	_ensure_class_map()
	return String(_class_paths.get(cls, ""))

static func make(cls: String) -> Resource:
	var path := class_path(cls)
	if path.is_empty():
		return null
	var script: Script = load(path)
	if script == null:
		return null
	return script.new()

## Создаёт ресурс класса cls и заполняет его из словаря.
static func build(cls: String, data: Dictionary) -> Resource:
	var res := make(cls)
	if res == null:
		return null
	apply(res, data)
	return res

## Записывает поля словаря в существующий ресурс.
static func apply(res: Object, data: Dictionary) -> void:
	var props := {}
	for p: Dictionary in res.get_property_list():
		props[String(p.get("name", ""))] = p
	for key: Variant in data.keys():
		var name := String(key)
		if not props.has(name):
			continue
		var p: Dictionary = props[name]
		res.set(name, _coerce(data[key], int(p.get("type", TYPE_NIL)), String(p.get("hint_string", ""))))

static func _coerce(value: Variant, type: int, hint_string: String) -> Variant:
	match type:
		TYPE_STRING_NAME:
			return StringName(value)
		TYPE_STRING:
			return String(value)
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_BOOL:
			return bool(value)
		TYPE_VECTOR2I:
			if value is Array and value.size() >= 2:
				return Vector2i(int(value[0]), int(value[1]))
			return value
		TYPE_COLOR:
			if value is String:
				return Color(value)
			if value is Array and value.size() >= 3:
				return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() > 3 else 1.0)
			return value
		TYPE_PACKED_INT32_ARRAY:
			var pi := PackedInt32Array()
			for v: Variant in value:
				pi.append(int(v))
			return pi
		TYPE_PACKED_FLOAT32_ARRAY:
			var pf := PackedFloat32Array()
			for v: Variant in value:
				pf.append(float(v))
			return pf
		TYPE_PACKED_STRING_ARRAY:
			var ps := PackedStringArray()
			for v: Variant in value:
				ps.append(String(v))
			return ps
		TYPE_DICTIONARY:
			return _coerce_dict(value)
		TYPE_ARRAY:
			return _coerce_array(value, hint_string)
	return value

static func _coerce_dict(value: Variant) -> Dictionary:
	var out := {}
	if value is Dictionary:
		for k: Variant in value.keys():
			out[StringName(k)] = value[k]
	return out

static func _coerce_array(value: Variant, hint_string: String) -> Array:
	if not (value is Array):
		return []
	var src: Array = value
	if hint_string.is_empty():
		return src.duplicate()
	var parts := hint_string.split(":")
	var head := parts[0]
	var cls := parts[1] if parts.size() > 1 else ""
	if head.contains("/"):
		# Массив ресурсов: Array[AttackData] и т.п.
		var out: Array = []
		for item: Variant in src:
			if item is Dictionary:
				var r := build(cls, item)
				if r != null:
					out.append(r)
			else:
				out.append(item)
		return _retype(out, cls)
	var elem_type := int(head) if head.is_valid_int() else TYPE_NIL
	var typed: Array = []
	for item: Variant in src:
		typed.append(_coerce(item, elem_type, ""))
	if elem_type == TYPE_STRING_NAME:
		var sn: Array[StringName] = []
		for item: Variant in typed:
			sn.append(item)
		return sn
	if elem_type == TYPE_STRING:
		var st: Array[String] = []
		for item: Variant in typed:
			st.append(item)
		return st
	return typed

static func _retype(items: Array, cls: String) -> Array:
	var path := class_path(cls)
	if path.is_empty():
		return items
	var script: Script = load(path)
	var typed := Array([], TYPE_OBJECT, &"Resource", script)
	for item: Variant in items:
		typed.append(item)
	return typed
