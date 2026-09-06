class_name SkillNodeData
extends Resource
## Узел дерева навыков (03-characters.md, раздел 4).

@export var id: StringName = &""
@export var hero_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var branch: StringName = &"trunk"
@export var row: int = 1
@export var requires: Array[StringName] = []
@export var skill_points: int = 1
@export var modifiers: Dictionary = {}
@export var grants_ability: StringName = &""
@export var grants_spell: StringName = &""
@export var available_from_version: String = "1.0"
