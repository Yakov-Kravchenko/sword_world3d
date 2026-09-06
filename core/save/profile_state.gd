class_name ProfileState
extends RefCounted
## Мета-прогресс профиля (08-architecture.md, раздел 7.1). Сохраняется всегда,
## гибель отряда его не трогает.

const SCHEMA_VERSION := 1

var schema_version: int = SCHEMA_VERSION
var profile_seed: int = 0
var main_hero_id: StringName = &"hald"
var day: int = 1
var party_level: int = 1
var gold: int = 0
var materials: Dictionary = {}
var storage: Array[ItemInstance] = []
var party: Array[CharacterState] = []
var unlocked_biomes: Array[StringName] = []
var building_levels: Dictionary = {"forge": 1, "training": 1, "shop": 1, "garden": 1, "storage": 1}
var decor: Array[Dictionary] = []
var lore: Array[StringName] = []
var achievements: Array[StringName] = []
var stats: Dictionary = {"runs": 0, "deepest_floor": 0, "bosses": 0, "kills": 0,
	"gold_earned": 0, "extractions": 0, "playtime": 0.0}

func member(hero_id: StringName) -> CharacterState:
	for c: CharacterState in party:
		if c.hero_id == hero_id:
			return c
	return null

func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	if amount > 0:
		stats["gold_earned"] = int(stats.get("gold_earned", 0)) + amount

func add_material(id: StringName, amount: int) -> void:
	materials[id] = maxi(0, int(materials.get(id, 0)) + amount)

func material_count(id: StringName) -> int:
	return int(materials.get(id, 0))

func spend(cost_gold: int, cost_materials: Dictionary = {}) -> Result:
	if gold < cost_gold:
		return Result.fail("Не хватает золота")
	for id: Variant in cost_materials.keys():
		if material_count(StringName(id)) < int(cost_materials[id]):
			return Result.fail("Не хватает материалов")
	gold -= cost_gold
	for id: Variant in cost_materials.keys():
		add_material(StringName(id), -int(cost_materials[id]))
	return Result.good()

## Требование по уровню выполнено? Проверяется в тренировочном зале.
func level_requirement_met(target_level: int, balance: BalanceData) -> bool:
	var deepest := int(stats.get("deepest_floor", 0))
	var bosses := int(stats.get("bosses", 0))
	match target_level:
		2: return deepest >= 3
		3: return deepest >= 6
		4: return deepest >= 5
		5: return bosses >= 1
		6: return deepest >= 14
		7: return deepest >= 15
		8: return deepest >= 18
		9: return unlocked_biomes.size() >= 5
	return target_level <= balance.max_party_level

func save_state() -> Dictionary:
	var members: Array = []
	for c: CharacterState in party:
		members.append(c.save_state())
	var store: Array = []
	for i: ItemInstance in storage:
		store.append(i.save_state())
	var mats := {}
	for k: Variant in materials.keys():
		mats[String(k)] = int(materials[k])
	var biomes: Array = []
	for b: StringName in unlocked_biomes:
		biomes.append(String(b))
	return {"schema_version": schema_version, "profile_seed": profile_seed,
		"main_hero": String(main_hero_id), "day": day, "party_level": party_level,
		"gold": gold, "materials": mats, "storage": store, "party": members,
		"unlocked_biomes": biomes, "buildings": building_levels.duplicate(),
		"decor": decor.duplicate(true), "stats": stats.duplicate(),
		"achievements": achievements.duplicate()}
