class_name LightService
extends RefCounted
## Освещённость считается логически, а не по рендеру (02-combat.md, раздел 8.3).
## Результат кэшируется на раунд.

const BRIGHT := 0
const DIM := 1
const DARK := 2

var grid: CombatGrid
var bright_cells: int = 6
var dim_cells: int = 12
## Источники: {cell: Vector2i, bright: int, dim: int}
var sources: Array[Dictionary] = []
var _cache: Dictionary = {}

func _init(g: CombatGrid = null, bright: int = 6, dim: int = 12) -> void:
	grid = g
	bright_cells = bright
	dim_cells = dim

func clear_cache() -> void:
	_cache.clear()

func set_sources(list: Array[Dictionary]) -> void:
	sources = list
	clear_cache()

func add_source(cell: Vector2i, bright: int = -1, dim: int = -1) -> void:
	sources.append({"cell": cell, "bright": bright if bright >= 0 else bright_cells,
		"dim": dim if dim >= 0 else dim_cells})
	clear_cache()

func level_at(cell: Vector2i) -> int:
	if _cache.has(cell):
		return _cache[cell]
	var best := DARK
	for s: Dictionary in sources:
		var origin: Vector2i = s["cell"]
		var d := CombatGrid.distance(origin, cell)
		if d > int(s["dim"]):
			continue
		if grid != null and not grid.has_line_of_sight(origin, cell):
			continue
		if d <= int(s["bright"]):
			best = BRIGHT
			break
		best = mini(best, DIM)
	_cache[cell] = best
	return best

## Видит ли актёр цель с учётом тёмного зрения (02-combat.md, раздел 8.1).
func can_see(viewer: CombatActor, target_cell: Vector2i, darkvision_cells: int) -> bool:
	if grid != null and not grid.has_line_of_sight(viewer.cell, target_cell):
		return false
	var lvl := level_at(target_cell)
	if lvl != DARK:
		return true
	if viewer.darkvision:
		return CombatGrid.distance(viewer.cell, target_cell) <= darkvision_cells
	return CombatGrid.distance(viewer.cell, target_cell) <= 2

static func level_name(level: int) -> String:
	match level:
		BRIGHT: return "яркий свет"
		DIM: return "тусклый свет"
		_: return "темнота"
