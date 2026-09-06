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
			if not String(key).begins_with("_"):
				_aliases[String(key)] = String((parsed as Dictionary)[key])

## Путь к модели или пустая строка, если её нет.
static func find(category: String, model_name: String) -> String:
	_load_aliases()
	if _aliases.has(model_name):
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
		"actors": ["hald", "irma", "vern", "mara", "enemy_default"],
	}

## Модель под нужный рост: киты сделаны в своём масштабе, поэтому подгоняем по
## высоте габаритов, а не подбираем множитель руками для каждого файла.
## Масштаб модели берётся из таблицы соответствий: автоматический замер габарита
## у моделей из китов ненадёжен — внутри встречаются служебные узлы с огромным
## bounding box. Ключ "<id>_scale" в aliases.json задаёт множитель.
static func model_scale(model_name: String) -> float:
	_load_aliases()
	var key := model_name + "_scale"
	return float(_aliases[key]) if _aliases.has(key) else 1.0

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
