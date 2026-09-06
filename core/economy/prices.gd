class_name Prices
extends RefCounted
## Цены покупки и продажи (07-economy.md). ХАР основного героя влияет на наценку.

const BASE_MARKUP := 1.35
const SELL_RATIO := 0.4

static func buy_price(item: ItemInstance, charisma_mod: int) -> int:
	var markup: float = maxf(1.05, BASE_MARKUP - charisma_mod * 0.04)
	return maxi(1, int(round(item.value() * markup)))

static func sell_price(item: ItemInstance, charisma_mod: int) -> int:
	var ratio: float = clampf(SELL_RATIO + charisma_mod * 0.02, 0.25, 0.7)
	return maxi(1, int(round(item.value() * ratio)))
