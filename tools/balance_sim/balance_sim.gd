extends SceneTree
## Симулятор баланса (08-architecture.md, раздел 12: «перебалансировка вручную
## съест месяцы»). Прогоняет автобои по сетке «уровень отряда x глубина».
##   godot --headless --path . --script res://tools/balance_sim/balance_sim.gd

const BATTLES_PER_CELL := 25
const LEVELS := [1, 3, 5, 7, 9]
const DEPTHS := [1, 5, 10, 15, 20]
## Отчёт дублируется в файл: stdout при headless буферизуется.
const REPORT_PATH := "user://balance_report.txt"

var index: ContentIndex
var balance: BalanceData
var factory: ItemFactory

var report: FileAccess

func _say(line: String) -> void:
	print(line)
	if report != null:
		report.store_line(line)
		report.flush()

func _initialize() -> void:
	report = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	index = ContentIndex.load_from()
	balance = ContentIndex.load_balance()
	var items := index.map_of_class("ItemData").merged(index.map_of_class("WeaponData")).merged(
		index.map_of_class("ArmorData")).merged(index.map_of_class("ConsumableData"))
	factory = ItemFactory.new(items, index.of_class("AffixData"), balance)
	_say("===== Симулятор баланса =====")
	_say("боёв на ячейку: %d" % BATTLES_PER_CELL)
	_say("%-8s %s" % ["ур/эт", " ".join(DEPTHS.map(func(d: int) -> String:
		return "%7s" % ("эт.%d" % d)))])
	_say("-- обычные встречи --")
	_table(false)
	_say("-- логово стража (элита, множитель %.1f) --" % balance.encounter_mult_elite)
	_table(true)
	_say("=============================")
	quit(0)

func _table(elite: bool) -> void:
	for level: int in LEVELS:
		var row: Array[String] = []
		for depth: int in DEPTHS:
			row.append("%6.0f%%" % (_win_rate(level, depth, elite) * 100.0))
		_say("%-8d %s" % [level, " ".join(row)])

func _win_rate(level: int, depth: int, elite: bool) -> float:
	var wins := 0
	for i: int in BATTLES_PER_CELL:
		var state := BattleSimulator.build_state(_party(level), _encounter(depth, i, elite),
			balance, index.map_of_class("StatusData"), depth * 1000 + level * 37 + i)
		state.spell_db = index.map_of_class("SpellData")
		if bool(BattleSimulator.run(state)["victory"]):
			wins += 1
	return float(wins) / float(BATTLES_PER_CELL)

func _party(level: int) -> Array:
	var out: Array = []
	for hero_id: StringName in [&"hald", &"irma", &"vern", &"mara"]:
		var data: HeroData = index.get_resource(hero_id)
		var c := CharacterState.new()
		c.hero_id = hero_id
		c.data = data
		c.level = level
		c.inventory = Inventory.new(10, 8, 40.0)
		for equip_id: StringName in data.starting_equipment:
			var inst := factory.create(equip_id)
			if inst == null:
				continue
			# Снаряжение подтягивается к глубине: +1 улучшения на каждые два уровня.
			inst.upgrade_level = mini(balance.upgrade_max_level, int(level / 2))
			if inst.data is WeaponData:
				c.equipment[(inst.data as WeaponData).slot] = inst
			elif inst.data is ArmorData:
				c.equipment[(inst.data as ArmorData).slot] = inst
		c.known_spells = data.starting_spells.duplicate()
		c.restore_full(balance)
		out.append(ActorBuilder.from_hero(c, balance))
	return out

## Встреча собирается тем же EncounterBuilder, что и в подземелье.
func _encounter(depth: int, salt: int, elite: bool = false) -> Array:
	var biomes := index.of_class("BiomeData")
	var tier := balance.act_of_floor(depth)
	var pool: Array = []
	for b: BiomeData in biomes:
		if b.tier_min == tier:
			pool.append(b)
	var biome: BiomeData = pool[salt % maxi(1, pool.size())]
	var rng := RngStream.new(depth * 977 + salt, &"encounter")
	var builder := EncounterBuilder.new(balance, biome, rng, index.map_of_class("EnemyData"))
	var room := FloorPlan.Room.new()
	room.rect = Rect2i(0, 0, 8, 8)
	var multiplier := balance.encounter_mult_elite if elite else balance.encounter_mult_normal
	var encounter := builder.build(room, depth, multiplier, elite)
	var out: Array = []
	var i := 0
	for enemy_id: StringName in encounter["enemies"]:
		var data: EnemyData = index.get_resource(enemy_id)
		if data != null:
			var is_elite: bool = elite and i == 0
			out.append(ActorBuilder.from_enemy(data, i, balance, is_elite, depth))
			i += 1
	if out.is_empty():
		out.append(ActorBuilder.from_enemy(index.get_resource(&"skeleton_warrior"), 0, balance,
			false, depth))
	return out
