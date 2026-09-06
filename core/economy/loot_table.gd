class_name LootTable
extends Resource
## Таблица дропа (07-economy.md).

@export var id: StringName = &""
@export var gold_dice: String = "2d6"
@export var ore_chance: float = 0.2
@export var ore_id: StringName = &"ore_iron"
@export var ore_dice: String = "1d3"
@export var crystal_chance: float = 0.03
@export var item_chance: float = 0.25
@export var item_pool: Array[StringName] = []
@export var item_weights: PackedFloat32Array = PackedFloat32Array()
@export var guaranteed_items: Array[StringName] = []
