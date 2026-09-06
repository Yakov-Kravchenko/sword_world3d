class_name Stats
extends RefCounted
## Шесть характеристик и производные значения (02-combat.md §1.2–1.3).

const STR := &"str"
const DEX := &"dex"
const CON := &"con"
const INT := &"int"
const WIS := &"wis"
const CHA := &"cha"

const ALL: Array[StringName] = [STR, DEX, CON, INT, WIS, CHA]

const RU := {
	&"str": "СИЛ", &"dex": "ЛОВ", &"con": "ТЕЛ",
	&"int": "ИНТ", &"wis": "МДР", &"cha": "ХАР",
}

static func modifier(value: int) -> int:
	return int(floor((value - 10) / 2.0))

static func empty() -> Dictionary:
	var d := {}
	for s: StringName in ALL:
		d[s] = 10
	return d

static func from_dict(src: Dictionary) -> Dictionary:
	var d := empty()
	for k: Variant in src.keys():
		var key := StringName(k)
		if ALL.has(key):
			d[key] = int(src[k])
	return d

## Типы урона (02-combat.md §4.2).
const DAMAGE_TYPES: Array[StringName] = [
	&"slashing", &"piercing", &"bludgeoning",
	&"fire", &"cold", &"lightning", &"acid", &"poison",
	&"necrotic", &"psychic", &"radiant",
]

const DAMAGE_RU := {
	&"slashing": "рубящий", &"piercing": "колющий", &"bludgeoning": "дробящий",
	&"fire": "огонь", &"cold": "холод", &"lightning": "молния",
	&"acid": "кислота", &"poison": "яд", &"necrotic": "некротический",
	&"psychic": "психический", &"radiant": "священный",
}
