extends TestCase

var index: ContentIndex
var balance: BalanceData

func suite_name() -> String:
	return "Сохранения и миграции"

func before_each() -> void:
	index = ContentIndex.load_from()
	balance = ContentIndex.load_balance()

func _factory() -> ItemFactory:
	var items := index.map_of_class("ItemData").merged(index.map_of_class("WeaponData")).merged(
		index.map_of_class("ArmorData")).merged(index.map_of_class("ConsumableData"))
	return ItemFactory.new(items, index.of_class("AffixData"), balance)

func test_item_roundtrip_keeps_upgrades_and_affixes() -> void:
	var factory := _factory()
	var rng := RngStream.new(11, &"loot")
	var sword := factory.create_rolled(&"rapier", 15, rng)
	sword.upgrade_level = 5
	var saved := sword.save_state()
	var json := JSON.stringify(saved)
	var restored: Dictionary = JSON.parse_string(json)
	assert_eq(String(restored["id"]), "rapier")
	assert_eq(int(restored["upgrade"]), 5)
	assert_eq((restored["affixes"] as Array).size(), sword.affixes.size())

func test_profile_roundtrip_through_json() -> void:
	var factory := _factory()
	var profile := ProfileState.new()
	profile.main_hero_id = &"mara"
	profile.gold = 4321
	profile.party_level = 6
	profile.add_material(&"ore_silver", 12)
	profile.storage.append(factory.create(&"potion_greater", 3))
	var c := CharacterState.new()
	c.hero_id = &"mara"
	c.data = index.get_resource(&"mara")
	c.level = 6
	c.hp = 33
	c.inventory = Inventory.new(10, 8, 40.0)
	c.unlocked_nodes = [&"mara_trunk_1", &"mara_life_1"]
	c.equipment[&"main_hand"] = factory.create(&"club_banded")
	profile.party.append(c)
	var text := JSON.stringify(profile.save_state())
	var parsed: Dictionary = JSON.parse_string(text)
	assert_eq(int(parsed["gold"]), 4321)
	assert_eq(String(parsed["main_hero"]), "mara")
	assert_eq(int(parsed["party_level"]), 6)
	assert_eq(int((parsed["materials"] as Dictionary)["ore_silver"]), 12)
	var member: Dictionary = (parsed["party"] as Array)[0]
	assert_eq(int(member["hp"]), 33)
	assert_eq((member["nodes"] as Array).size(), 2)
	assert_true((member["equipment"] as Dictionary).has("main_hand"))

func test_run_roundtrip_keeps_loot_and_torch() -> void:
	var factory := _factory()
	var run := RunState.new()
	run.run_seed = 987
	run.floor_index = 7
	run.current_biome = &"swamp"
	run.light_torch(420)
	run.add_gold(1500)
	run.add_material(&"crystal_rot", 2)
	run.run_items.append(factory.create(&"potion_minor", 2))
	run.cleared_rooms = [1, 2, 5]
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(run.save_state()))
	assert_eq(int(parsed["floor"]), 7)
	assert_eq(String(parsed["biome"]), "swamp")
	assert_eq(int(parsed["torch"]), 420)
	assert_eq(int(parsed["gold"]), 1500)
	assert_eq((parsed["cleared_rooms"] as Array).size(), 3)

## Требование ТЗ: профиль релиза обязан открываться в версии с актом III.
func test_migration_from_older_schema() -> void:
	var legacy := {"schema_version": 0, "gold": 100, "ore": 7, "main_hero": "vern"}
	var migrated := Migrations.migrate_profile(legacy)
	assert_eq(int(migrated["schema_version"]), ProfileState.SCHEMA_VERSION)
	assert_true((migrated["materials"] as Dictionary).has("ore_iron"))
	assert_eq(int((migrated["materials"] as Dictionary)["ore_iron"]), 7)
	assert_false(migrated.has("ore"))

## Числа объёма релиза лежат в данных, а не в коде.
func test_release_scope_is_data_driven() -> void:
	assert_eq(balance.act_count, 2)
	assert_eq(balance.total_floors, 20)
	assert_eq(balance.max_party_level, 9)
	assert_eq(balance.max_spell_level, 3)
	assert_eq(Array(balance.boss_floors), [10, 20])
	assert_eq(Array(balance.blessing_floors), [5, 10, 15, 20])
	# Подмена данных «как в обновлении» не должна ломать логику.
	balance.act_count = 3
	balance.total_floors = 30
	balance.boss_floors = PackedInt32Array([10, 20, 30])
	assert_true(balance.is_boss_floor(30))
	assert_eq(balance.act_of_floor(25), 3)
