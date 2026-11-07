class_name ItemPricing
extends RefCounted

const RARITY_MULT := {"normal": 1.0, "magic": 2.5, "rare": 6.0, "gem": 4.0}
const PER_MODIFIER := 0.25   # each modifier the item rolled: +25%
const PER_LEVEL := 0.10      # each item level above 1: +10%
const COPIED_MULT := 0.5     # a "COPY OF" item is a novelty: half the value

## The item's "true" value. Shops apply their own buy markup and sell ratio on top.
static func value_of(item: ItemInstance) -> int:
	var def := item.definition
	var v: float = float(def.base_value) * RARITY_MULT.get(item.rarity, 1.0)
	v *= 1.0 + PER_MODIFIER * item.rolled_affixes.size()
	# The level it was rolled at, which sets how strong its modifiers can be, or its base's if higher
	v *= 1.0 + PER_LEVEL * maxi(maxi(item.item_level, def.item_level) - 1, 0)
	if item.copied:
		v *= COPIED_MULT
	return maxi(roundi(v), 1)
