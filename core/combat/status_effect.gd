class_name StatusEffect
extends RefCounted
## Экземпляр статуса на конкретном актёре (02-combat.md, раздел 7).

var data: StatusData
var stacks: int = 1
var rounds_left: int = 1
var source_id: StringName = &""
var save_dc: int = 0

func _init(status: StatusData = null, source: StringName = &"", dc: int = 0) -> void:
	data = status
	source_id = source
	save_dc = dc if dc > 0 else (status.save_dc if status != null else 0)
	if status != null:
		rounds_left = status.duration_rounds

func id() -> StringName:
	return data.id if data != null else &""

func modifier(key: StringName) -> float:
	if data == null:
		return 0.0
	var v: float = float(data.modifiers.get(key, 0.0))
	return v * (stacks if data.tick_per_stack else 1)

func save_state() -> Dictionary:
	return {"id": String(id()), "stacks": stacks, "rounds": rounds_left,
		"source": String(source_id), "dc": save_dc}
