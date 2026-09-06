class_name HeroData
extends Resource
## Один из четырёх героев (03-characters.md, раздел 2).

@export var id: StringName = &""
@export var display_name: String = ""
@export var archetype: String = ""
@export var role: String = ""
@export var hit_die: int = 8
@export var primary_stat: StringName = &"str"
@export var casting_stat: StringName = &""
@export var save_proficiencies: Array[StringName] = []
@export var base_stats: Dictionary = {}
@export var starting_equipment: Array[StringName] = []
@export var starting_inventory: Array[StringName] = []
@export var starting_spells: Array[StringName] = []
@export var abilities: Array[StringName] = []
@export var tint: Color = Color(0.8, 0.8, 0.8)
@export var house_description: String = ""
