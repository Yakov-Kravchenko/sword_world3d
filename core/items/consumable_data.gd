class_name ConsumableData
extends ItemData
## Расходники: зелья, антидоты, бинты, факелы (05-items.md).

@export var effect: StringName = &"heal"    # heal | cure_status | restore_slot | torch | buff
@export var dice: String = "2d4+2"
@export var status_id: StringName = &""
@export var use_time: StringName = &"bonus" # action | bonus | free
@export var torch_ticks: int = 0
@export var limit_group: StringName = &""   # potion | antidote — лимиты на героя
