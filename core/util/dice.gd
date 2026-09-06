class_name Dice
extends RefCounted
## Разбор и бросок костей вида "2d6+3", "1d8", "d20-1".

class Formula extends RefCounted:
	var count: int = 0
	var sides: int = 0
	var flat: int = 0

	func text() -> String:
		var s := ""
		if count > 0:
			s = "%dd%d" % [count, sides]
		if flat > 0:
			s += ("+%d" % flat) if not s.is_empty() else str(flat)
		elif flat < 0:
			s += str(flat)
		return s if not s.is_empty() else "0"

	func average() -> float:
		return count * (sides + 1) / 2.0 + flat

	func maximum() -> int:
		return count * sides + flat

static func parse(expr: String) -> Formula:
	var f := Formula.new()
	var s := expr.strip_edges().to_lower().replace(" ", "")
	if s.is_empty():
		return f
	var sign_split := 1
	var flat_part := ""
	var dice_part := s
	var plus := s.find("+", 1)
	var minus := s.find("-", 1)
	var cut := plus if plus != -1 else minus
	if plus != -1 and minus != -1:
		cut = mini(plus, minus)
	if cut != -1:
		dice_part = s.substr(0, cut)
		flat_part = s.substr(cut + 1)
		sign_split = 1 if s[cut] == "+" else -1
	if flat_part.is_valid_int():
		f.flat = flat_part.to_int() * sign_split
	if dice_part.contains("d"):
		var parts := dice_part.split("d")
		f.count = 1 if parts[0].is_empty() else parts[0].to_int()
		f.sides = parts[1].to_int() if parts.size() > 1 and parts[1].is_valid_int() else 0
		if f.sides <= 0:
			f.count = 0
	elif dice_part.is_valid_int():
		f.flat += dice_part.to_int()
	return f

## Бросок. crit=true удваивает количество костей (модификаторы — нет, 02-combat.md §4.1).
static func roll(expr: String, rng: RngStream, crit: bool = false) -> Dictionary:
	var f := parse(expr)
	var n := f.count * (2 if crit else 1)
	var rolls: Array[int] = []
	var total := 0
	for i: int in n:
		var r := rng.randi_range(1, f.sides)
		rolls.append(r)
		total += r
	total += f.flat
	return {"total": total, "rolls": rolls, "flat": f.flat, "formula": expr, "crit": crit}

static func average(expr: String) -> float:
	return parse(expr).average()

static func maximum(expr: String) -> int:
	return parse(expr).maximum()

static func is_valid(expr: String) -> bool:
	var f := parse(expr)
	return f.count > 0 or f.flat != 0 or expr.strip_edges() == "0"
