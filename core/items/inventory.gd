class_name Inventory
extends RefCounted
## Сетка с пределом веса и лимитами расходников (05-items.md, раздел 6).

var width: int = 10
var height: int = 8
var carry_limit: float = 30.0
## uid -> {item: ItemInstance, pos: Vector2i}
var slots: Dictionary = {}
var _occupancy: Dictionary = {}   # Vector2i -> uid

func _init(w: int = 10, h: int = 8, limit: float = 30.0) -> void:
	width = w
	height = h
	carry_limit = limit

func items() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for entry: Dictionary in slots.values():
		out.append(entry["item"])
	return out

func total_weight() -> float:
	var w := 0.0
	for item: ItemInstance in items():
		w += item.weight()
	return w

func is_overloaded() -> bool:
	return total_weight() > carry_limit

func cells_for(item: ItemInstance, pos: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var size := item.grid_size()
	for dy: int in size.y:
		for dx: int in size.x:
			out.append(pos + Vector2i(dx, dy))
	return out

func can_place(item: ItemInstance, pos: Vector2i, ignore_uid: int = -1) -> bool:
	for c: Vector2i in cells_for(item, pos):
		if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height:
			return false
		var occupant: Variant = _occupancy.get(c, null)
		if occupant != null and int(occupant) != ignore_uid:
			return false
	return true

func find_free_position(item: ItemInstance) -> Vector2i:
	for y: int in height:
		for x: int in width:
			if can_place(item, Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

## Кладёт предмет; стакающиеся сначала пытаются влиться в существующий стак.
func add(item: ItemInstance) -> Result:
	if item.data != null and item.data.stackable:
		for existing: ItemInstance in items():
			if existing.id() != item.id():
				continue
			var room := existing.data.max_stack - existing.quantity
			if room <= 0:
				continue
			var moved := mini(room, item.quantity)
			existing.quantity += moved
			item.quantity -= moved
			if item.quantity <= 0:
				return Result.good(existing)
	var pos := find_free_position(item)
	if pos.x < 0:
		return Result.fail("Нет места в сумке")
	return place(item, pos)

func place(item: ItemInstance, pos: Vector2i) -> Result:
	if not can_place(item, pos, item.uid):
		return Result.fail("Здесь не помещается")
	remove(item.uid)
	slots[item.uid] = {"item": item, "pos": pos}
	for c: Vector2i in cells_for(item, pos):
		_occupancy[c] = item.uid
	return Result.good(item)

func remove(uid: int) -> ItemInstance:
	if not slots.has(uid):
		return null
	var entry: Dictionary = slots[uid]
	var item: ItemInstance = entry["item"]
	for c: Vector2i in cells_for(item, entry["pos"]):
		if _occupancy.get(c, -1) == uid:
			_occupancy.erase(c)
	slots.erase(uid)
	return item

func rotate(uid: int) -> Result:
	if not slots.has(uid):
		return Result.fail("Нет такого предмета")
	var entry: Dictionary = slots[uid]
	var item: ItemInstance = entry["item"]
	var pos: Vector2i = entry["pos"]
	item.rotated = not item.rotated
	if not can_place(item, pos, uid):
		item.rotated = not item.rotated
		return Result.fail("После поворота не помещается")
	return place(item, pos)

func count_of(item_id: StringName) -> int:
	var total := 0
	for item: ItemInstance in items():
		if item.id() == item_id:
			total += item.quantity
	return total

## Лимиты «5 зелий и 5 антидотов на героя» (05-items.md).
func count_limit_group(group: StringName) -> int:
	var total := 0
	for item: ItemInstance in items():
		if item.data is ConsumableData and (item.data as ConsumableData).limit_group == group:
			total += item.quantity
	return total

func take(item_id: StringName, amount: int = 1) -> int:
	var taken := 0
	for item: ItemInstance in items():
		if item.id() != item_id:
			continue
		var moved := mini(item.quantity, amount - taken)
		item.quantity -= moved
		taken += moved
		if item.quantity <= 0:
			remove(item.uid)
		if taken >= amount:
			break
	return taken

func find(item_id: StringName) -> ItemInstance:
	for item: ItemInstance in items():
		if item.id() == item_id:
			return item
	return null

func position_of(uid: int) -> Vector2i:
	var entry: Variant = slots.get(uid, null)
	return entry["pos"] if entry != null else Vector2i(-1, -1)

func save_state() -> Array:
	var out: Array = []
	for uid: Variant in slots.keys():
		var entry: Dictionary = slots[uid]
		var d: Dictionary = (entry["item"] as ItemInstance).save_state()
		d["pos"] = [int(entry["pos"].x), int(entry["pos"].y)]
		out.append(d)
	return out
