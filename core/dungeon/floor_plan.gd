class_name FloorPlan
extends RefCounted
## Результат генерации этажа: чистые данные, из которых FloorBuilder строит ноды.

const TILE_WALL := 0
const TILE_FLOOR := 1
const TILE_DOOR := 2
const TILE_STAIRS_DOWN := 3
const TILE_ENTRANCE := 4
const TILE_SECRET_DOOR := 5

const ROLE_ENTRANCE := &"entrance"
const ROLE_COMBAT := &"combat"
const ROLE_EMPTY := &"empty"
const ROLE_TREASURE := &"treasure"
const ROLE_TRAPS := &"traps"
const ROLE_ALTAR := &"altar"
const ROLE_EVENT := &"event"
const ROLE_GUARDIAN := &"guardian"
const ROLE_HERALD := &"herald"
const ROLE_BOSS := &"boss"
const ROLE_SECRET := &"secret"

class Room extends RefCounted:
	var index: int = 0
	var rect: Rect2i = Rect2i()
	var role: StringName = ROLE_EMPTY
	var connections: Array[int] = []
	var cleared: bool = false
	var looted: bool = false

	func center() -> Vector2i:
		return rect.position + rect.size / 2

	func contains(cell: Vector2i) -> bool:
		return rect.has_point(cell)

	func save_state() -> Dictionary:
		return {"index": index, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"role": String(role), "cleared": cleared, "looted": looted}

var width: int = 0
var height: int = 0
var tiles: PackedByteArray = PackedByteArray()
var rooms: Array[Room] = []
var entrance_cell: Vector2i = Vector2i.ZERO
var exit_cell: Vector2i = Vector2i.ZERO
var floor_index: int = 1
var biome_id: StringName = &""
var run_seed: int = 0
## Встречи: {"room": int, "enemies": Array[StringName], "cells": Array[Vector2i], "kind": StringName}
var encounters: Array[Dictionary] = []
## Интерактивные объекты: {"kind": chest|altar|trap|secret, "cell": Vector2i, "table": StringName}
var props: Array[Dictionary] = []
var static_lights: Array[Vector2i] = []
var generation_attempts: int = 1

func _init(w: int = 0, h: int = 0) -> void:
	width = w
	height = h
	tiles = PackedByteArray()
	tiles.resize(w * h)
	tiles.fill(TILE_WALL)

func tile(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return TILE_WALL
	return tiles[cell.y * width + cell.x]

func set_tile(cell: Vector2i, value: int) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return
	tiles[cell.y * width + cell.x] = value

func is_floor(cell: Vector2i) -> bool:
	return tile(cell) != TILE_WALL

func room_at(cell: Vector2i) -> Room:
	for r: Room in rooms:
		if r.contains(cell):
			return r
	return null

func room_by_role(role: StringName) -> Room:
	for r: Room in rooms:
		if r.role == role:
			return r
	return null

## Сетка боя для комнаты с запасом в 1 клетку по краям.
func build_combat_grid(area: Rect2i) -> CombatGrid:
	var grid := CombatGrid.new(width, height)
	for y: int in height:
		for x: int in width:
			var c := Vector2i(x, y)
			if area.has_point(c) and is_floor(c):
				grid.set_flags(c, 0)
	return grid

func floor_cells_in(area: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			if is_floor(c):
				out.append(c)
	return out

func encounter_for_room(room_index: int) -> Dictionary:
	for e: Dictionary in encounters:
		if int(e.get("room", -1)) == room_index:
			return e
	return {}

func save_state() -> Dictionary:
	var rs: Array = []
	for r: Room in rooms:
		rs.append(r.save_state())
	return {"floor": floor_index, "biome": String(biome_id), "seed": run_seed, "rooms": rs}
