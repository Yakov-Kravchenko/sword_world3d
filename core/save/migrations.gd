class_name Migrations
extends RefCounted
## Цепочка миграций сейвов. Профиль релизной версии обязан открываться в версии
## с актом III (08-architecture.md, раздел 4.1) — это покрыто тестом.

static func migrate_profile(data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 1))
	while version < ProfileState.SCHEMA_VERSION:
		if version == 0:
			data = _v0_to_v1(data)
		else:
			break
		version += 1
		data["schema_version"] = version
	return data

static func migrate_run(data: Dictionary) -> Dictionary:
	if int(data.get("schema_version", 1)) < 1:
		data["schema_version"] = 1
	return data

static func _v0_to_v1(data: Dictionary) -> Dictionary:
	# Форма миграции: до v1 руда лежала одним числом, а не словарём материалов.
	if data.has("ore") and not data.has("materials"):
		data["materials"] = {"ore_iron": int(data["ore"])}
		data.erase("ore")
	return data
