class_name RngStream
extends RefCounted
## Детерминированный поток случайных чисел (08-architecture.md §5).
## Глобальные randi()/randf() в core/ запрещены — только этот класс.

var _rng := RandomNumberGenerator.new()
var stream_name: StringName = &""

func _init(seed_value: int = 0, name: StringName = &"default") -> void:
	stream_name = name
	_rng.seed = hash_combine(seed_value, name)
	_rng.state = _rng.seed

static func hash_combine(a: int, b: Variant) -> int:
	return abs(hash(str(a) + "|" + str(b)))

## Целое в [from, to] включительно.
func randi_range(from: int, to: int) -> int:
	if to <= from:
		return from
	return _rng.randi_range(from, to)

func randf_value() -> float:
	return _rng.randf()

func randf_range_value(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

## Случайный элемент массива.
func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[randi_range(0, items.size() - 1)]

## Взвешенный выбор: weights той же длины, что items.
func pick_weighted(items: Array, weights: Array) -> Variant:
	if items.is_empty():
		return null
	var total: float = 0.0
	for w: float in weights:
		total += maxf(0.0, w)
	if total <= 0.0:
		return pick(items)
	var roll: float = randf_value() * total
	var acc: float = 0.0
	for i: int in items.size():
		acc += maxf(0.0, float(weights[i]))
		if roll <= acc:
			return items[i]
	return items[items.size() - 1]

## Перемешивание на месте (Фишер–Йетс на нашем потоке, не на глобальном RNG).
func shuffle(items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp

## Порождает дочерний поток — так подсистемы не сдвигают броски друг друга.
func derive(name: StringName) -> RngStream:
	return RngStream.new(int(_rng.seed), name)

## Сериализация состояния: без неё save-scumming ломает рогалик (§5).
func save_state() -> Dictionary:
	return {"seed": int(_rng.seed), "state": int(_rng.state), "name": String(stream_name)}

func load_state(data: Dictionary) -> void:
	_rng.seed = int(data.get("seed", 0))
	_rng.state = int(data.get("state", _rng.seed))
	stream_name = StringName(data.get("name", "default"))
