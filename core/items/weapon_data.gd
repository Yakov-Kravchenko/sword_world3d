class_name WeaponData
extends ItemData
## Оружие (02-combat.md, раздел про броски атаки).

@export var damage_dice: String = "1d8"
@export var damage_type: StringName = &"slashing"
@export var attack_stat: StringName = &"str"
@export var range_cells: int = 1
@export var properties: Array[StringName] = []   # two_handed | light | finesse | heavy | reach | ranged
@export var slot: StringName = &"main_hand"
@export var allowed_affix_pools: Array[StringName] = []
@export var spell_dc_bonus: int = 0

func is_ranged() -> bool:
	return range_cells > 1 or properties.has(&"ranged")

func is_two_handed() -> bool:
	return properties.has(&"two_handed")
