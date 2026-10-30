class_name EquipObjective
extends Objective

func already_met(player: Node) -> bool:
	var eq: EquipmentComponent = player.get("equipment")
	if eq == null:
		return false
	for item: ItemInstance in eq.equipped.values():
		if item.definition.id == target:
			return true
	return false
