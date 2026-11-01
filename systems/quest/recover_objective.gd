class_name RecoverObjective
extends Objective
## "Recover X": pick up a quest item (a key) or reach a ward beacon. Its target is the item's
## id (see QuestItems). Counts even if it was recovered before the quest was taken, because
## QuestManager keeps what's been recovered apart from quest progress.


func _init() -> void:
	kind = "recover"


func already_met(player: Node) -> bool:
	var qm = player.get("quests") if player != null else null
	return qm != null and qm.has_recovered(target)
