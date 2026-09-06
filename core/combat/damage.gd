class_name DamageCalc
extends RefCounted
## Порядок применения урона строго фиксирован (02-combat.md, раздел 4.1):
## кости, плоские модификаторы, уязвимость/сопротивление, поглощение, минимум 1.

static func apply_type_modifiers(target: CombatActor, amount: int, type: StringName) -> Dictionary:
	var immune := target.immunities.has(type)
	var resist := target.resistances.has(type)
	var vulnerable := target.vulnerabilities.has(type)
	var value := amount
	if immune:
		value = 0
	elif vulnerable:
		value = value * 2
	elif resist:
		value = int(floor(value / 2.0))
	var absorbed := 0
	if not immune and value > 0:
		absorbed = mini(value, target.absorb + int(target.modifier(&"absorb")))
		value -= absorbed
	if not immune:
		value = maxi(1, value)
	return {"amount": value, "immune": immune, "resisted": resist,
		"vulnerable": vulnerable, "absorbed": absorbed}

## Наносит урон и обновляет состояние актёра. Возвращает событие для ActionResult.
static func deal(target: CombatActor, raw: int, type: StringName, crit: bool,
		balance: BalanceData) -> Dictionary:
	var mods := apply_type_modifiers(target, raw, type)
	var amount: int = mods["amount"]
	var event := {
		"target": String(target.id), "amount": amount, "type": String(type), "crit": crit,
		"raw": raw, "immune": mods["immune"], "resisted": mods["resisted"],
		"vulnerable": mods["vulnerable"], "absorbed": mods["absorbed"],
		"killed": false, "downed": false,
	}
	if amount <= 0:
		return event
	if target.is_down:
		# Урон по лежащему при смерти: 1 провал, крит — 2 (02-combat.md, раздел 4.3).
		target.death_failures += 2 if crit else 1
		if target.death_failures >= balance.death_saves_to_die:
			target.is_dead = true
			event["killed"] = true
		return event
	var absorbed_by_temp := mini(target.temp_hp, amount)
	target.temp_hp -= absorbed_by_temp
	target.hp -= (amount - absorbed_by_temp)
	if target.hp <= 0:
		target.hp = 0
		if target.is_hero:
			target.is_down = true
			target.death_successes = 0
			target.death_failures = 0
			event["downed"] = true
		else:
			target.is_dead = true
			event["killed"] = true
	return event

static func heal(target: CombatActor, amount: int) -> int:
	if target.is_dead or amount <= 0:
		return 0
	var scaled := maxi(1, int(floor(amount * target.multiplier(&"healing_mult"))))
	var before := target.hp
	target.hp = mini(target.effective_max_hp(), target.hp + scaled)
	if target.is_down and target.hp > 0:
		target.is_down = false
		target.death_successes = 0
		target.death_failures = 0
	return target.hp - before

static func describe(event: Dictionary) -> String:
	if bool(event.get("immune", false)):
		return "иммунитет: урона нет"
	var type_key := StringName(event.get("type", ""))
	var text := "%d %s" % [int(event.get("amount", 0)), Stats.DAMAGE_RU.get(type_key, String(type_key))]
	if bool(event.get("vulnerable", false)):
		text += " (уязвимость x2)"
	elif bool(event.get("resisted", false)):
		text += " (сопротивление /2)"
	if int(event.get("absorbed", 0)) > 0:
		text += " (поглощено %d)" % int(event["absorbed"])
	if bool(event.get("crit", false)):
		text += " [крит]"
	return text
