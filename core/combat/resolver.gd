class_name Resolver
extends RefCounted
## Все броски d20: атака, спасбросок, проверка. Преимущество и помеха гасят друг друга
## (02-combat.md, раздел 3.2). Ни одного глобального randi() — только RngStream.

const ADV := 1
const NONE := 0
const DIS := -1

static func resolve_mode(advantages: int, disadvantages: int) -> int:
	if advantages > 0 and disadvantages > 0:
		return NONE
	if advantages > 0:
		return ADV
	if disadvantages > 0:
		return DIS
	return NONE

## Бросок d20 с учётом режима. Возвращает {natural, rolls, mode}.
static func roll_d20(rng: RngStream, mode: int = NONE) -> Dictionary:
	var a := rng.randi_range(1, 20)
	if mode == NONE:
		return {"natural": a, "rolls": [a], "mode": mode}
	var b := rng.randi_range(1, 20)
	var pick := maxi(a, b) if mode == ADV else mini(a, b)
	return {"natural": pick, "rolls": [a, b], "mode": mode}

static func mode_text(mode: int) -> String:
	if mode == ADV:
		return " [преимущество]"
	if mode == DIS:
		return " [помеха]"
	return ""

## Бросок атаки. Возвращает запись броска для лога и ActionResult.
static func attack_roll(rng: RngStream, attack_bonus: int, target_ac: int, mode: int,
		crit_threshold: int, label: String = "атака") -> Dictionary:
	var d := roll_d20(rng, mode)
	var natural: int = d["natural"]
	var total: int = natural + attack_bonus
	var crit: bool = natural >= crit_threshold
	var auto_miss: bool = natural == 1
	var hit: bool = crit or (not auto_miss and total >= target_ac)
	var verdict := "КРИТ" if crit else ("попадание" if hit else "промах")
	var line := "d20(%d)%s %+d = %d против КБ %d -> %s" % [
		natural, mode_text(mode), attack_bonus, total, target_ac, verdict]
	return {
		"kind": "attack", "label": label, "natural": natural, "rolls": d["rolls"],
		"mode": mode, "bonus": attack_bonus, "total": total, "dc": target_ac,
		"hit": hit, "crit": crit, "success": hit, "text": line,
	}

## Спасбросок против СЛ.
static func saving_throw(rng: RngStream, actor: CombatActor, stat_key: StringName, dc: int,
		mode: int = NONE) -> Dictionary:
	# Оглушение и паралич: автопровал спасбросков СИЛ и ЛОВ (02-combat.md, раздел 7).
	if (stat_key == Stats.STR or stat_key == Stats.DEX) and actor.has_flag_status(&"skip_turn"):
		return {"kind": "save", "label": String(stat_key), "natural": 0, "rolls": [],
			"mode": NONE, "bonus": 0, "total": 0, "dc": dc, "success": false,
			"text": "автопровал спасброска %s" % Stats.RU.get(stat_key, stat_key)}
	var bonus := actor.save_bonus(stat_key)
	var d := roll_d20(rng, mode)
	var natural: int = d["natural"]
	var total: int = natural + bonus
	var success: bool = total >= dc
	var line := "спасбросок %s: d20(%d)%s %+d = %d против СЛ %d -> %s" % [
		Stats.RU.get(stat_key, stat_key), natural, mode_text(mode), bonus, total, dc,
		("успех" if success else "провал")]
	return {"kind": "save", "label": String(stat_key), "natural": natural, "rolls": d["rolls"],
		"mode": mode, "bonus": bonus, "total": total, "dc": dc, "success": success, "text": line}

## Проверка характеристики вне боя (поиск, отмычки, скрытность).
static func ability_check(rng: RngStream, actor: CombatActor, stat_key: StringName, dc: int,
		proficient: bool = false, mode: int = NONE) -> Dictionary:
	var bonus := actor.stat_mod(stat_key) + (actor.proficiency if proficient else 0)
	var d := roll_d20(rng, mode)
	var natural: int = d["natural"]
	var total: int = natural + bonus
	return {"kind": "check", "label": String(stat_key), "natural": natural,
		"rolls": d["rolls"], "mode": mode, "bonus": bonus, "total": total, "dc": dc,
		"success": total >= dc,
		"text": "проверка %s: d20(%d) %+d = %d против СЛ %d -> %s" % [
			Stats.RU.get(stat_key, stat_key), natural, bonus, total, dc,
			("успех" if total >= dc else "провал")]}

## Спасбросок от смерти (02-combat.md, раздел 4.3).
static func death_save(rng: RngStream, dc: int) -> Dictionary:
	var natural := rng.randi_range(1, 20)
	var verdict := "успех" if natural >= dc else "провал"
	if natural == 20:
		verdict = "критический успех"
	elif natural == 1:
		verdict = "критический провал"
	return {"kind": "death_save", "natural": natural, "dc": dc, "success": natural >= dc,
		"text": "спасбросок от смерти: d20(%d) -> %s" % [natural, verdict]}
