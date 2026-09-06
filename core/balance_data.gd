class_name BalanceData
extends Resource
## Все числа из «Констант» ТЗ. Ни одно из них не должно быть литералом в коде
## (README «Ключевое техническое требование», 08-architecture.md §4.1).

# --- Бой (02-combat.md §13) ---
@export var grid_cell_size: float = 1.5
@export var base_speed_cells: int = 6
@export var round_duration_sec: int = 6
@export var crit_threshold: int = 20
@export var death_save_dc: int = 10
@export var death_saves_to_die: int = 3
@export var death_saves_to_stable: int = 3
@export var cover_half_ac: int = 2
@export var cover_three_quarter_ac: int = 5
@export var high_ground_bonus: int = 1
@export var flanking_requires: int = 2
@export var max_enemies_per_room: int = 8
@export var ai_max_eval_positions: int = 40

# --- Свет (02-combat.md §8) ---
@export var torch_ticks: int = 600
@export var torch_warn_ticks: int = 60
@export var light_bright_cells: int = 6
@export var light_dim_cells: int = 12
@export var darkvision_cells: int = 12

# --- Структура забега (04-dungeon.md §2) ---
@export var act_count: int = 2
@export var act_length_floors: int = 10
@export var total_floors: int = 20
@export var herald_floors: PackedInt32Array = PackedInt32Array([5, 15])
@export var boss_floors: PackedInt32Array = PackedInt32Array([10, 20])
@export var extraction_floors: PackedInt32Array = PackedInt32Array([10, 20])
@export var blessing_floors: PackedInt32Array = PackedInt32Array([5, 10, 15, 20])
@export var segment_length_floors: int = 3

# --- Прогресс (03-characters.md) ---
@export var max_party_level: int = 9
@export var max_spell_level: int = 3
@export var upgrade_max_level: int = 8
@export var max_affix_tier: int = 4
@export var death_rules_preset: String = "roguelite"
## Таблица ячеек: индекс = уровень героя - 1, элемент = ячейки 1..N уровня.
@export var spell_slots: Array = []
## Бонус мастерства по уровню (индекс = уровень - 1).
@export var proficiency_by_level: PackedInt32Array = PackedInt32Array()
## Стоимость уровня в золоте (индекс = целевой уровень - 2).
@export var level_costs: PackedInt32Array = PackedInt32Array()
@export var level_requirements: Array = []
## Кость класса → среднее значение для расчёта HP.
@export var hit_die_average: Dictionary = {}

# --- Шкала врагов (02-combat.md, раздел 10) ---
## Общий множитель хитов врагов: главный рычаг сложности боя.
@export var enemy_hp_scale: float = 1.0
## Прирост хитов и КБ за каждый тир глубины (тир = 5 этажей).
@export var enemy_hp_per_depth_tier: float = 0.18
@export var enemy_ac_per_depth_tier: int = 1
@export var depth_tier_floors: int = 5
## Элита (Страж этажа, Вестник) поверх базового статблока.
@export var elite_hp_multiplier: float = 2.0
@export var elite_ac_bonus: int = 2
@export var elite_proficiency_bonus: int = 1
@export var elite_danger_multiplier: float = 1.8

# --- Экономика (07-economy.md) ---
@export var encounter_budget_base: int = 10
@export var encounter_budget_per_depth: int = 6
@export var encounter_mult_normal: float = 1.0
@export var encounter_mult_elite: float = 1.6
@export var encounter_mult_guardian: float = 2.2
@export var skill_node_price_base: float = 250.0
@export var skill_node_price_exp: float = 1.55
@export var skill_tree_respec_penalty: float = 0.3
@export var upgrade_cost_base: int = 60
@export var upgrade_cost_exp: float = 1.9
@export var upgrade_success_chance: PackedFloat32Array = PackedFloat32Array()

# --- Инвентарь (05-items.md) ---
@export var inventory_width: int = 10
@export var inventory_height: int = 8
@export var carry_base_kg: float = 15.0
@export var carry_per_str: float = 1.5
@export var potion_limit_per_hero: int = 5
@export var antidote_limit_per_hero: int = 5

func slots_for_level(level: int) -> PackedInt32Array:
	var idx := clampi(level - 1, 0, maxi(0, spell_slots.size() - 1))
	if spell_slots.is_empty():
		return PackedInt32Array()
	var raw: Variant = spell_slots[idx]
	var out := PackedInt32Array()
	for v: Variant in raw:
		out.append(int(v))
	return out

func proficiency_for_level(level: int) -> int:
	if proficiency_by_level.is_empty():
		return 2
	return proficiency_by_level[clampi(level - 1, 0, proficiency_by_level.size() - 1)]

func is_boss_floor(floor_index: int) -> bool:
	return boss_floors.has(floor_index)

func is_herald_floor(floor_index: int) -> bool:
	return herald_floors.has(floor_index)

func is_blessing_floor(floor_index: int) -> bool:
	return blessing_floors.has(floor_index)

func is_extraction_floor(floor_index: int) -> bool:
	return extraction_floors.has(floor_index)

func act_of_floor(floor_index: int) -> int:
	return int(ceil(float(floor_index) / float(maxi(1, act_length_floors))))

func encounter_budget(depth: int, room_multiplier: float) -> int:
	return int(round((encounter_budget_base + encounter_budget_per_depth * depth) * room_multiplier))

func skill_node_price(row: int) -> int:
	var raw := skill_node_price_base * pow(float(row), skill_node_price_exp)
	return int(round(raw / 50.0) * 50)
