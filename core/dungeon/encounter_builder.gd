class_name EncounterBuilder
extends RefCounted
## Состав встречи по бюджету очков опасности (02-combat.md, раздел 10.3).

var balance: BalanceData
var biome: BiomeData
var rng: RngStream
## id -> EnemyData; заполняется игровым слоем, чтобы core не знал про Database.
var enemy_db: Dictionary = {}

func _init(balance_data: BalanceData, biome_data: BiomeData, stream: RngStream,
		enemies: Dictionary = {}) -> void:
	balance = balance_data
	biome = biome_data
	rng = stream
	enemy_db = enemies

func build(room: FloorPlan.Room, depth: int, multiplier: float, elite: bool,
		kind: StringName = &"") -> Dictionary:
	var budget := balance.encounter_budget(depth, multiplier)
	var chosen: Array[StringName] = []
	var support_count := 0
	var spent := 0
	var guard := 0
	while spent < budget and chosen.size() < balance.max_enemies_per_room and guard < 64:
		guard += 1
		var id: StringName = _pick_enemy()
		if id == &"":
			break
		var data: EnemyData = enemy_db.get(id, null)
		var cost: int = data.danger_points if data != null else 8
		var behavior: StringName = data.behavior if data != null else &"aggressive"
		if behavior == &"support":
			if support_count >= 2:
				continue
			support_count += 1
		if spent + cost > budget and not chosen.is_empty():
			break
		chosen.append(id)
		spent += cost
	if chosen.is_empty():
		var fallback: StringName = _pick_enemy()
		if fallback != &"":
			chosen.append(fallback)
	# «Якорь» — усиленный враг при большом бюджете.
	var elites: Array[StringName] = []
	if elite and not chosen.is_empty():
		elites.append(chosen[0])
	elif budget > 60 and not chosen.is_empty():
		elites.append(chosen[0])
	var resolved := kind
	if resolved == &"":
		resolved = &"elite" if elite else &"normal"
	return {"room": room.index, "enemies": chosen, "elites": elites,
		"kind": resolved, "budget": budget, "spent": spent}

func build_boss(room: FloorPlan.Room, depth: int) -> Dictionary:
	var boss_id: StringName = &"bone_abbot" if depth <= balance.act_length_floors else &"mother_of_bogs"
	var escort: Array[StringName] = []
	for i: int in 2:
		var id: StringName = _pick_enemy()
		if id != &"":
			escort.append(id)
	return {"room": room.index, "enemies": [boss_id] + escort, "elites": [],
		"kind": &"boss", "budget": 0, "spent": 0}

func _pick_enemy() -> StringName:
	if biome.enemy_pool.is_empty():
		return &""
	var weights: Array = []
	for i: int in biome.enemy_pool.size():
		weights.append(float(biome.enemy_weights[i]) if i < biome.enemy_weights.size() else 1.0)
	return rng.pick_weighted(biome.enemy_pool, weights)
