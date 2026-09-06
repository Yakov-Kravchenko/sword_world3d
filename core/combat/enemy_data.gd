class_name EnemyData
extends Resource
## Статблок врага (02-combat.md, раздел 10.1).

@export var id: StringName = &""
@export var display_name: String = ""
@export var biomes: Array[StringName] = []
@export var depth_tier: int = 1
@export var max_hp: int = 10
@export var armor_class: int = 12
@export var speed_cells: int = 6
@export var size_cells: int = 1
@export var stats: Dictionary = {}
@export var proficiency_bonus: int = 2
@export var save_proficiencies: Array[StringName] = []
@export var attacks: Array[AttackData] = []
@export var resistances: Array[StringName] = []
@export var vulnerabilities: Array[StringName] = []
@export var immunities: Array[StringName] = []
@export var status_immunities: Array[StringName] = []
@export var darkvision: bool = true
@export var behavior: StringName = &"aggressive"
@export var morale_threshold: float = 0.0
@export var loot_table: StringName = &"common"
@export var danger_points: int = 6
@export var tint: Color = Color(0.6, 0.25, 0.25)
@export var is_elite: bool = false
@export var is_boss: bool = false
