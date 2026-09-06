class_name ShopGenerator
extends RefCounted
## Ассортимент лавки: детерминирован по сиду профиля и дню (08-architecture.md, раздел 5).

const STAPLES: Array[StringName] = [&"potion_minor", &"antidote", &"bandage", &"torch"]
const ROTATING: Array[StringName] = [
	&"potion_greater", &"essence_vial", &"holy_water", &"elixir_might",
	&"sword_notched", &"war_axe", &"rapier", &"crossbow", &"spear", &"staff_charred",
	&"armor_leather", &"armor_gambeson", &"armor_chainmail", &"shield_worn",
	&"shield_tower", &"charm_wood",
]

var factory: ItemFactory

func _init(item_factory: ItemFactory) -> void:
	factory = item_factory

## Возвращает список ItemInstance на продажу.
func generate(profile_seed: int, day: int, shop_level: int, depth_hint: int) -> Array:
	var rng := RngStream.new(RngStream.hash_combine(profile_seed, "shop_%d" % day), &"shop")
	var out: Array = []
	for id: StringName in STAPLES:
		var stock := factory.create(id, rng.randi_range(2, 4))
		if stock != null:
			out.append(stock)
	var slots := 3 + shop_level
	var pool := ROTATING.duplicate()
	rng.shuffle(pool)
	for i: int in mini(slots, pool.size()):
		var item := factory.create_rolled(pool[i], maxi(1, depth_hint), rng)
		if item != null:
			out.append(item)
	return out
