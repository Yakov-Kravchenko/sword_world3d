extends Node
## Реестр всего контента (08-architecture.md, раздел 3).
## Каждый файл data/**/*.json — манифест {"class": "...", "entries": [...]}.

var _index: ContentIndex

func _ready() -> void:
	load_all()

func load_all() -> void:
	Log.perf_start("database_load")
	_index = ContentIndex.load_from("res://data", true)
	Log.perf_end("database_load")
	Log.info("Database: %d файлов, %d записей" % [_index.files, _index.by_id.size()])
	for err: String in _index.errors:
		Log.error("Database: " + err)

func errors() -> Array[String]:
	return _index.errors if _index != null else []

func has(id: StringName) -> bool:
	return _index != null and _index.by_id.has(id)

func get_resource(id: StringName) -> Resource:
	return _index.get_resource(id) if _index != null else null

func get_item(id: StringName) -> ItemData:
	var r := get_resource(id)
	return r if r is ItemData else null

func get_hero(id: StringName) -> HeroData:
	var r := get_resource(id)
	return r if r is HeroData else null

func get_enemy(id: StringName) -> EnemyData:
	var r := get_resource(id)
	return r if r is EnemyData else null

func get_spell(id: StringName) -> SpellData:
	var r := get_resource(id)
	return r if r is SpellData else null

func get_status(id: StringName) -> StatusData:
	var r := get_resource(id)
	return r if r is StatusData else null

func get_biome(id: StringName) -> BiomeData:
	var r := get_resource(id)
	return r if r is BiomeData else null

func get_ability(id: StringName) -> AbilityData:
	var r := get_resource(id)
	return r if r is AbilityData else null

func get_loot_table(id: StringName) -> LootTable:
	var r := get_resource(id)
	return r if r is LootTable else null

func of_class(cls: String) -> Array:
	return _index.of_class(cls) if _index != null else []

func status_map() -> Dictionary:
	return _index.map_of_class("StatusData") if _index != null else {}

func spell_map() -> Dictionary:
	return _index.map_of_class("SpellData") if _index != null else {}

func enemy_map() -> Dictionary:
	return _index.map_of_class("EnemyData") if _index != null else {}

func item_map() -> Dictionary:
	var out := {}
	for cls: String in ["ItemData", "WeaponData", "ArmorData", "ConsumableData"]:
		out.merge(_index.map_of_class(cls) if _index != null else {})
	return out
