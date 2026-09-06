class_name ModelLibrary
extends RefCounted
## Подмена процедурной геометрии готовыми моделями.
##
## Если в assets/models/<категория>/<имя>.glb (или .tscn) лежит модель — берётся
## она, иначе строится процедурная заглушка. Благодаря этому подключение
## купленных или CC0-ассетов не требует правок в коде построек и персонажей:
## достаточно положить файл с нужным именем.

const ROOT := "res://assets/models/"
const EXTENSIONS: Array[String] = [".glb", ".gltf", ".tscn", ".scn"]

static var _aliases: Dictionary = {}
static var _aliases_loaded: bool = false

## Таблица соответствий id актёра и файла модели: assets/models/aliases.json.
## Позволяет одной моделью закрыть несколько врагов и не плодить копии файлов.
static func _load_aliases() -> void:
	if _aliases_loaded:
		return
	_aliases_loaded = true
	var file := FileAccess.open(ROOT + "aliases.json", FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		for key: Variant in (parsed as Dictionary).keys():
			if String(key).begins_with("_folder_") or not String(key).begins_with("_"):
				# Значение остаётся как есть: строки — пути, числа — масштаб и доворот.
				_aliases[String(key)] = (parsed as Dictionary)[key]

## Путь к модели или пустая строка, если её нет.
static func find(category: String, model_name: String) -> String:
	_load_aliases()
	if _aliases.has(model_name) and _aliases[model_name] is String:
		for extension: String in EXTENSIONS:
			var aliased: String = ROOT + String(_aliases[model_name]) + extension
			if ResourceLoader.exists(aliased):
				return aliased
	for extension: String in EXTENSIONS:
		var path := "%s%s/%s%s" % [ROOT, category, model_name, extension]
		if ResourceLoader.exists(path):
			return path
	return ""

static func has(category: String, model_name: String) -> bool:
	return not find(category, model_name).is_empty()

## Создаёт экземпляр модели; null, если файла нет или он не сцена.
static func instantiate(category: String, model_name: String) -> Node3D:
	var path := find(category, model_name)
	if path.is_empty():
		return null
	var packed: Variant = load(path)
	if not (packed is PackedScene):
		return null
	var node: Variant = (packed as PackedScene).instantiate()
	return node if node is Node3D else null

## Модель в узле-держателе: доворот и масштаб кита лежат на вложенном узле,
## поэтому игровой код крутит и двигает держатель как обычный Node3D, ничего не
## зная про особенности конкретного набора моделей.
static func build(category: String, model_name: String) -> Node3D:
	var model := instantiate(category, model_name)
	if model == null:
		return null
	var root := Node3D.new()
	model.rotation.y = deg_to_rad(model_yaw(model_name))
	var factor := model_scale(model_name)
	if not is_equal_approx(factor, 1.0):
		model.scale = Vector3.ONE * factor
	root.add_child(model)
	return root

## Габариты модели в плане — нужны, чтобы построить препятствие под неё.
static func footprint(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child: Node in _all_children(node):
		if not (child is VisualInstance3D):
			continue
		var mesh_box: AABB = (child as VisualInstance3D).get_aabb()
		# Трансформы копим по всей цепочке до корня: у скиненных мешей узел лежит
		# внутри Skeleton3D, и один локальный transform даёт неверный габарит.
		var local := _relative_transform(child as Node3D, node) * mesh_box
		if first:
			box = local
			first = false
		else:
			box = box.merge(local)
	return box

static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

static func _all_children(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_all_children(child))
	return out

## Список того, что игра ищет — печатается инструментом проверки ассетов.
static func expected() -> Dictionary:
	return {
		"village": ["forge", "training", "shop", "garden", "storage", "descend", "chapel"],
		"actors": ["hald", "irma", "vern", "mara", "skeleton_warrior", "bone_archer",
			"bone_legionnaire", "lich_acolyte", "ghoul", "enemy_default"],
		"props": ["chest_common", "chest_treasure"],
	}

## Масштаб модели берётся из таблицы соответствий: автоматический замер габарита
## у моделей из китов ненадёжен — внутри встречаются служебные узлы с огромным
## bounding box. Ключ "<id>_scale" в aliases.json задаёт множитель для одного
## персонажа, "_folder_scale" — для всего кита.
static func model_scale(model_name: String) -> float:
	_load_aliases()
	var key := model_name + "_scale"
	if _aliases.has(key):
		return float(_aliases[key])
	return _folder_number(model_name, "_folder_scale", 1.0)

## Значение по умолчанию для всего кита: масштаб и разворот — свойство набора
## моделей, а не конкретного персонажа, поэтому дублировать их на каждый id
## незачем. Ключ "_folder_scale" / "_folder_yaw" — папка внутри assets/models.
static func _folder_number(model_name: String, table: String, fallback: float) -> float:
	if not (_aliases.has(table) and _aliases[table] is Dictionary):
		return fallback
	var path := String(_aliases[model_name]) if _aliases.has(model_name) else ""
	var folder := path.get_base_dir()
	var folders: Dictionary = _aliases[table]
	return float(folders[folder]) if folders.has(folder) else fallback

## Разворот модели вокруг Y в градусах. В Godot «перёд» узла — это -Z, а модели
## из китов обычно смотрят в +Z, поэтому по умолчанию их надо развернуть на 180:
## иначе персонаж идёт спиной вперёд и смотрит в камеру.
static func model_yaw(model_name: String) -> float:
	_load_aliases()
	var key := model_name + "_yaw"
	if _aliases.has(key):
		return float(_aliases[key])
	return _folder_number(model_name, "_folder_yaw", 180.0)

## Подгонка роста уже добавленной в дерево модели. Мерить надо именно здесь:
## у моделей из китов масштаб раскидан по узлам, и вне дерева габарит врёт.
## Надёжный габарит модели, уже добавленной в дерево.
static func measure(node: Node3D) -> AABB:
	if node == null or not node.is_inside_tree():
		return AABB()
	var inverse := node.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for child: Node in _all_children(node):
		if not (child is VisualInstance3D):
			continue
		var world: Transform3D = (child as Node3D).global_transform
		var local := inverse * world * (child as VisualInstance3D).get_aabb()
		if first:
			box = local
			first = false
		else:
			box = box.merge(local)
	return box

static func fit_height(node: Node3D, target_height: float) -> void:
	var box := measure(node)
	if box.size.y < 0.01:
		return
	var factor := target_height / box.size.y
	if factor > 0.02 and factor < 50.0:
		node.scale = Vector3.ONE * factor

## Габарит модели в мировых координатах — то, что реально видно на экране,
## с учётом всех масштабов по цепочке узлов.
static func measure_world(node: Node3D) -> AABB:
	if node == null or not node.is_inside_tree():
		return AABB()
	var box := AABB()
	var first := true
	for child: Node in _all_children(node):
		if not (child is VisualInstance3D):
			continue
		var world: Transform3D = (child as Node3D).global_transform
		var piece: AABB = world * (child as VisualInstance3D).get_aabb()
		if first:
			box = piece
			first = false
		else:
			box = box.merge(piece)
	return box
