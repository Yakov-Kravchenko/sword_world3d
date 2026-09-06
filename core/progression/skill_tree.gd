class_name SkillTree
extends RefCounted
## Дерево навыков строится из данных: UI обязан рисовать то, что пришло,
## а не фиксированную вёрстку (03-characters.md, раздел 4.1).

var nodes: Array = []            # SkillNodeData
var balance: BalanceData
var game_version: String = "1.0"

func _init(all_nodes: Array, balance_data: BalanceData, version: String = "1.0") -> void:
	nodes = all_nodes
	balance = balance_data
	game_version = version

func nodes_for(hero_id: StringName) -> Array:
	var out: Array = []
	for n: SkillNodeData in nodes:
		if n.hero_id != hero_id:
			continue
		if not _version_available(n.available_from_version):
			continue
		out.append(n)
	out.sort_custom(func(a: SkillNodeData, b: SkillNodeData) -> bool:
		if a.branch != b.branch:
			return String(a.branch) < String(b.branch)
		return a.row < b.row)
	return out

## Узлы будущих обновлений грузятся, но игроку не выдаются.
func _version_available(required: String) -> bool:
	return required.to_float() <= game_version.to_float()

func price(node: SkillNodeData) -> int:
	return balance.skill_node_price(node.row)

func can_unlock(node: SkillNodeData, state: CharacterState, gold: int) -> Result:
	if state.unlocked_nodes.has(node.id):
		return Result.fail("Узел уже открыт")
	if not _version_available(node.available_from_version):
		return Result.fail("Откроется в следующем обновлении")
	for req: StringName in node.requires:
		if not state.unlocked_nodes.has(req):
			return Result.fail("Нужен предыдущий узел ветки")
	if state.skill_points < node.skill_points:
		return Result.fail("Не хватает очков навыков")
	if gold < price(node):
		return Result.fail("Не хватает золота: нужно %d" % price(node))
	return Result.good(price(node))

## Открывает узел и пересчитывает модификаторы героя.
func unlock(node: SkillNodeData, state: CharacterState) -> void:
	state.unlocked_nodes.append(node.id)
	state.skill_points -= node.skill_points
	if node.grants_spell != &"" and not state.known_spells.has(node.grants_spell):
		state.known_spells.append(node.grants_spell)
	recompute(state)

func recompute(state: CharacterState) -> void:
	state.skill_modifiers.clear()
	for n: SkillNodeData in nodes:
		if not state.unlocked_nodes.has(n.id):
			continue
		for k: Variant in n.modifiers.keys():
			var key := StringName(k)
			state.skill_modifiers[key] = float(state.skill_modifiers.get(key, 0.0)) + float(n.modifiers[k])

## Сброс дерева: золото возвращается со штрафом, очки — полностью.
func respec(state: CharacterState) -> int:
	var spent := 0
	for n: SkillNodeData in nodes:
		if state.unlocked_nodes.has(n.id):
			spent += price(n)
			state.skill_points += n.skill_points
	state.unlocked_nodes.clear()
	state.skill_modifiers.clear()
	return int(round(spent * (1.0 - balance.skill_tree_respec_penalty)))
