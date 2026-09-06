class_name ItemData
extends Resource
## Базовое описание предмета (05-items.md). Контент лежит в data/items/*.json.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var category: StringName = &"misc"      # weapon | armor | consumable | material | gem | decor
@export var rarity: StringName = &"common"      # common | uncommon | rare | epic | legendary
@export var weight: float = 1.0
@export var grid_size: Vector2i = Vector2i(1, 1)
@export var base_value: int = 10
@export var stackable: bool = false
@export var max_stack: int = 1
@export var tint: Color = Color(0.7, 0.7, 0.7)
@export var modifiers: Dictionary = {}   # бонусы владельцу: ac, attack, damage, saves
@export var tags: Array[StringName] = []
@export var available_from_version: String = "1.0"

func is_equipment() -> bool:
	return category == &"weapon" or category == &"armor"
