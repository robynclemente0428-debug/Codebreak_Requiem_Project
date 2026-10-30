class_name EquipmentComponent
extends Node
## What the character is wearing, one item per slot. Add as a child node of the player.

@export var stat_component: StatComponent

var equipped: Dictionary = {}   # EquipmentSlots.Slot (int) -> ItemInstance

## Fired after anything is equipped or unequipped, so UI can refresh.
signal equipment_changed


## Returns false if the item has no valid slot, or if the two-handed rule blocks it
## (see can_equip()). Whatever was in that slot is removed (its stat modifiers are
## stripped), so grab it with get_equipped() first if you want to keep it.
func equip(item: ItemInstance, slot: int = -1) -> bool:
	if slot < 0 or not item.definition.is_stim():
		slot = slot_for(item)
	if slot < 0:
		return false
	if not can_equip(item):
		return false
	if equipped.has(slot):
		unequip(slot)
	equipped[slot] = item
	for m in item.build_modifiers():
		stat_component.add_modifier(m)
	equipment_changed.emit()
	GameEvents.report("equip", item.definition.id)
	GameEvents.report("equip_slot", str(slot))     # for "equip any weapon" style quests
	return true


## Where equip(item) would put it. Stims take the first empty stim slot (slot 1 if both are full).
func slot_for(item: ItemInstance) -> int:
	if item == null:
		return -1
	if item.definition.is_stim():
		if item.stim_roll.is_empty():
			StimRoller.recompute(item)              # starting gear made from a bare id
		for s in EquipmentSlots.STIM_SLOTS:
			if not equipped.has(s):
				return s
		return EquipmentSlots.STIM_SLOTS[0]
	return item.definition.get_slot()


## Why the last can_equip() call said no ("" if it said yes). Show this in your UI.
var last_block_reason: String = ""


## Two-handed rule: a two-handed weapon needs an empty off-hand, and nothing can go
## in the off-hand while a two-handed weapon is equipped.
func can_equip(item: ItemInstance) -> bool:
	last_block_reason = ""
	var slot: int = slot_for(item)
	if slot == EquipmentSlots.Slot.OFF_HAND \
			and _is_two_handed(get_equipped(EquipmentSlots.Slot.WEAPON)):
		last_block_reason = "Can't use an off-hand with a two-handed weapon."
		return false
	if slot == EquipmentSlots.Slot.WEAPON and _is_two_handed(item) \
			and get_equipped(EquipmentSlots.Slot.OFF_HAND) != null:
		last_block_reason = "Unequip your off-hand first."
		return false
	return true


func _is_two_handed(item: ItemInstance) -> bool:
	return item != null and item.definition.weapon_type != null \
		and item.definition.weapon_type.two_handed


func unequip(slot: int) -> void:
	if not equipped.has(slot):
		return
	var item: ItemInstance = equipped[slot]
	stat_component.remove_by_source_prefix("item_%s_" % item.definition.id)
	equipped.erase(slot)
	equipment_changed.emit()


func get_equipped(slot: int) -> ItemInstance:
	return equipped.get(slot)
