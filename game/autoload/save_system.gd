extends Node
## Сохранения: атомарная запись, резервная копия, версия схемы, миграции
## (08-architecture.md, раздел 7.2).

const SAVE_DIR := "user://saves"
const PROFILE_PATH := "user://saves/profile_1.json"
const RUN_PATH := "user://saves/run_1.json"

signal profile_saved()
signal run_saved()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func save_profile() -> bool:
	if GameState.profile == null:
		return false
	var ok := _write_atomic(PROFILE_PATH, GameState.profile.save_state())
	if ok:
		profile_saved.emit()
	return ok

func save_run() -> bool:
	if GameState.run == null:
		return false
	var data := GameState.run.save_state()
	data["schema_version"] = ProfileState.SCHEMA_VERSION
	var ok := _write_atomic(RUN_PATH, data)
	if ok:
		run_saved.emit()
	return ok

## Пишем в .tmp, старое уводим в .bak, затем переименовываем. Никогда не пишем поверх.
func _write_atomic(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		Log.error("Не удалось открыть %s на запись" % tmp)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	if FileAccess.file_exists(path):
		var backup := path + ".bak"
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path(backup))
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path))
	if err != OK:
		Log.error("Не удалось переименовать %s (%d)" % [tmp, err])
		return false
	return true

func has_profile_file() -> bool:
	return FileAccess.file_exists(PROFILE_PATH)

func has_run_file() -> bool:
	return FileAccess.file_exists(RUN_PATH)

func _read(path: String) -> Dictionary:
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			if candidate.ends_with(".bak"):
				Log.warn("Основной файл повреждён, взята резервная копия")
			return parsed
	return {}

func load_profile() -> bool:
	var data := _read(PROFILE_PATH)
	if data.is_empty():
		return false
	data = Migrations.migrate_profile(data)
	GameState.profile = _profile_from(data)
	EventBus.party_changed.emit()
	return true

## Загрузка забега удаляет файл — защита от save-scumming копированием.
func load_run() -> bool:
	var data := _read(RUN_PATH)
	if data.is_empty():
		return false
	data = Migrations.migrate_run(data)
	GameState.run = _run_from(data)
	delete_run()
	return GameState.run != null

func delete_run() -> void:
	for path: String in [RUN_PATH, RUN_PATH + ".bak", RUN_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# --- Восстановление объектов из JSON ---

func _profile_from(data: Dictionary) -> ProfileState:
	var p := ProfileState.new()
	p.schema_version = int(data.get("schema_version", 1))
	p.profile_seed = int(data.get("profile_seed", 0))
	p.main_hero_id = StringName(data.get("main_hero", "hald"))
	p.day = int(data.get("day", 1))
	p.party_level = int(data.get("party_level", 1))
	p.gold = int(data.get("gold", 0))
	for k: Variant in (data.get("materials", {}) as Dictionary).keys():
		p.materials[StringName(k)] = int(data["materials"][k])
	for entry: Variant in data.get("storage", []):
		var inst := item_from(entry)
		if inst != null:
			p.storage.append(inst)
	for entry: Variant in data.get("party", []):
		p.party.append(character_from(entry))
	for b: Variant in data.get("unlocked_biomes", []):
		p.unlocked_biomes.append(StringName(b))
	p.building_levels = data.get("buildings", p.building_levels)
	p.stats = data.get("stats", p.stats)
	for a: Variant in data.get("achievements", []):
		p.achievements.append(StringName(a))
	return p

func item_from(entry: Variant) -> ItemInstance:
	if not (entry is Dictionary):
		return null
	var d: Dictionary = entry
	var inst := GameState.item_factory.create(StringName(d.get("id", "")), int(d.get("qty", 1)))
	if inst == null:
		return null
	inst.upgrade_level = int(d.get("upgrade", 0))
	inst.rotated = bool(d.get("rotated", false))
	for aid: Variant in d.get("affixes", []):
		var affix: Variant = Database.get_resource(StringName(aid))
		if affix is AffixData:
			inst.affixes.append(affix)
	for sid: Variant in d.get("sockets", []):
		inst.sockets.append(StringName(sid))
	return inst

func character_from(entry: Variant) -> CharacterState:
	var d: Dictionary = entry
	var c := CharacterState.new()
	c.hero_id = StringName(d.get("hero", "hald"))
	c.data = Database.get_hero(c.hero_id)
	c.level = int(d.get("level", 1))
	c.hp = int(d.get("hp", 1))
	c.skill_points = int(d.get("skill_points", 0))
	c.is_dead_this_run = bool(d.get("dead", false))
	c.spell_slots = PackedInt32Array()
	for v: Variant in d.get("slots", []):
		c.spell_slots.append(int(v))
	c.inventory = Inventory.new(Balance.data.inventory_width, Balance.data.inventory_height, 30.0)
	for slot: Variant in (d.get("equipment", {}) as Dictionary).keys():
		var equipped := item_from(d["equipment"][slot])
		if equipped != null:
			c.equipment[StringName(slot)] = equipped
	for raw: Variant in d.get("inventory", []):
		var carried := item_from(raw)
		if carried != null:
			c.inventory.add(carried)
	for n: Variant in d.get("nodes", []):
		c.unlocked_nodes.append(StringName(n))
	for s: Variant in d.get("spells", []):
		c.known_spells.append(StringName(s))
	c.inventory.carry_limit = c.carry_limit(Balance.data)
	GameState.skill_tree.recompute(c)
	return c

func _run_from(data: Dictionary) -> RunState:
	var r := RunState.new()
	r.run_seed = int(data.get("seed", 0))
	r.floor_index = int(data.get("floor", 1))
	r.current_biome = StringName(data.get("biome", "catacombs"))
	r.torch_ticks_left = int(data.get("torch", 0))
	r.torch_lit = bool(data.get("torch_lit", false))
	r.run_gold = int(data.get("gold", 0))
	r.floors_cleared = int(data.get("floors_cleared", 0))
	r.elapsed_seconds = float(data.get("elapsed", 0.0))
	r.combat_index = int(data.get("combat_index", 0))
	r.reroll_available = bool(data.get("reroll", true))
	r.stats = data.get("stats", r.stats)
	for k: Variant in (data.get("materials", {}) as Dictionary).keys():
		r.run_materials[StringName(k)] = int(data["materials"][k])
	for entry: Variant in data.get("items", []):
		var inst := item_from(entry)
		if inst != null:
			r.run_items.append(inst)
	for entry: Variant in data.get("party", []):
		r.party.append(character_from(entry))
	for bid: Variant in data.get("blessings", []):
		var b: Variant = Database.get_resource(StringName(bid))
		if b is BlessingData:
			r.blessings.append(b)
			r.taken_blessing_ids.append(StringName(bid))
	for i: Variant in data.get("cleared_rooms", []):
		r.cleared_rooms.append(int(i))
	for i: Variant in data.get("visited_rooms", []):
		r.visited_rooms.append(int(i))
	for i: Variant in data.get("looted", []):
		r.looted_props.append(int(i))
	return r
