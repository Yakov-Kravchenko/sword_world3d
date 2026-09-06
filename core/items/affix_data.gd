class_name AffixData
extends Resource
## Аффикс предмета: префикс или суффикс (05-items.md).

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: StringName = &"suffix"     # prefix | suffix
@export var pools: Array[StringName] = []    # weapon | armor | any
@export var tier: int = 1
@export var weight: float = 1.0
@export var modifiers: Dictionary = {}
@export var damage_bonus_dice: String = ""
@export var damage_bonus_type: StringName = &""
@export var tags: Array[StringName] = []
