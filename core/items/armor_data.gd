class_name ArmorData
extends ItemData
## Броня и щиты (02-combat.md, производные значения).

@export var ac_base: int = 10
@export var dex_limit: int = 99          # сколько ЛОВ-мода засчитывается
@export var ac_bonus: int = 0            # щит и мелкие бонусы
@export var slot: StringName = &"body"   # body | off_hand | trinket
@export var min_str: int = 0
@export var stealth_disadvantage: bool = false
@export var absorb: int = 0              # поглощение, вычитается после модификатора типа
@export var allowed_affix_pools: Array[StringName] = []

func is_shield() -> bool:
	return slot == &"off_hand"
