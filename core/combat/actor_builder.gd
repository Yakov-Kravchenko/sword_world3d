class_name ActorBuilder
extends RefCounted
## Сборка CombatActor из данных героя или статблока врага.

static func from_hero(state: CharacterState, balance: BalanceData,
		run_modifiers: Dictionary = {}) -> CombatActor:
	var a := CombatActor.new()
	a.id = state.hero_id
	a.source_id = state.hero_id
	a.display_name = state.data.display_name if state.data != null else String(state.hero_id)
	a.team = CombatActor.TEAM_PARTY
	a.is_hero = true
	a.tint = state.data.tint if state.data != null else Color.WHITE
	a.level = state.level
	a.proficiency = state.proficiency(balance)
	a.save_proficiencies = state.data.save_proficiencies.duplicate() if state.data != null else []
	a.stats = state.data.base_stats.duplicate() if state.data != null else Stats.empty()
	a.modifiers = state.all_modifiers()
	for key: Variant in run_modifiers.keys():
		var k := StringName(key)
		if String(k).ends_with("_mult"):
			a.modifiers[k] = float(a.modifiers.get(k, 1.0)) * float(run_modifiers[key])
		else:
			a.modifiers[k] = float(a.modifiers.get(k, 0.0)) + float(run_modifiers[key])
	a.max_hp = state.max_hp(balance)
	a.hp = clampi(state.hp, 0, a.effective_max_hp())
	a.armor_class = state.armor_class()
	a.absorb = state.absorb()
	a.base_speed = balance.base_speed_cells
	a.casting_stat = state.data.casting_stat if state.data != null else &""
	a.spells = state.known_spells.duplicate()
	a.abilities = state.data.abilities.duplicate() if state.data != null else []
	a.spell_slots_max = balance.slots_for_level(state.level)
	a.spell_slots = state.spell_slots.duplicate() if state.spell_slots.size() > 0 else a.spell_slots_max.duplicate()
	a.darkvision = state.skill_modifiers.get(&"darkvision", 0) > 0
	a.attacks = [_weapon_attack(state)]
	a.is_down = state.hp <= 0
	var bonus := state.main_weapon().bonus_damage_dice() if state.main_weapon() != null else []
	if not bonus.is_empty():
		a.flags[&"bonus_damage_dice"] = bonus
	return a

static func _weapon_attack(state: CharacterState) -> AttackData:
	var attack := AttackData.new()
	var weapon: ItemInstance = state.main_weapon()
	if weapon == null or not (weapon.data is WeaponData):
		attack.id = &"unarmed"
		attack.display_name = "Безоружный удар"
		attack.damage_dice = "1d2"
		attack.damage_type = &"bludgeoning"
		attack.attack_stat = Stats.STR
		attack.uses_proficiency = true
		attack.adds_stat_to_damage = true
		attack.range_cells = 1
		return attack
	var data: WeaponData = weapon.data
	attack.id = data.id
	attack.display_name = weapon.display_name()
	attack.damage_dice = data.damage_dice
	attack.damage_type = data.damage_type
	attack.attack_stat = data.attack_stat
	attack.uses_proficiency = true
	attack.adds_stat_to_damage = true
	attack.range_cells = data.range_cells
	return attack

static func from_enemy(data: EnemyData, index: int, balance: BalanceData,
		elite: bool = false, depth: int = 1) -> CombatActor:
	var a := CombatActor.new()
	a.id = StringName("%s_%d" % [data.id, index])
	a.source_id = data.id
	a.display_name = data.display_name
	a.team = CombatActor.TEAM_ENEMY
	a.tint = data.tint
	a.stats = Stats.from_dict(data.stats)
	a.proficiency = data.proficiency_bonus
	a.save_proficiencies = data.save_proficiencies.duplicate()
	a.max_hp = data.max_hp
	a.armor_class = data.armor_class
	a.base_speed = data.speed_cells
	a.size_cells = data.size_cells
	a.darkvision = data.darkvision
	a.resistances = data.resistances.duplicate()
	a.vulnerabilities = data.vulnerabilities.duplicate()
	a.immunities = data.immunities.duplicate()
	a.status_immunities = data.status_immunities.duplicate()
	a.behavior = data.behavior
	a.morale_threshold = data.morale_threshold
	a.danger_points = data.danger_points
	a.loot_table = data.loot_table
	for atk: AttackData in data.attacks:
		a.attacks.append(atk)
	if a.attacks.is_empty():
		a.attacks.append(_default_attack())
	# Масштабирование по глубине: тир этажа поднимает HP и точность.
	# Шкала хитов и прирост по глубине задаются данными, а не кодом.
	a.max_hp = maxi(1, int(round(a.max_hp * balance.enemy_hp_scale)))
	var depth_tier := maxi(0, int(floor(float(depth - 1) / float(maxi(1, balance.depth_tier_floors)))))
	if depth_tier > 0:
		a.max_hp += int(round(a.max_hp * balance.enemy_hp_per_depth_tier * depth_tier))
		a.armor_class += balance.enemy_ac_per_depth_tier * depth_tier
	if elite:
		a.display_name = "Элитный %s" % data.display_name.to_lower()
		a.max_hp = int(round(a.max_hp * balance.elite_hp_multiplier))
		a.armor_class += balance.elite_ac_bonus
		a.proficiency += balance.elite_proficiency_bonus
		a.danger_points = int(round(a.danger_points * balance.elite_danger_multiplier))
		a.tint = data.tint.lightened(0.25)
	a.hp = a.effective_max_hp()
	return a

static func _default_attack() -> AttackData:
	var attack := AttackData.new()
	attack.id = &"strike"
	attack.display_name = "Удар"
	attack.attack_bonus = 3
	attack.damage_dice = "1d6"
	return attack
