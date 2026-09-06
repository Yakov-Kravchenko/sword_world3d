extends Node
## Единственный способ связи UI и логики (08-architecture.md, раздел 3.1).
## Никаких get_node("../../..").

# --- Бой ---
signal combat_started(state: CombatState)
signal turn_started(actor_id: StringName)
signal action_resolved(result: ActionResult)
signal damage_dealt(target_id: StringName, amount: int, type: StringName, is_crit: bool)
signal status_applied(target_id: StringName, status: StringName, stacks: int)
signal actor_died(actor_id: StringName)
signal combat_ended(victory: bool)
signal combat_log_appended(line: String)

# --- Забег ---
signal floor_loaded(floor_index: int, biome: StringName)
signal torch_state_changed(ticks_left: int)
signal blessing_offered(options: Array)
signal blessing_chosen(blessing: BlessingData)
signal run_started(seed_value: int)
signal run_ended(summary: Dictionary)
signal extraction_offered(floor_index: int)
signal rest_taken(floor_index: int)

# --- Инвентарь и мета ---
signal item_acquired(item: ItemInstance)
signal currency_changed(kind: StringName, amount: int)
signal upgrade_attempted(item: ItemInstance, success: bool)
signal party_changed()
signal notice(text: String)

func notify(text: String) -> void:
	notice.emit(text)
	Log.info(text)
