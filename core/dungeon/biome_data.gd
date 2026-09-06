class_name BiomeData
extends Resource
## Биом (04-dungeon.md, раздел 4.1).

@export var id: StringName = &""
@export var display_name: String = ""
@export var tier_min: int = 1
@export var tier_max: int = 1
@export var deep_variant_of: StringName = &""
@export var threat_line: String = ""
@export var reward_line: String = ""
@export var risk_line: String = ""
@export var mechanic_id: StringName = &""
@export var floor_color: Color = Color(0.25, 0.24, 0.22)
@export var wall_color: Color = Color(0.18, 0.17, 0.16)
@export var fog_color: Color = Color(0.07, 0.07, 0.09)
@export var ambient_color: Color = Color(0.1, 0.11, 0.13)
@export var fog_density: float = 0.06
@export var enemy_pool: Array[StringName] = []
@export var enemy_weights: PackedFloat32Array = PackedFloat32Array()
@export var elite_affix_pool: Array[StringName] = []
@export var crystal_id: StringName = &""
@export var trap_density: float = 0.1
@export var graph_weights: Dictionary = {}
@export var loot_modifier: Dictionary = {}
@export var room_count_min: int = 8
@export var room_count_max: int = 14
@export var available_from_version: String = "1.0"

func is_deep() -> bool:
	return deep_variant_of != &""
