extends TestCase

var index: ContentIndex
var factory: ItemFactory
var inv: Inventory

func suite_name() -> String:
	return "Инвентарь"

func before_each() -> void:
	index = ContentIndex.load_from()
	var balance := ContentIndex.load_balance()
	factory = ItemFactory.new(index.map_of_class("ItemData").merged(
		index.map_of_class("WeaponData")).merged(
		index.map_of_class("ArmorData")).merged(
		index.map_of_class("ConsumableData")), index.of_class("AffixData"), balance)
	inv = Inventory.new(6, 5, 20.0)

func test_place_and_occupy() -> void:
	var sword := factory.create(&"sword_notched")
	assert_not_null(sword)
	assert_true(inv.add(sword).ok)
	assert_false(inv.can_place(factory.create(&"sword_notched"), Vector2i(0, 0)))

func test_rotation_changes_footprint() -> void:
	var bow := factory.create(&"shortbow")
	inv.add(bow)
	assert_eq(bow.grid_size(), Vector2i(1, 3))
	inv.rotate(bow.uid)
	assert_eq(bow.grid_size(), Vector2i(3, 1))

func test_overflow_reports_failure() -> void:
	var placed := 0
	for i: int in 40:
		if inv.add(factory.create(&"armor_plate")).ok:
			placed += 1
	assert_le(float(placed), 2.0, "латы 3x3 не влезут в сетку 6x5 больше двух раз")

func test_stacking_and_take() -> void:
	for i: int in 3:
		inv.add(factory.create(&"torch", 3))
	assert_eq(inv.count_of(&"torch"), 9)
	assert_eq(inv.take(&"torch", 4), 4)
	assert_eq(inv.count_of(&"torch"), 5)

func test_weight_limit_detected() -> void:
	inv.carry_limit = 5.0
	inv.add(factory.create(&"armor_chainmail"))
	assert_true(inv.is_overloaded(), "кольчуга весит больше лимита")

func test_limit_groups_counted() -> void:
	inv.add(factory.create(&"potion_minor", 3))
	inv.add(factory.create(&"antidote", 2))
	assert_eq(inv.count_limit_group(&"potion"), 3)
	assert_eq(inv.count_limit_group(&"antidote"), 2)
