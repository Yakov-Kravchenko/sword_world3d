class_name ItemInstance
extends RefCounted
## Конкретный предмет в мире: база + уровень улучшения + аффиксы + вставленные кристаллы
## (05-items.md).

var uid: int = 0
var data: ItemData
var quantity: int = 1
var upgrade_level: int = 0
var affixes: Array[AffixData] = []
var sockets: Array[StringName] = []
var rotated: bool = false

static var _next_uid: int = 1

static func create(item_data: ItemData, count: int = 1) -> ItemInstance:
	var inst := ItemInstance.new()
	inst.uid = _next_uid
	_next_uid += 1
	inst.data = item_data
	inst.quantity = count
	return inst

func id() -> StringName:
	return data.id if data != null else &""

func display_name() -> String:
	if data == null:
		return "?"
	var name := data.display_name
	for a: AffixData in affixes:
		if a.kind == &"prefix":
			name = "%s %s" % [a.display_name, name.to_lower()]
	for a: AffixData in affixes:
		if a.kind == &"suffix":
			name = "%s %s" % [name, a.display_name]
	if upgrade_level > 0:
		name += " +%d" % upgrade_level
	return name

func grid_size() -> Vector2i:
	var s: Vector2i = data.grid_size if data != null else Vector2i.ONE
	return Vector2i(s.y, s.x) if rotated else s

func weight() -> float:
	return (data.weight if data != null else 0.0) * quantity

func is_weapon() -> bool:
	return data is WeaponData

func is_armor() -> bool:
	return data is ArmorData

func is_consumable() -> bool:
	return data is ConsumableData

## Суммарные модификаторы: база предмета + аффиксы + бонусы улучшения.
func modifiers() -> Dictionary:
	var out: Dictionary = {}
	if data != null:
		for k: Variant in data.modifiers.keys():
			out[StringName(k)] = float(out.get(StringName(k), 0.0)) + float(data.modifiers[k])
	for a: AffixData in affixes:
		for k: Variant in a.modifiers.keys():
			out[StringName(k)] = float(out.get(StringName(k), 0.0)) + float(a.modifiers[k])
	if upgrade_level > 0:
		if is_weapon():
			out[&"attack"] = float(out.get(&"attack", 0.0)) + upgrade_hit_bonus()
			out[&"damage"] = float(out.get(&"damage", 0.0)) + upgrade_damage_bonus()
		elif is_armor():
			out[&"ac"] = float(out.get(&"ac", 0.0)) + upgrade_ac_bonus()
	return out

## Кривая улучшения +1...+8: попадание растёт медленнее урона (05-items.md).
func upgrade_hit_bonus() -> int:
	return int(ceil(upgrade_level / 2.0))

func upgrade_damage_bonus() -> int:
	return upgrade_level

func upgrade_ac_bonus() -> int:
	return int(ceil(upgrade_level / 2.0))

## Дополнительные кости урона от аффиксов: [{dice, type}]
func bonus_damage_dice() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a: AffixData in affixes:
		if not a.damage_bonus_dice.is_empty():
			out.append({"dice": a.damage_bonus_dice, "type": String(a.damage_bonus_type)})
	return out

func value() -> int:
	var base := (data.base_value if data != null else 0) * quantity
	var affix_mult := 1.0 + 0.35 * affixes.size()
	var upgrade_mult := 1.0 + 0.25 * upgrade_level
	return int(round(base * affix_mult * upgrade_mult))

func save_state() -> Dictionary:
	var af: Array = []
	for a: AffixData in affixes:
		af.append(String(a.id))
	var sk: Array = []
	for s: StringName in sockets:
		sk.append(String(s))
	return {"id": String(id()), "qty": quantity, "upgrade": upgrade_level,
		"affixes": af, "sockets": sk, "rotated": rotated}
