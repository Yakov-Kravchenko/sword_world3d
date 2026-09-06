class_name BlessingPool
extends RefCounted
## Выбор благословений на этажах 5, 10, 15, 20 (03-characters.md, раздел 5).

const RARITY_WEIGHT := {&"common": 55.0, &"rare": 30.0, &"epic": 12.0, &"cursed": 3.0}

var pool: Array = []   # BlessingData

func _init(all: Array) -> void:
	pool = all

## Три карты на выбор, без повторов уже взятого.
func offer(rng: RngStream, taken: Array[StringName], count: int = 3) -> Array:
	var candidates: Array = []
	var weights: Array = []
	for b: BlessingData in pool:
		if taken.has(b.id):
			continue
		candidates.append(b)
		weights.append(b.weight * float(RARITY_WEIGHT.get(b.rarity, 1.0)))
	var out: Array = []
	for i: int in count:
		if candidates.is_empty():
			break
		var picked: BlessingData = rng.pick_weighted(candidates, weights)
		var idx := candidates.find(picked)
		if idx >= 0:
			candidates.remove_at(idx)
			weights.remove_at(idx)
		out.append(picked)
	return out

## Складывает модификаторы всех взятых благословений в один словарь.
static func aggregate(blessings: Array) -> Dictionary:
	var out: Dictionary = {}
	for b: BlessingData in blessings:
		for k: Variant in b.modifiers.keys():
			var key := StringName(k)
			if String(key).ends_with("_mult"):
				out[key] = float(out.get(key, 1.0)) * float(b.modifiers[k])
			else:
				out[key] = float(out.get(key, 0.0)) + float(b.modifiers[k])
	return out
