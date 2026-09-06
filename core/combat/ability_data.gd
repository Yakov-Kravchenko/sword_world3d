class_name AbilityData
extends Resource
## Классовая способность героя (03-characters.md, раздел 2).

@export var id: StringName = &""
@export var hero_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var cost: StringName = &"action"      # action | bonus | reaction | free
@export var uses_per_rest: int = 0            # 0 = без ограничения
@export var target_kind: StringName = &"none" # none | enemy | ally | self
@export var range_cells: int = 1
@export var available_from_version: String = "1.0"
