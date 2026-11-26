class_name EquipmentComponent
extends Node

@export var stat_component: StatComponent

var equipped: Dictionary = {}

signal equipment_changed

var sandbox_locked := false


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
	GameEvents.report("equip_slot", str(slot))
	return true


func slot_for(item: ItemInstance) -> int:
	if item == null:
		return -1
	if item.definition.is_stim():
		if item.stim_roll.is_empty():
			StimRoller.recompute(item)
		for s in EquipmentSlots.STIM_SLOTS:
			if not equipped.has(s):
				return s
		return EquipmentSlots.STIM_SLOTS[0]
	return item.definition.get_slot()


var last_block_reason: String = ""


func can_equip(item: ItemInstance) -> bool:
	last_block_reason = ""
	if sandbox_locked:
		last_block_reason = "The exam uses its own loadout."
		return false
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


func unequip(slot: int) -> bool:
	last_block_reason = ""
	if sandbox_locked:
		last_block_reason = "The exam uses its own loadout."
		return false
	if not equipped.has(slot):
		return false
	var item: ItemInstance = equipped[slot]
	stat_component.remove_by_source_prefix("item_%s_" % item.definition.id)
	equipped.erase(slot)
	equipment_changed.emit()
	return true


func get_equipped(slot: int) -> ItemInstance:
	return equipped.get(slot)


func swap_to(items: Dictionary) -> void:
	var locked := sandbox_locked
	sandbox_locked = false
	for slot in equipped.keys():
		unequip(slot)
	for slot in items:
		equip(items[slot], slot)
	sandbox_locked = locked
