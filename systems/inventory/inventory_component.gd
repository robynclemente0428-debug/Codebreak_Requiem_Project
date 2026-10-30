class_name InventoryComponent
extends Node
## The player's backpack: a fixed number of slots holding ItemInstances.
## Pure data, no UI. Add it as a child node of the player (never as an autoload).

const RARITY_ORDER := {"normal": 0, "magic": 1, "rare": 2, "skill_gem": -1, "support_gem": -1}

@export var capacity: int = 30

var items: Array[ItemInstance] = []

signal changed


func is_full() -> bool:
	return items.size() >= capacity


func has_item(item: ItemInstance) -> bool:
	return items.has(item)


## Returns false (and does nothing) if the backpack is full.
func add_item(item: ItemInstance) -> bool:
	if item == null or is_full():
		return false
	items.append(item)
	changed.emit()
	return true


func remove_item(item: ItemInstance) -> bool:
	var index := items.find(item)
	if index < 0:
		return false
	items.remove_at(index)
	changed.emit()
	return true


## Highest rarity first, then alphabetical.
func sort_items() -> void:
	items.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool:
		var ra: int = RARITY_ORDER.get(a.rarity, 0)
		var rb: int = RARITY_ORDER.get(b.rarity, 0)
		if ra != rb:
			return ra > rb
		return a.get_display_name() < b.get_display_name())
	changed.emit()
