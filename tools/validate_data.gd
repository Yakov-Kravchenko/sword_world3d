extends SceneTree
## Проверка целостности контента (08-architecture.md, раздел 4):
##   godot --headless --path . --script res://tools/validate_data.gd
## Без него при 500+ ресурсах опечатки становятся основным источником багов.

var problems: Array[String] = []
var checked: int = 0

func _initialize() -> void:
	var index := ContentIndex.load_from()
	var balance := ContentIndex.load_balance()
	for err: String in index.errors:
		problems.append("загрузка: " + err)
	_check_items(index)
	_check_spells(index, balance)
	_check_enemies(index)
	_check_biomes(index)
	_check_loot(index)
	_check_heroes(index)
	_check_skills(index)
	_check_balance(balance)
	print("===== Проверка контента =====")
	print("Записей: %d, проверок: %d" % [index.by_id.size(), checked])
	if problems.is_empty():
		print("Ошибок нет.")
	else:
		for p: String in problems:
			print("  ! " + p)
	print("=============================")
	quit(1 if not problems.is_empty() else 0)

func _require(condition: bool, message: String) -> void:
	checked += 1
	if not condition:
		problems.append(message)

func _check_items(index: ContentIndex) -> void:
	for weapon: WeaponData in index.of_class("WeaponData"):
		_require(Dice.is_valid(weapon.damage_dice),
			"оружие %s: не разбираются кости «%s»" % [weapon.id, weapon.damage_dice])
		_require(Stats.DAMAGE_TYPES.has(weapon.damage_type),
			"оружие %s: неизвестный тип урона %s" % [weapon.id, weapon.damage_type])
		_require(Stats.ALL.has(weapon.attack_stat),
			"оружие %s: неизвестная характеристика атаки %s" % [weapon.id, weapon.attack_stat])
		_require(weapon.grid_size.x > 0 and weapon.grid_size.y > 0,
			"оружие %s: нулевой размер в сетке" % weapon.id)
	for armor: ArmorData in index.of_class("ArmorData"):
		_require(armor.ac_base >= 0, "броня %s: отрицательный КБ" % armor.id)
	for consumable: ConsumableData in index.of_class("ConsumableData"):
		if consumable.effect == &"cure_status":
			_require(index.by_id.has(consumable.status_id),
				"расходник %s: несуществующий статус %s" % [consumable.id, consumable.status_id])
		if consumable.effect == &"heal":
			_require(Dice.is_valid(consumable.dice),
				"расходник %s: не разбираются кости «%s»" % [consumable.id, consumable.dice])

func _check_spells(index: ContentIndex, balance: BalanceData) -> void:
	for spell: SpellData in index.of_class("SpellData"):
		if not spell.damage_dice.is_empty():
			_require(Dice.is_valid(spell.damage_dice),
				"заклинание %s: кости урона «%s»" % [spell.id, spell.damage_dice])
			_require(Stats.DAMAGE_TYPES.has(spell.damage_type),
				"заклинание %s: тип урона %s" % [spell.id, spell.damage_type])
		if not spell.heal_dice.is_empty():
			_require(Dice.is_valid(spell.heal_dice),
				"заклинание %s: кости лечения «%s»" % [spell.id, spell.heal_dice])
		if spell.apply_status != &"":
			_require(index.by_id.has(spell.apply_status),
				"заклинание %s: несуществующий статус %s" % [spell.id, spell.apply_status])
		if spell.save_stat != &"":
			_require(Stats.ALL.has(spell.save_stat),
				"заклинание %s: характеристика спасброска %s" % [spell.id, spell.save_stat])
		_require(spell.level <= balance.max_spell_level or spell.available_from_version != "1.0",
			"заклинание %s: уровень %d выше потолка релиза" % [spell.id, spell.level])

func _check_enemies(index: ContentIndex) -> void:
	for enemy: EnemyData in index.of_class("EnemyData"):
		_require(not enemy.attacks.is_empty(), "враг %s: нет ни одной атаки" % enemy.id)
		_require(index.by_id.has(enemy.loot_table),
			"враг %s: нет таблицы дропа %s" % [enemy.id, enemy.loot_table])
		_require(enemy.danger_points > 0, "враг %s: нулевые очки опасности" % enemy.id)
		for attack: AttackData in enemy.attacks:
			_require(Dice.is_valid(attack.damage_dice),
				"враг %s: кости «%s»" % [enemy.id, attack.damage_dice])
			if attack.on_hit_status != &"":
				_require(index.by_id.has(attack.on_hit_status),
					"враг %s: статус при попадании %s" % [enemy.id, attack.on_hit_status])
		for type: StringName in enemy.resistances + enemy.vulnerabilities + enemy.immunities:
			_require(Stats.DAMAGE_TYPES.has(type),
				"враг %s: неизвестный тип урона %s" % [enemy.id, type])

func _check_biomes(index: ContentIndex) -> void:
	for biome: BiomeData in index.of_class("BiomeData"):
		_require(not biome.enemy_pool.is_empty(), "биом %s: пустой пул врагов" % biome.id)
		_require(biome.enemy_weights.size() == biome.enemy_pool.size(),
			"биом %s: веса врагов не совпадают с пулом" % biome.id)
		for enemy_id: StringName in biome.enemy_pool:
			_require(index.by_id.has(enemy_id),
				"биом %s: неизвестный враг %s" % [biome.id, enemy_id])
		_require(index.by_id.has(biome.crystal_id),
			"биом %s: неизвестный кристалл %s" % [biome.id, biome.crystal_id])
		_require(biome.room_count_min <= biome.room_count_max,
			"биом %s: диапазон комнат вывернут" % biome.id)
		if biome.is_deep():
			_require(index.by_id.has(biome.deep_variant_of),
				"биом %s: базовый биом %s не найден" % [biome.id, biome.deep_variant_of])

func _check_loot(index: ContentIndex) -> void:
	for table: LootTable in index.of_class("LootTable"):
		_require(Dice.is_valid(table.gold_dice),
			"таблица %s: кости золота «%s»" % [table.id, table.gold_dice])
		_require(index.by_id.has(table.ore_id),
			"таблица %s: неизвестная руда %s" % [table.id, table.ore_id])
		for item_id: StringName in table.item_pool + table.guaranteed_items:
			_require(index.by_id.has(item_id),
				"таблица %s: неизвестный предмет %s" % [table.id, item_id])
		if not table.item_weights.is_empty():
			_require(table.item_weights.size() == table.item_pool.size(),
				"таблица %s: веса не совпадают с пулом" % table.id)

func _check_heroes(index: ContentIndex) -> void:
	for hero: HeroData in index.of_class("HeroData"):
		for item_id: StringName in hero.starting_equipment + hero.starting_inventory:
			_require(index.by_id.has(item_id),
				"герой %s: неизвестный предмет %s" % [hero.id, item_id])
		for spell_id: StringName in hero.starting_spells:
			_require(index.by_id.has(spell_id),
				"герой %s: неизвестное заклинание %s" % [hero.id, spell_id])
		for ability_id: StringName in hero.abilities:
			_require(index.by_id.has(ability_id),
				"герой %s: неизвестная способность %s" % [hero.id, ability_id])
		for key: StringName in Stats.ALL:
			_require(hero.base_stats.has(key),
				"герой %s: не задана характеристика %s" % [hero.id, key])

func _check_skills(index: ContentIndex) -> void:
	for node: SkillNodeData in index.of_class("SkillNodeData"):
		_require(index.by_id.has(node.hero_id),
			"узел %s: неизвестный герой %s" % [node.id, node.hero_id])
		for req: StringName in node.requires:
			_require(index.by_id.has(req),
				"узел %s: требование %s не найдено" % [node.id, req])
		if node.grants_spell != &"":
			_require(index.by_id.has(node.grants_spell),
				"узел %s: неизвестное заклинание %s" % [node.id, node.grants_spell])

func _check_balance(balance: BalanceData) -> void:
	_require(balance.total_floors == balance.act_count * balance.act_length_floors,
		"баланс: total_floors не равен act_count * act_length_floors")
	_require(balance.spell_slots.size() >= balance.max_party_level,
		"баланс: таблица ячеек короче максимального уровня")
	_require(balance.proficiency_by_level.size() >= balance.max_party_level,
		"баланс: таблица БМ короче максимального уровня")
	_require(balance.level_costs.size() >= balance.max_party_level - 1,
		"баланс: не заданы цены всех уровней")
	_require(balance.upgrade_success_chance.size() >= balance.upgrade_max_level,
		"баланс: не заданы шансы улучшения до потолка")
	for floor_index: int in balance.boss_floors:
		_require(floor_index <= balance.total_floors,
			"баланс: этаж босса %d вне забега" % floor_index)
