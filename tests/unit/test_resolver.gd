extends TestCase

func suite_name() -> String:
	return "Броски и урон"

func _actor(hp: int = 20, ac: int = 14) -> CombatActor:
	var a := CombatActor.new()
	a.id = &"t"
	a.display_name = "Цель"
	a.stats = Stats.empty()
	a.max_hp = hp
	a.hp = hp
	a.armor_class = ac
	return a

func test_advantage_takes_higher() -> void:
	var rng := RngStream.new(11, &"c")
	var adv_total := 0
	var dis_total := 0
	for i: int in 400:
		adv_total += int(Resolver.roll_d20(rng, Resolver.ADV)["natural"])
		dis_total += int(Resolver.roll_d20(rng, Resolver.DIS)["natural"])
	assert_gt(float(adv_total), float(dis_total) * 1.3)

func test_advantage_and_disadvantage_cancel() -> void:
	assert_eq(Resolver.resolve_mode(1, 1), Resolver.NONE)
	assert_eq(Resolver.resolve_mode(3, 1), Resolver.NONE)
	assert_eq(Resolver.resolve_mode(2, 0), Resolver.ADV)
	assert_eq(Resolver.resolve_mode(0, 2), Resolver.DIS)

func test_natural_one_always_misses() -> void:
	var rng := RngStream.new(3, &"c")
	var misses := 0
	var nat_ones := 0
	for i: int in 2000:
		var r := Resolver.attack_roll(rng, 30, 5, Resolver.NONE, 20)
		if int(r["natural"]) == 1:
			nat_ones += 1
			if not bool(r["hit"]):
				misses += 1
	assert_gt(float(nat_ones), 50.0)
	assert_eq(misses, nat_ones, "натуральная 1 — всегда промах")

func test_resistance_vulnerability_order() -> void:
	var target := _actor()
	target.resistances = [&"fire"]
	var mods := DamageCalc.apply_type_modifiers(target, 9, &"fire")
	assert_eq(int(mods["amount"]), 4, "сопротивление округляет вниз")
	target.resistances = []
	target.vulnerabilities = [&"fire"]
	assert_eq(int(DamageCalc.apply_type_modifiers(target, 9, &"fire")["amount"]), 18)
	target.vulnerabilities = []
	target.immunities = [&"fire"]
	assert_eq(int(DamageCalc.apply_type_modifiers(target, 9, &"fire")["amount"]), 0)

func test_absorb_after_type_then_min_one() -> void:
	var target := _actor()
	target.resistances = [&"cold"]
	target.absorb = 3
	var mods := DamageCalc.apply_type_modifiers(target, 10, &"cold")
	assert_eq(int(mods["amount"]), 2, "10 -> 5 (сопр.) -> 2 (поглощение 3)")
	var tiny := DamageCalc.apply_type_modifiers(target, 2, &"cold")
	assert_eq(int(tiny["amount"]), 1, "попадание всегда наносит минимум 1")

func test_hero_drops_to_dying_not_dead() -> void:
	var balance := BalanceData.new()
	var hero := _actor(10)
	hero.is_hero = true
	DamageCalc.deal(hero, 25, &"slashing", false, balance)
	assert_true(hero.is_down)
	assert_false(hero.is_dead)
	var enemy := _actor(10)
	DamageCalc.deal(enemy, 25, &"slashing", false, balance)
	assert_true(enemy.is_dead)
