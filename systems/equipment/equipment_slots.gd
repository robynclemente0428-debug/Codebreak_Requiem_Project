class_name EquipmentSlots

## APPEND ONLY (saved .tres files store the integer)
enum Slot { WEAPON, OFF_HAND, HEAD, BODY, HANDS, FEET, STIM_1, STIM_2 }

## Stim (health / mana potion) slots, in hotkey order: STIM_1 is key 1, STIM_2 key 2.
const STIM_SLOTS: Array[int] = [Slot.STIM_1, Slot.STIM_2]


static func is_stim_slot(slot: int) -> bool:
	return slot in STIM_SLOTS
