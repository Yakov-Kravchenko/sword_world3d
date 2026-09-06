class_name SpellData
extends Resource
## Заклинание (02-combat.md раздел 6, 03-characters.md раздел 6).

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var level: int = 0                      # 0 = заговор
@export var cast_time: StringName = &"action"   # action | bonus | reaction | ritual
@export var range_cells: int = 12
@export var shape: StringName = &"single"       # single | cone | sphere | line | self
@export var shape_size: int = 0
@export var target_team: StringName = &"enemy"  # enemy | ally | self | any | point
@export var max_targets: int = 1
@export var attack_roll: bool = false
@export var save_stat: StringName = &""
@export var save_for_half: bool = false
@export var damage_dice: String = ""
@export var damage_type: StringName = &"fire"
@export var heal_dice: String = ""
@export var heal_adds_casting_mod: bool = false
@export var apply_status: StringName = &""
@export var remove_status_count: int = 0
@export var concentration: bool = false
@export var upcast_dice: String = ""
@export var tags: Array[StringName] = []
@export var available_from_version: String = "1.0"

func is_cantrip() -> bool:
	return level == 0
