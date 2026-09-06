extends TestCase

var index: ContentIndex
var balance: BalanceData
var statuses: Dictionary
var spells: Dictionary

func suite_name() -> String:
	return "Бой (интеграция)"

func before_each() -> void:
	index = ContentIndex.load_from()
	balance = ContentIndex.load_balance()
	statuses = index.map_of_class("StatusData")
	spells = index.map_of_class("SpellData")

func _party(level: int) -> Array:
	var items := index.map_of_class("ItemData").merged(index.map_of_class("WeaponData")).merged(
		index.map_of_class("ArmorData")).merged(index.map_of_class("ConsumableData"))
	var factory := ItemFactory.new(items, index.of_class("AffixData"), balance)
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
			if inst.data is WeaponData:
				c.equipment[(inst.data as WeaponData).slot] = inst
			elif inst.data is ArmorData:
				c.equipment[(inst.data as ArmorData).slot] = inst
		c.known_spells = data.starting_spells.duplicate()
		c.restore_full(balance)
		out.append(ActorBuilder.from_hero(c, balance))
	return out

func _enemies(ids: Array, depth: int) -> Array:
	var out: Array = []
	var i := 0
	for id: StringName in ids:
		var data: EnemyData = index.get_resource(id)
		out.append(ActorBuilder.from_enemy(data, i, balance, false, depth))
		i += 1
	return out

func test_hero_derived_values_match_spec() -> void:
	var party := _party(1)
	var hald: CombatActor = party[0]
	# d10 + ТЕЛ(15 -> +2) = 12 на первом уровне.
	assert_eq(hald.max_hp, 12, "HP латника 1 уровня")
	# Кольчуга 14 + min(ЛОВ 0, лимит 2) + щит 2 = 16.
	assert_eq(hald.effective_ac(), 16, "КБ латника со щитом")
	assert_eq(hald.proficiency, 2)

func test_spell_slots_come_from_balance_table() -> void:
	var l1 := balance.slots_for_level(1)
	var l5 := balance.slots_for_level(5)
	assert_eq(l1[0], 2)
	assert_eq(l5[2], 2, "на 5 уровне появляются ячейки 3-го уровня")
	assert_eq(balance.slots_for_level(9).size(), balance.max_spell_level)

func test_five_hundred_battles_without_errors() -> void:
	var wins := 0
	var timeouts := 0
	var rounds_total := 0
	for i: int in 500:
		var party := _party(5)
		var enemies := _enemies([&"skeleton_warrior", &"bone_archer", &"ghoul"], 10)
		var state := BattleSimulator.build_state(party, enemies, balance, statuses, 1000 + i)
		state.spell_db = spells
		var result := BattleSimulator.run(state)
		rounds_total += int(result["rounds"])
		if bool(result["victory"]):
			wins += 1
		if bool(result["timeout"]):
			timeouts += 1
	assert_eq(timeouts, 0, "бой обязан завершаться")
	assert_between(float(wins) / 500.0, 0.55, 1.0, "отряд 5 уровня должен уверенно побеждать")
	assert_le(float(rounds_total) / 500.0, 20.0, "средний бой короче 20 раундов")

func test_deeper_enemies_are_harder() -> void:
	var easy_wins := 0
	var hard_wins := 0
	for i: int in 120:
		var state_a := BattleSimulator.build_state(_party(3),
			_enemies([&"goblin_digger", &"goblin_slinger"], 2), balance, statuses, 7000 + i)
		state_a.spell_db = spells
		if bool(BattleSimulator.run(state_a)["victory"]):
			easy_wins += 1
		var state_b := BattleSimulator.build_state(_party(3),
			_enemies([&"lich_acolyte", &"cold_wraith", &"bone_legionnaire"], 18),
			balance, statuses, 8000 + i)
		state_b.spell_db = spells
		if bool(BattleSimulator.run(state_b)["victory"]):
			hard_wins += 1
	assert_gt(float(easy_wins), float(hard_wins), "глубокие враги должны быть опаснее")

func test_combat_log_explains_every_roll() -> void:
	var state := BattleSimulator.build_state(_party(4),
		_enemies([&"skeleton_warrior"], 3), balance, statuses, 4242)
	state.spell_db = spells
	var result := BattleSimulator.run(state)
	var log_lines: Array = result["log"]
	assert_gt(float(log_lines.size()), 5.0)
	var has_attack_line := false
	for line: String in log_lines:
		if line.contains("против КБ"):
			has_attack_line = true
			break
	assert_true(has_attack_line, "в логе должна быть расшифровка броска атаки")

func test_same_seed_reproduces_battle() -> void:
	var results: Array[String] = []
	for i: int in 2:
		var state := BattleSimulator.build_state(_party(4),
			_enemies([&"ghoul", &"bone_archer"], 6), balance, statuses, 31415)
		state.spell_db = spells
		var r := BattleSimulator.run(state)
		results.append("%s|%d|%d" % [r["victory"], r["rounds"], r["party_hp"]])
	assert_eq(results[0], results[1], "один сид — один и тот же бой")

## Режим разработчика: любая атака бьёт на dev_damage. Проверяем на бое целиком —
## одно попадание должно снимать врага, у которого HP заведомо меньше.
func test_dev_damage_kills_in_one_hit() -> void:
	var state := BattleSimulator.build_state(_party(4),
		_enemies([&"skeleton_warrior", &"bone_archer", &"ghoul"], 3), balance, statuses, 777)
	state.spell_db = spells
	state.dev_damage = 999
	state.dev_always_hit = true
	var result := BattleSimulator.run(state)
	assert_true(bool(result["victory"]), "с отладочным уроном отряд побеждает")
	assert_le(float(int(result["rounds"])), 3.0,
		"три врага снимаются за пару раундов, а не за десяток")
	var without := BattleSimulator.build_state(_party(4),
		_enemies([&"skeleton_warrior", &"bone_archer", &"ghoul"], 3), balance, statuses, 777)
	without.spell_db = spells
	var plain := BattleSimulator.run(without)
	assert_gt(float(int(plain["rounds"])), float(int(result["rounds"])),
		"без режима тот же бой идёт дольше")

## Отладочная неуязвимость: отряд не теряет ни хита, даже если бой затягивается.
func test_invulnerable_party_takes_no_damage() -> void:
	var party := _party(1)
	var state := BattleSimulator.build_state(party,
		_enemies([&"skeleton_warrior", &"bone_archer", &"ghoul"], 8), balance, statuses, 2024)
	state.spell_db = spells
	var before := 0
	for actor: CombatActor in state.team_actors(CombatActor.TEAM_PARTY, false):
		actor.invulnerable = true
		before += actor.hp
	var result := BattleSimulator.run(state)
	var after := 0
	var downed := false
	for actor: CombatActor in state.team_actors(CombatActor.TEAM_PARTY, false):
		after += actor.hp
		downed = downed or actor.is_down or actor.is_dead
	assert_eq(after, before, "неуязвимый отряд не теряет хитов")
	assert_false(downed, "никто не падает при смерти")
	assert_true(result.has("rounds"), "бой доигран до конца")

## «Всегда попадает»: натуральный промах героя переводится в попадание. Считаем
## по метке в логе, а не по слову «промах»: бросок остаётся настоящим и слово в
## строке сохраняется — проверять надо именно вердикт после метки.
func test_dev_always_hit_converts_hero_misses() -> void:
	var state := BattleSimulator.build_state(_party(1),
		_enemies([&"bone_legionnaire", &"ice_guard"], 12), balance, statuses, 909)
	state.spell_db = spells
	state.dev_always_hit = true
	for actor: CombatActor in state.team_actors(CombatActor.TEAM_PARTY, false):
		actor.invulnerable = true
	var result := BattleSimulator.run(state)
	var hero_names: Array[String] = []
	for actor: CombatActor in state.team_actors(CombatActor.TEAM_PARTY, false):
		hero_names.append(actor.display_name)
	var forced := 0
	var unconverted := 0
	for line: String in result["log"]:
		# Метку ставит только бросок героя, врагов режим не касается.
		if line.contains("режим разработчика"):
			forced += 1
			continue
		if not line.contains("промах"):
			continue
		for name: String in hero_names:
			if line.begins_with(name):
				unconverted += 1
	assert_gt(float(forced), 0.0, "режим действительно вмешался хотя бы раз")
	assert_eq(unconverted, 0, "ни один промах героя не остался промахом")
	assert_true(bool(result["victory"]), "бой при этом доигрывается до победы")
