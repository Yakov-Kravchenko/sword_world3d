extends Node
## Текущее состояние игры: профиль, активный забег, отряд, сервисы.
## Хранение и маршрутизация — без игровых правил (08-architecture.md, раздел 3).

const GAME_VERSION := "1.0"
## Урон любой атаки в режиме разработчика (F1 в подземелье). Режим живёт только
## в сессии: в сохранение не попадает и при запуске всегда выключен.
const DEV_DAMAGE := 999

var profile: ProfileState
var run: RunState
var item_factory: ItemFactory
var skill_tree: SkillTree
var blessing_pool: BlessingPool
var dev_mode: bool = false

func _ready() -> void:
	_build_services()

func _build_services() -> void:
	var items := Database.item_map()
	item_factory = ItemFactory.new(items, Database.of_class("AffixData"), Balance.data)
	var nodes: Array = Database.of_class("SkillNodeData")
	skill_tree = SkillTree.new(nodes, Balance.data, GAME_VERSION)
	blessing_pool = BlessingPool.new(Database.of_class("BlessingData"))

func item_database() -> Dictionary:
	return item_factory.item_db

# --- Профиль ---

func new_profile(main_hero_id: StringName) -> void:
	profile = ProfileState.new()
	profile.main_hero_id = main_hero_id
	profile.profile_seed = int(Time.get_unix_time_from_system())
	profile.gold = 250
	profile.party.clear()
	for hero_id: StringName in [&"hald", &"irma", &"vern", &"mara"]:
		profile.party.append(_make_character(hero_id, main_hero_id))
	profile.unlocked_biomes = [&"catacombs", &"mines"]
	EventBus.party_changed.emit()
	Log.info("Новый профиль, основной герой: %s" % main_hero_id)

func _make_character(hero_id: StringName, main_hero_id: StringName) -> CharacterState:
	var data := Database.get_hero(hero_id)
	var c := CharacterState.new()
	c.hero_id = hero_id
	c.data = data
	c.level = 1
	c.skill_points = 2
	c.inventory = Inventory.new(Balance.data.inventory_width, Balance.data.inventory_height, 30.0)
	if data != null:
		# Стартовый бонус основного героя: +1 к профильной характеристике.
		if hero_id == main_hero_id:
			c.skill_modifiers[StringName("stat_" + String(data.primary_stat))] = 1.0
		for item_id: StringName in data.starting_equipment:
			var inst := item_factory.create(item_id)
			if inst == null:
				continue
			var slot := _slot_for(inst)
			if slot != &"":
				c.equipment[slot] = inst
		for item_id: StringName in data.starting_inventory:
			var inst := item_factory.create(item_id)
			if inst != null:
				c.inventory.add(inst)
		c.known_spells = data.starting_spells.duplicate()
	c.inventory.carry_limit = c.carry_limit(Balance.data)
	c.restore_full(Balance.data)
	return c

func _slot_for(item: ItemInstance) -> StringName:
	if item.data is WeaponData:
		return (item.data as WeaponData).slot
	if item.data is ArmorData:
		return (item.data as ArmorData).slot
	return &""

func has_profile() -> bool:
	return profile != null

# --- Валюты ---

func add_gold(amount: int) -> void:
	if profile == null:
		return
	profile.add_gold(amount)
	EventBus.currency_changed.emit(&"gold", profile.gold)

func add_material(id: StringName, amount: int) -> void:
	if profile == null:
		return
	profile.add_material(id, amount)
	EventBus.currency_changed.emit(id, profile.material_count(id))

# --- Забег ---

func has_active_run() -> bool:
	return run != null and not run.finished

func party_level() -> int:
	return profile.party_level if profile != null else 1
