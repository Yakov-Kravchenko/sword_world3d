class_name AffixRoller
extends RefCounted
## Навешивание аффиксов при генерации предмета (05-items.md, раздел 4).

const RARITY_ORDER: Array[StringName] = [&"common", &"uncommon", &"rare", &"epic", &"legendary"]
const AFFIX_COUNT := {&"common": 0, &"uncommon": 1, &"rare": 2, &"epic": 3, &"legendary": 4}

var affix_db: Array = []
var max_tier: int = 4

func _init(affixes: Array, tier_cap: int = 4) -> void:
	affix_db = affixes
	max_tier = tier_cap

## Редкость по глубине: чем глубже, тем выше шанс сильных предметов.
static func roll_rarity(rng: RngStream, depth: int) -> StringName:
	var d: float = clampf(depth / 20.0, 0.0, 1.0)
	var weights := [
		60.0 - 30.0 * d,
		25.0 + 5.0 * d,
		10.0 + 12.0 * d,
		4.0 + 9.0 * d,
		1.0 + 4.0 * d,
	]
	return rng.pick_weighted(RARITY_ORDER, weights)

## Максимальный тир аффикса растёт с глубиной, но не выше потолка из balance.
func tier_cap_for_depth(depth: int) -> int:
	return clampi(1 + int(floor(depth / 5.0)), 1, max_tier)

func candidates(pools: Array[StringName], depth: int, taken: Array[AffixData]) -> Array:
	var cap := tier_cap_for_depth(depth)
	var out: Array = []
	for a: AffixData in affix_db:
		if a.tier > cap:
			continue
		if taken.has(a):
			continue
		var matched := false
		for p: StringName in a.pools:
			if pools.has(p) or p == &"any":
				matched = true
				break
		if matched:
			out.append(a)
	return out

## Навешивает аффиксы на предмет по его редкости.
func apply(item: ItemInstance, pools: Array[StringName], depth: int, rng: RngStream) -> void:
	var count: int = int(AFFIX_COUNT.get(item.data.rarity, 0))
	for i: int in count:
		var options := candidates(pools, depth, item.affixes)
		if options.is_empty():
			return
		var weights: Array = []
		for a: AffixData in options:
			weights.append(a.weight)
		var picked: AffixData = rng.pick_weighted(options, weights)
		if picked != null:
			item.affixes.append(picked)
