extends TestCase

var index: ContentIndex
var balance: BalanceData
var factory: ItemFactory

func suite_name() -> String:
	return "Предметы и лут"

func before_each() -> void:
	index = ContentIndex.load_from()
	balance = ContentIndex.load_balance()
	var items := index.map_of_class("ItemData").merged(index.map_of_class("WeaponData")).merged(
		index.map_of_class("ArmorData")).merged(index.map_of_class("ConsumableData"))
	factory = ItemFactory.new(items, index.of_class("AffixData"), balance)

func test_upgrade_bonuses_follow_curve() -> void:
	var sword := factory.create(&"sword_notched")
	sword.upgrade_level = 8
	assert_eq(sword.upgrade_damage_bonus(), 8)
	assert_eq(sword.upgrade_hit_bonus(), 4)
	assert_eq(int(sword.modifiers().get(&"damage", 0)), 8)

func test_upgrade_cap_comes_from_data() -> void:
	assert_eq(balance.upgrade_max_level, 8, "потолок улучшения задан данными")
	assert_eq(balance.upgrade_success_chance.size(), balance.upgrade_max_level)

func test_rarity_distribution_shifts_with_depth() -> void:
	var rng := RngStream.new(31337, &"loot")
	var shallow_common := 0
	var deep_common := 0
	for i: int in 3000:
		if AffixRoller.roll_rarity(rng, 1) == &"common":
			shallow_common += 1
		if AffixRoller.roll_rarity(rng, 20) == &"common":
			deep_common += 1
	assert_gt(float(shallow_common), float(deep_common), "на глубине обычных предметов меньше")

func test_affix_count_matches_rarity() -> void:
	var rng := RngStream.new(5, &"loot")
	for i: int in 200:
		var item := factory.create_rolled(&"sword_notched", 12, rng)
		var expected: int = int(AffixRoller.AFFIX_COUNT.get(item.data.rarity, 0))
		assert_le(float(item.affixes.size()), float(expected))

func test_affix_tier_capped_by_depth_and_balance() -> void:
	var roller := AffixRoller.new(index.of_class("AffixData"), balance.max_affix_tier)
	assert_eq(roller.tier_cap_for_depth(1), 1)
	assert_eq(roller.tier_cap_for_depth(20), balance.max_affix_tier)

func test_loot_table_produces_gold_and_items() -> void:
	var rng := RngStream.new(99, &"loot")
	var table: LootTable = index.get_resource(&"chest_treasure")
	assert_not_null(table)
	var total_gold := 0
	var items := 0
	for i: int in 100:
		var loot := factory.roll_loot(table, 10, rng, {})
		total_gold += int(loot["gold"])
		items += (loot["items"] as Array).size()
	assert_gt(float(total_gold), 0.0)
	assert_gt(float(items), 50.0, "сокровищница почти всегда даёт предмет")

func test_boss_table_guarantees_items() -> void:
	var rng := RngStream.new(4, &"loot")
	var table: LootTable = index.get_resource(&"boss_act1")
	var loot := factory.roll_loot(table, 10, rng, {})
	assert_ge(float((loot["items"] as Array).size()), 2.0)
