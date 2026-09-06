class_name RunState
extends RefCounted
## Состояние активного забега (04-dungeon.md, раздел 2; 08-architecture.md, раздел 7.1).

var run_seed: int = 0
var floor_index: int = 1
var current_biome: StringName = &""
## Биомы, уже использованные в этом забеге — повтор запрещён, пока пул не исчерпан.
var used_biomes: Array[StringName] = []
var party: Array[CharacterState] = []
var blessings: Array = []                 # BlessingData
var taken_blessing_ids: Array[StringName] = []
var reroll_available: bool = true
var torch_ticks_left: int = 0
var torch_lit: bool = false
## Добыча забега: теряется при гибели отряда, сохраняется при выходе через Врата.
var run_gold: int = 0
var run_materials: Dictionary = {}
var run_items: Array[ItemInstance] = []
var floors_cleared: int = 0
var combat_index: int = 0
var elapsed_seconds: float = 0.0
var stats: Dictionary = {"kills": 0, "best_hit": 0, "bosses": 0, "rooms_cleared": 0}
var cleared_rooms: Array[int] = []
## Комнаты, в которых отряд уже побывал — для миникарты.
var visited_rooms: Array[int] = []
var looted_props: Array[int] = []
var finished: bool = false
var outcome: StringName = &""             # extracted | wiped | completed

func alive_party() -> Array[CharacterState]:
	var out: Array[CharacterState] = []
	for c: CharacterState in party:
		if not c.is_dead_this_run:
			out.append(c)
	return out

func is_wiped() -> bool:
	return alive_party().is_empty()

func member(hero_id: StringName) -> CharacterState:
	for c: CharacterState in party:
		if c.hero_id == hero_id:
			return c
	return null

## Поток RNG подсистемы: изменение одного не сдвигает другой (08-architecture.md, раздел 5).
func stream(name: StringName, salt: Variant = "") -> RngStream:
	return RngStream.new(RngStream.hash_combine(run_seed, "%s|%s" % [name, salt]), name)

## Факел: 1 секунда исследования = 1 тик, раунд боя = 6 тиков.
func tick_torch(amount: int, balance: BalanceData) -> Dictionary:
	if not torch_lit:
		return {"lit": false, "left": 0, "warning": false, "went_out": false}
	var before := torch_ticks_left
	torch_ticks_left = maxi(0, torch_ticks_left - amount)
	var went_out := before > 0 and torch_ticks_left == 0
	if went_out:
		torch_lit = false
	return {"lit": torch_lit, "left": torch_ticks_left, "went_out": went_out,
		"warning": torch_ticks_left > 0 and torch_ticks_left <= balance.torch_warn_ticks}

func light_torch(ticks: int) -> void:
	torch_ticks_left = ticks
	torch_lit = true

func add_gold(amount: int) -> void:
	run_gold += maxi(0, amount)

func add_material(id: StringName, amount: int) -> void:
	run_materials[id] = int(run_materials.get(id, 0)) + amount

func blessing_modifiers() -> Dictionary:
	return BlessingPool.aggregate(blessings)

func act(balance: BalanceData) -> int:
	return balance.act_of_floor(floor_index)

func is_last_floor(balance: BalanceData) -> bool:
	return floor_index >= balance.total_floors

func save_state() -> Dictionary:
	var members: Array = []
	for c: CharacterState in party:
		members.append(c.save_state())
	var bl: Array = []
	for b: BlessingData in blessings:
		bl.append(String(b.id))
	var items: Array = []
	for i: ItemInstance in run_items:
		items.append(i.save_state())
	var mats := {}
	for k: Variant in run_materials.keys():
		mats[String(k)] = int(run_materials[k])
	return {
		"seed": run_seed, "floor": floor_index, "biome": String(current_biome),
		"party": members, "blessings": bl, "torch": torch_ticks_left, "torch_lit": torch_lit,
		"gold": run_gold, "materials": mats, "items": items,
		"floors_cleared": floors_cleared, "stats": stats.duplicate(),
		"cleared_rooms": cleared_rooms.duplicate(), "visited_rooms": visited_rooms.duplicate(),
		"looted": looted_props.duplicate(),
		"elapsed": elapsed_seconds, "combat_index": combat_index,
		"reroll": reroll_available,
	}
