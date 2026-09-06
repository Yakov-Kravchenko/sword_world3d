class_name CombatState
extends RefCounted
## Данные боя. Никакой логики принятия решений — только состояние и запросы к нему.

const PHASE_IDLE := &"idle"
const PHASE_TURN := &"turn"
const PHASE_ENDED := &"ended"

var grid: CombatGrid
var light: LightService
var balance: BalanceData
var rng: RngStream

var actors: Dictionary = {}                 # StringName -> CombatActor
var initiative: Array[StringName] = []      # порядок ходов на весь бой
var turn_index: int = 0
var round_number: int = 1
var phase: StringName = PHASE_IDLE
var victory: bool = false
var log_lines: Array[String] = []
var combat_index: int = 0
## Справочники контента, переданные игровым слоем (core не знает про автозагрузки).
var status_db: Dictionary = {}
var spell_db: Dictionary = {}
## Отладка, которую включает игровой слой. Для core это просто число и флаг —
## про «режим разработчика» правила ничего не знают.
## dev_damage: если больше нуля, атака героя наносит столько вместо своего броска.
## dev_always_hit: бросок атаки героя считается попаданием.
var dev_damage: int = 0
var dev_always_hit: bool = false

func add_actor(actor: CombatActor) -> void:
	actors[actor.id] = actor

func get_actor(id: StringName) -> CombatActor:
	return actors.get(id, null)

func current_actor() -> CombatActor:
	if initiative.is_empty():
		return null
	return get_actor(initiative[turn_index % initiative.size()])

func all_actors() -> Array[CombatActor]:
	var out: Array[CombatActor] = []
	for a: CombatActor in actors.values():
		out.append(a)
	return out

func team_actors(team: int, alive_only: bool = true) -> Array[CombatActor]:
	var out: Array[CombatActor] = []
	for a: CombatActor in actors.values():
		if a.team != team:
			continue
		if alive_only and not a.is_alive():
			continue
		out.append(a)
	return out

## Может ли актёр встать так, чтобы занять клетку cell: все нужные клетки
## проходимы и свободны. Одна клетка — один персонаж (02-combat.md, раздел 1.1).
func can_occupy(actor: CombatActor, cell: Vector2i) -> bool:
	for dy: int in actor.size_cells:
		for dx: int in actor.size_cells:
			var c := cell + Vector2i(dx, dy)
			if grid != null and not grid.is_walkable(c):
				return false
			var other := actor_at(c)
			if other != null and other.id != actor.id:
				return false
	return true

## Клетки, занятые телами (для путей и размещения).
func blocked_cells(exclude: StringName = &"") -> Dictionary:
	var out := {}
	for a: CombatActor in actors.values():
		if a.id == exclude or not a.is_alive():
			continue
		for c: Vector2i in a.occupied_cells():
			out[c] = a.id
	return out

func actor_at(cell: Vector2i) -> CombatActor:
	for a: CombatActor in actors.values():
		if not a.is_alive():
			continue
		if a.occupied_cells().has(cell):
			return a
	return null

func is_over() -> bool:
	return party_wiped() or team_actors(CombatActor.TEAM_ENEMY).is_empty()

func party_wiped() -> bool:
	for a: CombatActor in team_actors(CombatActor.TEAM_PARTY):
		if not a.is_down:
			return false
	return true

## Сколько союзников цели стоят вплотную к ней — для правила окружения.
func adjacent_enemies_of(target: CombatActor) -> int:
	var count := 0
	for a: CombatActor in actors.values():
		if not a.is_alive() or a.is_down or a.team == target.team:
			continue
		if CombatGrid.distance(a.cell, target.cell) <= 1:
			count += 1
	return count

## Сколько врагов команды team стоят вплотную к клетке.
func adjacent_enemies_of_cell(cell_pos: Vector2i, team: int) -> int:
	var count := 0
	for a: CombatActor in actors.values():
		if not a.is_alive() or a.is_down or a.team == team:
			continue
		if CombatGrid.distance(a.cell, cell_pos) <= 1:
			count += 1
	return count

func add_log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 400:
		log_lines.remove_at(0)

func save_state() -> Dictionary:
	var acts: Array = []
	for a: CombatActor in actors.values():
		acts.append(a.save_state())
	var order: Array = []
	for id: StringName in initiative:
		order.append(String(id))
	return {
		"round": round_number, "turn": turn_index, "phase": String(phase),
		"initiative": order, "actors": acts, "rng": rng.save_state() if rng else {},
		"combat_index": combat_index,
	}
