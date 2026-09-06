class_name RunService
extends RefCounted
## Жизненный цикл забега: старт, выбор биома, спуск, отдых, благословения,
## Врата Возврата и итоги (04-dungeon.md, разделы 2 и 7).

var balance: BalanceData
var run: RunState

func _init() -> void:
	balance = Balance.data

# --- Старт ---

func start_new_run(seed_value: int = 0) -> RunState:
	run = RunState.new()
	run.run_seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	run.floor_index = 1
	run.party = GameState.profile.party
	for c: CharacterState in run.party:
		c.level = GameState.profile.party_level
		if c.spell_slots.is_empty():
			c.spell_slots = balance.slots_for_level(c.level)
	run.current_biome = _first_biome()
	run.used_biomes = [run.current_biome]
	_ensure_torch()
	GameState.run = run
	EventBus.run_started.emit(run.run_seed)
	Log.info("Забег начат: сид %d, биом %s" % [run.run_seed, run.current_biome])
	return run

func attach(existing: RunState) -> void:
	run = existing
	GameState.run = run

func _first_biome() -> StringName:
	var options := available_biomes(1)
	if options.is_empty():
		return &"catacombs"
	return (options[0] as BiomeData).id

## Биомы, доступные на этаже: тир по акту, без повторов внутри забега.
func available_biomes(floor_index: int) -> Array:
	var tier := balance.act_of_floor(floor_index)
	var unlocked := GameState.profile.unlocked_biomes
	var pool: Array = []
	for b: BiomeData in Database.of_class("BiomeData"):
		if b.tier_min != tier:
			continue
		var base_id: StringName = b.deep_variant_of if b.is_deep() else b.id
		if not unlocked.has(base_id):
			continue
		if run != null and run.used_biomes.has(b.id):
			continue
		pool.append(b)
	if pool.is_empty():
		for b: BiomeData in Database.of_class("BiomeData"):
			if b.tier_min == tier:
				pool.append(b)
	return pool

## Карточки выбора биома перед сегментом (04-dungeon.md, раздел 2.2).
func biome_choices(count: int = 2) -> Array:
	var pool := available_biomes(run.floor_index)
	var rng := run.stream(&"fork", run.floor_index)
	rng.shuffle(pool)
	return pool.slice(0, mini(count, pool.size()))

func is_segment_start() -> bool:
	if balance.is_boss_floor(run.floor_index):
		return false
	return (run.floor_index - 1) % balance.segment_length_floors == 0

func choose_biome(biome_id: StringName) -> void:
	run.current_biome = biome_id
	if not run.used_biomes.has(biome_id):
		run.used_biomes.append(biome_id)

# --- Этаж ---

func generate_floor() -> FloorPlan:
	var biome: BiomeData = Database.get_biome(run.current_biome)
	if biome == null:
		biome = Database.of_class("BiomeData")[0]
	Log.perf_start("floor_generation")
	var generator := DungeonGenerator.new(balance, biome, run.floor_index, run.run_seed)
	generator.enemy_db = Database.enemy_map()
	var plan := generator.generate()
	var ms := Log.perf_end("floor_generation")
	if ms > 1500.0:
		Log.warn("Генерация этажа заняла %.0f мс — бюджет 1500 мс" % ms)
	EventBus.floor_loaded.emit(run.floor_index, run.current_biome)
	return plan

func descend() -> void:
	run.floors_cleared += 1
	run.floor_index += 1
	# Индексы комнат и пропов относятся к конкретному этажу: на новом они другие.
	run.cleared_rooms.clear()
	run.visited_rooms.clear()
	run.looted_props.clear()
	_unlock_biome_for_depth()
	GameState.profile.stats["deepest_floor"] = maxi(
		int(GameState.profile.stats.get("deepest_floor", 0)), run.floor_index - 1)
	_ensure_torch()
	SaveSystem.save_run()
	SaveSystem.save_profile()

func _ensure_torch() -> void:
	if run.torch_lit:
		return
	for c: CharacterState in run.party:
		if c.inventory != null and c.inventory.take(&"torch", 1) > 0:
			var mult: float = float(run.blessing_modifiers().get(&"torch_mult", 1.0))
			run.light_torch(int(round(balance.torch_ticks * mult)))
			EventBus.torch_state_changed.emit(run.torch_ticks_left)
			return

func light_new_torch() -> bool:
	for c: CharacterState in run.party:
		if c.inventory != null and c.inventory.take(&"torch", 1) > 0:
			var mult: float = float(run.blessing_modifiers().get(&"torch_mult", 1.0))
			run.light_torch(int(round(balance.torch_ticks * mult)))
			EventBus.torch_state_changed.emit(run.torch_ticks_left)
			return true
	return false

func tick_torch(amount: int) -> void:
	var info := run.tick_torch(amount, balance)
	EventBus.torch_state_changed.emit(run.torch_ticks_left)
	if bool(info.get("went_out", false)):
		EventBus.notify("Факел погас. Темнота даёт помеху на все атаки.")

# --- Отдых у алтаря (04-dungeon.md, раздел 7) ---

func rest() -> void:
	for c: CharacterState in run.party:
		if c.is_dead_this_run:
			continue
		c.hp = c.max_hp(balance)
		c.spell_slots = balance.slots_for_level(c.level)
	EventBus.rest_taken.emit(run.floor_index)
	EventBus.notify("Отряд отдохнул: хиты и ячейки восстановлены.")
	SaveSystem.save_run()

# --- Благословения ---

func should_offer_blessing() -> bool:
	return balance.is_blessing_floor(run.floor_index)

func blessing_options() -> Array:
	var rng := run.stream(&"blessing", run.floor_index)
	return GameState.blessing_pool.offer(rng, run.taken_blessing_ids, 3)

func take_blessing(blessing: BlessingData) -> void:
	run.blessings.append(blessing)
	run.taken_blessing_ids.append(blessing.id)
	EventBus.blessing_chosen.emit(blessing)
	EventBus.notify("Благословение: %s" % blessing.display_name)

# --- Врата Возврата и конец забега ---

func can_extract() -> bool:
	return balance.is_extraction_floor(run.floor_index)

func extract() -> Dictionary:
	return finish(&"extracted", true)

func wipe() -> Dictionary:
	return finish(&"wiped", false)

## keep_loot=false — добыча забега теряется (02-combat.md, раздел 12.2),
## но снаряжение героев остаётся всегда.
func finish(outcome: StringName, keep_loot: bool) -> Dictionary:
	run.finished = true
	run.outcome = outcome
	var profile := GameState.profile
	var summary := {
		"outcome": String(outcome), "floor": run.floor_index,
		"gold": run.run_gold, "materials": run.run_materials.duplicate(),
		"items": run.run_items.size(), "kept": keep_loot,
		"kills": int(run.stats.get("kills", 0)),
		"bosses": int(run.stats.get("bosses", 0)),
		"best_hit": int(run.stats.get("best_hit", 0)),
		"elapsed": run.elapsed_seconds,
	}
	if keep_loot:
		profile.add_gold(run.run_gold)
		for id: Variant in run.run_materials.keys():
			profile.add_material(StringName(id), int(run.run_materials[id]))
		for item: ItemInstance in run.run_items:
			profile.storage.append(item)
		profile.stats["extractions"] = int(profile.stats.get("extractions", 0)) + 1
	profile.stats["runs"] = int(profile.stats.get("runs", 0)) + 1
	profile.stats["kills"] = int(profile.stats.get("kills", 0)) + int(run.stats.get("kills", 0))
	profile.stats["bosses"] = int(profile.stats.get("bosses", 0)) + int(run.stats.get("bosses", 0))
	profile.stats["deepest_floor"] = maxi(int(profile.stats.get("deepest_floor", 0)), run.floor_index)
	profile.day += 1
	# Погибшие герои возвращаются в строй вместе со своим снаряжением.
	# Раны и павшие сохраняются: восстановление происходит у Алтаря в деревне.
	SaveSystem.delete_run()
	SaveSystem.save_profile()
	GameState.run = null
	EventBus.run_ended.emit(summary)
	Log.info("Забег завершён: %s, этаж %d" % [outcome, summary["floor"]])
	return summary

## Новые биомы открываются по глубине — это и есть причина спускаться дальше.
func _unlock_biome_for_depth() -> void:
	const ORDER: Array[StringName] = [&"catacombs", &"mines", &"mushroom_caves", &"swamp",
		&"necropolis", &"ice_fortress"]
	var thresholds := [0, 0, 4, 7, 11, 15]
	var profile := GameState.profile
	for i: int in ORDER.size():
		if run.floor_index < thresholds[i]:
			continue
		if profile.unlocked_biomes.has(ORDER[i]):
			continue
		profile.unlocked_biomes.append(ORDER[i])
		var biome := Database.get_biome(ORDER[i])
		EventBus.notify("Открыт биом: %s" % (biome.display_name if biome else String(ORDER[i])))
		return
