class_name CombatActor
extends RefCounted
## Участник боя. Чистые данные + производные значения (02-combat.md, разделы 1–4).

const TEAM_PARTY := 0
const TEAM_ENEMY := 1

var id: StringName = &""
var display_name: String = ""
var source_id: StringName = &""
var team: int = TEAM_PARTY
var is_hero: bool = false
var tint: Color = Color.WHITE

var level: int = 1
var stats: Dictionary = {}
var proficiency: int = 2
var save_proficiencies: Array[StringName] = []

var max_hp: int = 10
var hp: int = 10
var temp_hp: int = 0
var armor_class: int = 10
var absorb: int = 0
var base_speed: int = 6
var size_cells: int = 1
var cell: Vector2i = Vector2i.ZERO
var darkvision: bool = false

var resistances: Array[StringName] = []
var vulnerabilities: Array[StringName] = []
var immunities: Array[StringName] = []
var status_immunities: Array[StringName] = []

var behavior: StringName = &"aggressive"
var morale_threshold: float = 0.0
var danger_points: int = 6
var loot_table: StringName = &"common"

var attacks: Array[AttackData] = []
var spells: Array[StringName] = []
var abilities: Array[StringName] = []
var spell_slots: PackedInt32Array = PackedInt32Array()
var spell_slots_max: PackedInt32Array = PackedInt32Array()
var casting_stat: StringName = &""

var statuses: Array[StatusEffect] = []
## Постоянные модификаторы: снаряжение + дерево навыков + благословения.
var modifiers: Dictionary = {}
## Метки на бой/ход: dodging, hidden, taunted_by, concentration, ability_uses.
var flags: Dictionary = {}

var movement_left: int = 0
var action_left: int = 0
var bonus_left: int = 0
var reaction_left: int = 0

## Отладочная неуязвимость: любой урон гасится в ноль. Ставится игровым слоем
## для режима разработчика — core про этот режим ничего не знает.
var invulnerable: bool = false
var is_down: bool = false
var is_dead: bool = false
var has_fled: bool = false
var death_successes: int = 0
var death_failures: int = 0

# --- Производные значения ---

func stat(key: StringName) -> int:
	return int(stats.get(key, 10)) + int(modifier(StringName("stat_" + String(key))))

func stat_mod(key: StringName) -> int:
	return Stats.modifier(stat(key))

func modifier(key: StringName) -> float:
	var total: float = float(modifiers.get(key, 0.0))
	for s: StatusEffect in statuses:
		total += s.modifier(key)
	return total

func multiplier(key: StringName) -> float:
	var total: float = float(modifiers.get(key, 1.0))
	for s: StatusEffect in statuses:
		var m: float = float(s.data.modifiers.get(key, 1.0)) if s.data != null else 1.0
		total *= m
	return total

func effective_ac() -> int:
	return armor_class + int(modifier(&"ac"))

func effective_speed() -> int:
	if has_flag_status(&"blocks_movement"):
		return 0
	var spd := float(base_speed + int(modifier(&"speed"))) * multiplier(&"speed_mult")
	return maxi(0, int(floor(spd)))

func effective_max_hp() -> int:
	var v := float(max_hp + int(modifier(&"max_hp"))) * multiplier(&"max_hp_mult")
	return maxi(1, int(floor(v)))

func save_bonus(key: StringName) -> int:
	var b := stat_mod(key)
	if save_proficiencies.has(key):
		b += proficiency
	return b + int(modifier(&"saves"))

func spell_save_dc() -> int:
	if casting_stat == &"":
		return 8 + proficiency
	return 8 + proficiency + stat_mod(casting_stat) + int(modifier(&"spell_dc"))

func crit_threshold(default_value: int) -> int:
	return maxi(2, default_value - int(modifier(&"crit_threshold")))

func hp_ratio() -> float:
	return 0.0 if effective_max_hp() <= 0 else float(hp) / float(effective_max_hp())

func is_alive() -> bool:
	return not is_dead and not has_fled

## Может действовать: жив, не при смерти, не пропускает ход.
func can_act() -> bool:
	return is_alive() and not is_down and not has_flag_status(&"skip_turn")

# --- Статусы ---

func has_status(status_id: StringName) -> bool:
	for s: StatusEffect in statuses:
		if s.id() == status_id:
			return true
	return false

func get_status(status_id: StringName) -> StatusEffect:
	for s: StatusEffect in statuses:
		if s.id() == status_id:
			return s
	return null

func has_flag_status(flag: StringName) -> bool:
	for s: StatusEffect in statuses:
		if s.data != null and bool(s.data.get(String(flag))):
			return true
	return false

func status_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s: StatusEffect in statuses:
		out.append(s.id())
	return out

# --- Ход ---

func begin_turn(base_movement: int) -> void:
	movement_left = base_movement
	action_left = 1
	bonus_left = 0 if has_flag_status(&"no_bonus_action") else 1
	reaction_left = 0 if has_flag_status(&"no_reaction") else 1
	flags.erase(&"dodging")
	flags.erase(&"disengaging")
	flags.erase(&"helped")

func occupied_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy: int in size_cells:
		for dx: int in size_cells:
			out.append(cell + Vector2i(dx, dy))
	return out

func save_state() -> Dictionary:
	var st: Array = []
	for s: StatusEffect in statuses:
		st.append(s.save_state())
	return {
		"id": String(id), "source": String(source_id), "team": team, "hero": is_hero,
		"hp": hp, "max_hp": max_hp, "temp_hp": temp_hp, "cell": [cell.x, cell.y],
		"down": is_down, "dead": is_dead, "fled": has_fled,
		"death_successes": death_successes, "death_failures": death_failures,
		"slots": Array(spell_slots), "statuses": st, "flags": flags.duplicate(true),
	}
