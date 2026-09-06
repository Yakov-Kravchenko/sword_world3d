class_name ActionResult
extends RefCounted
## Полностью разрешённое действие. CombatView только проигрывает его как анимацию
## (08-architecture.md, раздел 6): состояние уже изменено до начала анимации.

var actor_id: StringName = &""
var action_id: StringName = &""
var targets: Array[StringName] = []
var ok: bool = true
var error: String = ""
## Броски: {kind, formula, natural, total, dc, success, mode}
var rolls: Array[Dictionary] = []
## Урон: {target, amount, type, crit, killed, downed}
var damage_events: Array[Dictionary] = []
## Статусы: {target, status, stacks, applied, removed}
var status_events: Array[Dictionary] = []
## Перемещение актёра по клеткам.
var movement: Array[Vector2i] = []
var resources_spent: Dictionary = {}
var log_lines: Array[String] = []
## Побочные эффекты для представления: vfx, звук, смерть.
var effects: Array[Dictionary] = []

static func failure(actor: StringName, action: StringName, message: String) -> ActionResult:
	var r := ActionResult.new()
	r.actor_id = actor
	r.action_id = action
	r.ok = false
	r.error = message
	return r

func add_log(line: String) -> void:
	log_lines.append(line)

func total_damage() -> int:
	var t := 0
	for d: Dictionary in damage_events:
		t += int(d.get("amount", 0))
	return t

func killed_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for d: Dictionary in damage_events:
		if bool(d.get("killed", false)):
			out.append(StringName(d.get("target", "")))
	return out
