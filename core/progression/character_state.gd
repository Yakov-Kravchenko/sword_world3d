class_name CharacterState
extends RefCounted
## Постоянное состояние героя: снаряжение, сумка, дерево навыков, текущие HP и ячейки.

var hero_id: StringName = &""
var data: HeroData
var level: int = 1
var equipment: Dictionary = {}       # slot -> ItemInstance
var inventory: Inventory
var hp: int = 1
var spell_slots: PackedInt32Array = PackedInt32Array()
var unlocked_nodes: Array[StringName] = []
var known_spells: Array[StringName] = []
var skill_points: int = 0
var persistent_statuses: Array[Dictionary] = []
var is_dead_this_run: bool = false
## Модификаторы от дерева навыков; пересчитываются при покупке узла.
var skill_modifiers: Dictionary = {}

func stat(key: StringName) -> int:
	var base: int = int(data.base_stats.get(key, 10)) if data != null else 10
	return base + int(_sum_modifier(StringName("stat_" + String(key))))

func stat_mod(key: StringName) -> int:
	return Stats.modifier(stat(key))

func proficiency(balance: BalanceData) -> int:
	return balance.proficiency_for_level(level)

## HP не бросается случайно — фиксированная формула (02-combat.md, раздел 1.3).
func max_hp(balance: BalanceData) -> int:
	if data == null:
		return 1
	var con := stat_mod(Stats.CON)
	var avg := int(balance.hit_die_average.get(StringName(str(data.hit_die)), 5))
	var total := data.hit_die + con + (level - 1) * (avg + con)
	return maxi(1, total + int(_sum_modifier(&"max_hp")))

func armor_class() -> int:
	var body: ItemInstance = equipment.get(&"body", null)
	var dex := stat_mod(Stats.DEX)
	var ac := 10 + dex
	if body != null and body.data is ArmorData:
		var armor: ArmorData = body.data
		ac = armor.ac_base + mini(dex, armor.dex_limit)
	var shield: ItemInstance = equipment.get(&"off_hand", null)
	if shield != null and shield.data is ArmorData:
		ac += (shield.data as ArmorData).ac_bonus
	return ac + int(_sum_modifier(&"ac"))

func absorb() -> int:
	var total := 0
	for item: ItemInstance in equipment.values():
		if item != null and item.data is ArmorData:
			total += (item.data as ArmorData).absorb
	return total + int(_sum_modifier(&"absorb"))

func main_weapon() -> ItemInstance:
	return equipment.get(&"main_hand", null)

func carry_limit(balance: BalanceData) -> float:
	return balance.carry_base_kg + stat(Stats.STR) * balance.carry_per_str

## Сумма модификаторов: снаряжение + дерево навыков.
func _sum_modifier(key: StringName) -> float:
	var total: float = float(skill_modifiers.get(key, 0.0))
	for item: ItemInstance in equipment.values():
		if item == null:
			continue
		total += float(item.modifiers().get(key, 0.0))
	return total

func all_modifiers() -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in skill_modifiers.keys():
		out[StringName(k)] = float(skill_modifiers[k])
	for item: ItemInstance in equipment.values():
		if item == null:
			continue
		for k: Variant in item.modifiers().keys():
			out[StringName(k)] = float(out.get(StringName(k), 0.0)) + float(item.modifiers()[k])
	return out

func restore_full(balance: BalanceData) -> void:
	hp = max_hp(balance)
	spell_slots = balance.slots_for_level(level)
	is_dead_this_run = false
	persistent_statuses.clear()

func save_state() -> Dictionary:
	var eq := {}
	for slot: Variant in equipment.keys():
		var item: ItemInstance = equipment[slot]
		if item != null:
			eq[String(slot)] = item.save_state()
	var nodes: Array = []
	for n: StringName in unlocked_nodes:
		nodes.append(String(n))
	var spells: Array = []
	for s: StringName in known_spells:
		spells.append(String(s))
	return {"hero": String(hero_id), "level": level, "hp": hp,
		"slots": Array(spell_slots), "equipment": eq, "nodes": nodes,
		"spells": spells, "skill_points": skill_points,
		"inventory": inventory.save_state() if inventory != null else [],
		"dead": is_dead_this_run}
