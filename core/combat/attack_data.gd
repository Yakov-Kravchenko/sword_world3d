class_name AttackData
extends Resource
## Атака из статблока врага (02-combat.md, раздел 10.1).

@export var id: StringName = &""
@export var display_name: String = ""
@export var attack_bonus: int = 3
@export var attack_stat: StringName = &""     # пусто = плоский бонус из статблока
@export var uses_proficiency: bool = false
@export var adds_stat_to_damage: bool = false
@export var damage_dice: String = "1d6"
@export var damage_type: StringName = &"slashing"
@export var range_cells: int = 1
@export var on_hit_status: StringName = &""
@export var on_hit_status_dc: int = 0
@export var save_stat: StringName = &""
@export var area_radius: int = 0
