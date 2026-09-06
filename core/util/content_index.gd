class_name ContentIndex
extends RefCounted
## Сканирует data/**/*.json и строит реестр типизированных ресурсов.
## Используется автозагрузкой Database, валидатором и тестами (без зависимости от нод).

var by_class: Dictionary = {}
var by_id: Dictionary = {}
var errors: Array[String] = []
var files: int = 0

static func load_from(root: String = "res://data", skip_balance: bool = true) -> ContentIndex:
	var index := ContentIndex.new()
	index._scan(root, skip_balance)
	return index

func _scan(path: String, skip_balance: bool) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		errors.append("не открывается каталог %s" % path)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan(full, skip_balance)
		elif name.ends_with(".json"):
			if not (skip_balance and name == "balance.json"):
				_load_file(full)
		name = dir.get_next()
	dir.list_dir_end()

func _load_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("не читается %s" % path)
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		errors.append("не разбирается JSON: %s" % path)
		return
	files += 1
	var manifests: Array = parsed if parsed is Array else [parsed]
	for m: Variant in manifests:
		if m is Dictionary:
			_load_manifest(m, path)

func _load_manifest(manifest: Dictionary, path: String) -> void:
	var cls := String(manifest.get("class", ""))
	if cls.is_empty():
		errors.append("нет поля class: %s" % path)
		return
	for e: Variant in manifest.get("entries", []):
		if not (e is Dictionary):
			continue
		var res := DataLoader.build(cls, e)
		if res == null:
			errors.append("неизвестный класс %s в %s" % [cls, path])
			continue
		var id := StringName(res.get("id"))
		if id == &"":
			errors.append("запись без id в %s" % path)
			continue
		if by_id.has(id):
			errors.append("дубль id %s (%s)" % [id, path])
		by_id[id] = res
		if not by_class.has(cls):
			by_class[cls] = {}
		by_class[cls][id] = res

func of_class(cls: String) -> Array:
	return (by_class.get(cls, {}) as Dictionary).values()

func map_of_class(cls: String) -> Dictionary:
	return (by_class.get(cls, {}) as Dictionary).duplicate()

func get_resource(id: StringName) -> Resource:
	return by_id.get(id, null)

## Загрузка balance.json отдельно: им владеет автозагрузка Balance.
static func load_balance(path: String = "res://data/balance/balance.json") -> BalanceData:
	var data := BalanceData.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return data
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		var entries: Array = (parsed as Dictionary).get("entries", [])
		if not entries.is_empty():
			DataLoader.apply(data, entries[0])
	return data
