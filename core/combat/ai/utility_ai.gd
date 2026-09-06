class_name UtilityAI
extends RefCounted
## Оценка полезности вместо дерева поведения (02-combat.md, раздел 10.2).
## Перебор ограничен balance.ai_max_eval_positions с ранним отсечением.

const WEIGHTS := {
	&"aggressive": {"dmg": 1.0, "kill": 8.0, "safety": 0.0, "risk": 0.2, "close": 0.6},
	&"ranged": {"dmg": 1.0, "kill": 7.0, "safety": 1.2, "risk": 1.5, "close": -0.8},
	&"support": {"dmg": 0.4, "kill": 4.0, "safety": 1.5, "risk": 1.2, "close": -0.5},
	&"ambush": {"dmg": 1.2, "kill": 8.0, "safety": 0.8, "risk": 1.0, "close": 0.2},
	&"swarm": {"dmg": 1.0, "kill": 6.0, "safety": 0.0, "risk": 0.1, "close": 1.0},
	&"guard": {"dmg": 1.0, "kill": 7.0, "safety": 0.5, "risk": 0.8, "close": 0.1},
}

## Возвращает список действий, которые надо провести через engine.submit().
static func plan_turn(state: CombatState, actor: CombatActor) -> Array:
	var plan: Array = []
	var targets := _targets_for(state, actor)
	if targets.is_empty() or actor.attacks.is_empty():
		return plan
	var weights: Dictionary = WEIGHTS.get(actor.behavior, WEIGHTS[&"aggressive"])
	var positions := _candidate_cells(state, actor)
	var best: Dictionary = {}
	var best_score: float = -1e9
	# Режим броска и приоритет цели считаем один раз на цель, а не на каждую клетку:
	# перебор 40 позиций x 8 целей x 6 способностей иначе не укладывается в бюджет хода.
	for target: CombatActor in targets:
		var context := _target_context(state, actor, target)
		for attack: AttackData in actor.attacks:
			for cell: Vector2i in positions:
				var score := _score(state, actor, target, attack, cell, weights, context)
				if score > best_score:
					best_score = score
					best = {"cell": cell, "target": target, "attack": attack}
	if best.is_empty():
		return plan
	if best["cell"] != actor.cell:
		plan.append({"kind": "move", "cell": best["cell"]})
	plan.append({"kind": "attack", "target": best["target"], "attack": best["attack"]})
	return plan

## Постоянные для цели величины: режим броска, КБ, приоритет.
static func _target_context(state: CombatState, actor: CombatActor, target: CombatActor) -> Dictionary:
	var probe := AttackData.new()
	probe.range_cells = 1
	var melee_mode: int = AttackAction.compute_mode(state, actor, target, probe)["mode"]
	var priority := 1.0 + (1.0 - target.hp_ratio())
	if target.effective_ac() <= 12:
		priority *= 1.3
	if String(actor.flags.get(&"taunted_by", "")) == String(target.id):
		priority *= 3.0
	elif actor.flags.has(&"taunted_by"):
		priority *= 0.5
	if target.is_down:
		priority *= 0.2
	return {"mode": melee_mode, "ac": target.effective_ac(), "priority": priority}

static func _targets_for(state: CombatState, actor: CombatActor) -> Array[CombatActor]:
	var out: Array[CombatActor] = []
	var enemy_team := CombatActor.TEAM_PARTY if actor.team == CombatActor.TEAM_ENEMY else CombatActor.TEAM_ENEMY
	for a: CombatActor in state.team_actors(enemy_team):
		if a.is_dead:
			continue
		out.append(a)
	return out

## Клетки-кандидаты: текущая + достижимые, обрезанные до лимита перебора.
static func _candidate_cells(state: CombatState, actor: CombatActor) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [actor.cell]
	var reach := MoveAction.reachable(state, actor)
	var keys: Array = reach.keys()
	if keys.size() > state.balance.ai_max_eval_positions:
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return int(reach[a]) < int(reach[b]))
		keys.resize(state.balance.ai_max_eval_positions)
	for c: Vector2i in keys:
		if c != actor.cell:
			cells.append(c)
	return cells

static func _score(state: CombatState, actor: CombatActor, target: CombatActor,
		attack: AttackData, cell: Vector2i, weights: Dictionary, context: Dictionary) -> float:
	var dist := CombatGrid.distance(cell, target.cell)
	if dist > attack.range_cells:
		# Позиция не позволяет ударить: ценность только в сближении.
		return -float(dist) * 0.5 + float(weights["close"]) * 2.0
	if attack.range_cells > 1 and not state.grid.has_line_of_sight(cell, target.cell):
		return -50.0
	var mode: int = int(context["mode"])
	if attack.range_cells > 1 and state.adjacent_enemies_of_cell(cell, actor.team) > 0:
		mode = Resolver.resolve_mode(1 if mode == Resolver.ADV else 0, 1)
	var ac: int = int(context["ac"])
	if attack.range_cells > 1:
		ac += state.grid.cover_bonus(cell, target.cell,
			state.balance.cover_half_ac, state.balance.cover_three_quarter_ac)
	var hit_chance := _hit_chance(AttackAction.attack_bonus(actor, attack), ac, mode)
	var avg_damage := Dice.average(attack.damage_dice)
	if attack.adds_stat_to_damage and attack.attack_stat != &"":
		avg_damage += actor.stat_mod(attack.attack_stat)
	var expected: float = hit_chance * avg_damage
	var score: float = expected * float(weights["dmg"]) * float(context["priority"])
	if expected >= target.hp * 0.9:
		score += float(weights["kill"])
	score -= state.adjacent_enemies_of_cell(cell, actor.team) * float(weights["safety"])
	score -= _opportunity_risk(state, actor, cell) * float(weights["risk"])
	score -= float(dist) * 0.15
	return score

static func _hit_chance(bonus: int, ac: int, mode: int) -> float:
	var need := clampi(ac - bonus, 2, 20)
	var p := float(21 - need) / 20.0
	if mode == Resolver.ADV:
		p = 1.0 - pow(1.0 - p, 2.0)
	elif mode == Resolver.DIS:
		p = pow(p, 2.0)
	return clampf(p, 0.05, 0.95)

## Сколько провокаций поймает актёр, уходя из текущей клетки в cell.
static func _opportunity_risk(state: CombatState, actor: CombatActor, cell: Vector2i) -> float:
	if cell == actor.cell:
		return 0.0
	var risk := 0.0
	for a: CombatActor in state.all_actors():
		if a.team == actor.team or not a.is_alive() or a.is_down or a.reaction_left <= 0:
			continue
		if CombatGrid.distance(a.cell, actor.cell) <= 1 and CombatGrid.distance(a.cell, cell) > 1:
			risk += 1.0
	return risk
