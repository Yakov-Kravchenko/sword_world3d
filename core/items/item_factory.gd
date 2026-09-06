class_name ItemFactory
extends RefCounted
## Создание предметов и разбор таблиц дропа (05-items.md, 07-economy.md).

var item_db: Dictionary = {}      # id -> ItemData
var roller: AffixRoller
var balance: BalanceData

func _init(items: Dictionary, affixes: Array, balance_data: BalanceData) -> void:
	item_db = items
	balance = balance_data
	roller = AffixRoller.new(affixes, balance_data.max_affix_tier)

func create(item_id: StringName, count: int = 1) -> ItemInstance:
	var data: ItemData = item_db.get(item_id, null)
	if data == null:
		return null
	return ItemInstance.create(data, count)

## Предмет со случайной редкостью и аффиксами по глубине.
func create_rolled(item_id: StringName, depth: int, rng: RngStream) -> ItemInstance:
	var inst := create(item_id)
	if inst == null or not inst.data.is_equipment():
		return inst
	inst.data = inst.data.duplicate()
	inst.data.rarity = AffixRoller.roll_rarity(rng, depth)
	var pools: Array[StringName] = []
	if inst.data is WeaponData:
		pools = (inst.data as WeaponData).allowed_affix_pools
	elif inst.data is ArmorData:
		pools = (inst.data as ArmorData).allowed_affix_pools
	roller.apply(inst, pools, depth, rng)
	return inst

## Разбор таблицы дропа. modifiers — множители биома и благословений.
func roll_loot(table: LootTable, depth: int, rng: RngStream,
		modifiers: Dictionary = {}) -> Dictionary:
	var gold_mult: float = float(modifiers.get(&"gold", 1.0))
	var ore_mult: float = float(modifiers.get(&"ore", 1.0))
	var crystal_mult: float = float(modifiers.get(&"crystals", 1.0))
	var result := {"gold": 0, "materials": {}, "items": []}
	result["gold"] = int(round(int(Dice.roll(table.gold_dice, rng)["total"]) * gold_mult))
	if rng.randf_value() < table.ore_chance * ore_mult:
		var amount := int(Dice.roll(table.ore_dice, rng)["total"])
		result["materials"][table.ore_id] = int(result["materials"].get(table.ore_id, 0)) + amount
	if rng.randf_value() < table.crystal_chance * crystal_mult:
		var crystal: StringName = StringName(modifiers.get(&"crystal_id", &"crystal_bone"))
		result["materials"][crystal] = int(result["materials"].get(crystal, 0)) + 1
	for guaranteed: StringName in table.guaranteed_items:
		var inst := create_rolled(guaranteed, depth, rng)
		if inst != null:
			result["items"].append(inst)
	if rng.randf_value() < table.item_chance and not table.item_pool.is_empty():
		var weights: Array = []
		for i: int in table.item_pool.size():
			weights.append(float(table.item_weights[i]) if i < table.item_weights.size() else 1.0)
		var picked: StringName = rng.pick_weighted(table.item_pool, weights)
		var inst := create_rolled(picked, depth, rng)
		if inst != null:
			result["items"].append(inst)
	return result

## Стоимость улучшения предмета на следующий уровень (07-economy.md).
func upgrade_cost(item: ItemInstance) -> Dictionary:
	var next_level := item.upgrade_level + 1
	var gold := int(round(balance.upgrade_cost_base * pow(float(next_level), balance.upgrade_cost_exp)))
	var ore_id: StringName = &"ore_iron"
	if next_level > 6:
		ore_id = &"ore_star"
	elif next_level > 3:
		ore_id = &"ore_silver"
	return {"gold": gold, "ore_id": ore_id, "ore": next_level, "level": next_level}

func upgrade_chance(level: int) -> float:
	var idx := clampi(level - 1, 0, maxi(0, balance.upgrade_success_chance.size() - 1))
	if balance.upgrade_success_chance.is_empty():
		return 1.0
	return balance.upgrade_success_chance[idx]
