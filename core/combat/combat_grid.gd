class_name CombatGrid
extends RefCounted
## Сетка боя: проходимость, дистанции, линия видимости, укрытия, достижимость.
## Клетка 1.5 м, диагональ считается за 1 (правило Чебышева) — 02-combat.md, раздел 1.1.

const FLAG_WALL := 1
const FLAG_DIFFICULT := 2
const FLAG_HAZARD := 4
const FLAG_COVER_HALF := 8
const FLAG_COVER_THREE_QUARTER := 16
const FLAG_HIGH := 32

var width: int = 0
var height: int = 0
var cells: PackedByteArray = PackedByteArray()

func _init(w: int = 0, h: int = 0) -> void:
	resize(w, h)

func resize(w: int, h: int) -> void:
	width = maxi(0, w)
	height = maxi(0, h)
	cells = PackedByteArray()
	cells.resize(width * height)
	cells.fill(FLAG_WALL)

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

func index(c: Vector2i) -> int:
	return c.y * width + c.x

func flags(c: Vector2i) -> int:
	if not in_bounds(c):
		return FLAG_WALL
	return cells[index(c)]

func set_flags(c: Vector2i, value: int) -> void:
	if in_bounds(c):
		cells[index(c)] = value

func add_flag(c: Vector2i, flag: int) -> void:
	if in_bounds(c):
		cells[index(c)] = cells[index(c)] | flag

func remove_flag(c: Vector2i, flag: int) -> void:
	if in_bounds(c):
		cells[index(c)] = cells[index(c)] & ~flag

func has_flag(c: Vector2i, flag: int) -> bool:
	return (flags(c) & flag) != 0

func is_wall(c: Vector2i) -> bool:
	return has_flag(c, FLAG_WALL)

func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not is_wall(c)

func move_cost(c: Vector2i) -> int:
	return 2 if has_flag(c, FLAG_DIFFICULT) else 1

## Дистанция Чебышева в клетках.
static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var n := c + Vector2i(dx, dy)
			if in_bounds(n):
				out.append(n)
	return out

## Линия видимости по алгоритму Брезенхэма: стены блокируют.
func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	for c: Vector2i in line_cells(from, to):
		if c == from or c == to:
			continue
		if is_wall(c):
			return false
	return true

## Клетки на отрезке, включая концы.
func line_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0 := from.x
	var y0 := from.y
	var dx := absi(to.x - x0)
	var dy := -absi(to.y - y0)
	var sx := 1 if x0 < to.x else -1
	var sy := 1 if y0 < to.y else -1
	var err := dx + dy
	var guard := 0
	while true:
		out.append(Vector2i(x0, y0))
		if x0 == to.x and y0 == to.y:
			break
		guard += 1
		if guard > width * height + 8:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return out

## Бонус КБ от укрытия между атакующим и целью (02-combat.md, раздел 9).
func cover_bonus(from: Vector2i, to: Vector2i, half_ac: int, three_quarter_ac: int) -> int:
	var best := 0
	for c: Vector2i in line_cells(from, to):
		if c == from or c == to:
			continue
		if has_flag(c, FLAG_COVER_THREE_QUARTER):
			best = maxi(best, three_quarter_ac)
		elif has_flag(c, FLAG_COVER_HALF):
			best = maxi(best, half_ac)
	return best

## Достижимые клетки с бюджетом движения. blocked — занятые клетки (свои и чужие тела).
## Ведёрная очередь: стоимость шага равна 1 или 2, поэтому обход линейный.
func reachable(from: Vector2i, budget: int, blocked: Dictionary) -> Dictionary:
	var costs := {from: 0}
	if budget <= 0:
		return costs
	var buckets: Array[Array] = []
	for i: int in budget + 1:
		buckets.append([])
	buckets[0].append(from)
	for cost: int in range(0, budget + 1):
		for cur: Vector2i in buckets[cost]:
			if int(costs.get(cur, 1 << 30)) < cost:
				continue
			for n: Vector2i in neighbors(cur):
				if not is_walkable(n) or blocked.has(n):
					continue
				var nc: int = cost + move_cost(n)
				if nc > budget:
					continue
				if not costs.has(n) or nc < int(costs[n]):
					costs[n] = nc
					buckets[nc].append(n)
	return costs

## Кратчайший путь; пустой массив, если пути нет. Цель может быть занята — тогда
## возвращается путь до ближайшей соседней клетки.
func find_path(from: Vector2i, to: Vector2i, blocked: Dictionary, max_cost: int = 9999) -> Array[Vector2i]:
	if from == to:
		return []
	var costs := {from: 0}
	var came := {}
	var frontier: Array[Vector2i] = [from]
	var found := false
	while not frontier.is_empty():
		var best_i := 0
		var best_score: int = 1 << 30
		for i: int in frontier.size():
			var score: int = int(costs[frontier[i]]) + distance(frontier[i], to)
			if score < best_score:
				best_score = score
				best_i = i
		var cur: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)
		if cur == to:
			found = true
			break
		for n: Vector2i in neighbors(cur):
			if not is_walkable(n):
				continue
			if blocked.has(n) and n != to:
				continue
			var nc: int = int(costs[cur]) + move_cost(n)
			if nc > max_cost:
				continue
			if not costs.has(n) or nc < int(costs[n]):
				costs[n] = nc
				came[n] = cur
				frontier.append(n)
	if not found:
		return []
	var path: Array[Vector2i] = []
	var node := to
	while node != from:
		path.append(node)
		node = came[node]
	path.reverse()
	return path

func save_state() -> Dictionary:
	return {"w": width, "h": height, "cells": Array(cells)}

static func from_state(data: Dictionary) -> CombatGrid:
	var g := CombatGrid.new(int(data.get("w", 0)), int(data.get("h", 0)))
	var raw: Array = data.get("cells", [])
	for i: int in mini(raw.size(), g.cells.size()):
		g.cells[i] = int(raw[i])
	return g
