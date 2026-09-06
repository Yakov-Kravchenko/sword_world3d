class_name StatusData
extends Resource
## Описание статусного эффекта (02-combat.md, раздел 7). Все 17 статусов — в data/statuses.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var stackable: bool = false
@export var max_stacks: int = 1
@export var duration_rounds: int = 2
@export var is_debuff: bool = true
@export var tick_dice: String = ""
@export var tick_damage_type: StringName = &"poison"
@export var tick_per_stack: bool = false
@export var modifiers: Dictionary = {}
@export var skip_turn: bool = false
@export var no_reaction: bool = false
@export var no_bonus_action: bool = false
@export var attacks_have_disadvantage: bool = false
@export var incoming_have_advantage: bool = false
@export var incoming_melee_auto_crit: bool = false
@export var blocks_movement: bool = false
@export var prevents_approach: bool = false
@export var save_stat: StringName = &""
@export var save_dc: int = 0
@export var removed_by_damage_types: Array[StringName] = []
@export var persists_after_combat: bool = false
@export var tags: Array[StringName] = []
