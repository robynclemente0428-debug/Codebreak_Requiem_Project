class_name ItemPricing
extends RefCounted

const RARITY_MULT := {"normal": 1.0, "magic": 2.5, "rare": 6.0, "gem": 4.0}

## The item's "true" value. Shops apply their own buy markup and sell ratio on top.
static func value_of(item: ItemInstance) -> int:
	var def := item.definition
	var v: float = float(def.base_value) * RARITY_MULT.get(item.rarity, 1.0)
	v *= 1.0 + 0.10 * item.rolled_affixes.size()
	v *= 1.0 + 0.05 * maxi(def.item_level - 1, 0)
	return maxi(roundi(v), 1)
