extends TestCase

var state: CombatState
var target: CombatActor

func suite_name() -> String:
	return "Статусные эффекты"

func before_each() -> void:
	state = CombatState.new()
	state.balance = ContentIndex.load_balance()
	state.grid = CombatGrid.new(10, 10)
	state.light = LightService.new(state.grid)
	state.rng = RngStream.new(2024, &"status")
	state.status_db = ContentIndex.load_from().map_of_class("StatusData")
	target = CombatActor.new()
	target.id = &"target"
	target.display_name = "Цель"
	target.stats = Stats.empty()
	target.max_hp = 60
	target.hp = 60
	state.add_actor(target)

func test_all_seventeen_statuses_present() -> void:
	for id: StringName in [&"bleeding", &"poisoned", &"poisoned_heavy", &"burning", &"frostbite",
			&"frozen", &"stunned", &"paralyzed", &"blinded", &"feared", &"slowed", &"cursed",
			&"diseased", &"restrained", &"vulnerable_mark", &"blessed", &"inspired"]:
		assert_true(state.status_db.has(id), "нет статуса %s" % id)

func test_apply_and_stack() -> void:
	for i: int in 8:
		StatusEngine.apply(state, target, &"bleeding", &"src")
	var effect := target.get_status(&"bleeding")
	assert_not_null(effect)
	assert_eq(effect.stacks, 5, "кровотечение стакается максимум до 5")

func test_non_stackable_refreshes_duration() -> void:
	StatusEngine.apply(state, target, &"slowed", &"src")
	target.get_status(&"slowed").rounds_left = 1
	StatusEngine.apply(state, target, &"slowed", &"src")
	assert_eq(target.get_status(&"slowed").rounds_left, 3)

func test_immunity_blocks_by_tag() -> void:
	target.status_immunities = [&"poison"]
	var event := StatusEngine.apply(state, target, &"poisoned", &"src")
	assert_true(bool(event.get("immune", false)))
	assert_false(target.has_status(&"poisoned"))

func test_tick_damage_scales_with_stacks() -> void:
	StatusEngine.apply(state, target, &"bleeding", &"src", 0, 3)
	var result := ActionResult.new()
	StatusEngine.tick_start_of_turn(state, target, result)
	assert_eq(result.damage_events.size(), 1)
	assert_ge(float(result.damage_events[0]["amount"]), 3.0, "3 стака = минимум 3 урона")

func test_duration_expires() -> void:
	StatusEngine.apply(state, target, &"blinded", &"src")
	for i: int in 3:
		StatusEngine.tick_end_of_turn(state, target, ActionResult.new())
	assert_false(target.has_status(&"blinded"))

func test_fire_removes_freeze() -> void:
	StatusEngine.apply(state, target, &"frozen", &"src")
	StatusEngine.on_damage_taken(target, &"fire")
	assert_false(target.has_status(&"frozen"))

func test_cleanse_removes_only_debuffs() -> void:
	StatusEngine.apply(state, target, &"blessed", &"src")
	StatusEngine.apply(state, target, &"poisoned", &"src")
	StatusEngine.cleanse(target, 5)
	assert_true(target.has_status(&"blessed"))
	assert_false(target.has_status(&"poisoned"))

func test_status_modifiers_apply_to_actor() -> void:
	var before := target.effective_ac()
	StatusEngine.apply(state, target, &"burning", &"src")
	assert_eq(target.effective_ac(), before - 2, "ожог даёт -2 КБ")
	assert_true(target.has_flag_status(&"skip_turn") == false)
	StatusEngine.apply(state, target, &"stunned", &"src")
	assert_true(target.has_flag_status(&"skip_turn"))
