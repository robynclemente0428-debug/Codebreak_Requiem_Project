class_name Objective
extends Resource

@export var description: String = "Kill 5 Grunt Drones"
@export var kind: String = "kill"
@export var target: String = ""            # "" = matches anything of that kind
@export var required: int = 1
@export var hidden: bool = false

## Does this event count toward me? Override for fancier rules.
func matches(event_kind: String, event_target: String) -> bool:
	return event_kind == kind and (target == "" or target == event_target)

## Done before the quest reached this step? "quest_done" checks the quest log, so an exam
## turned in before the quest was taken still counts. Named kills and areas reached
## (QuestManager.DEED_KINDS with a target) count from before too: the gate guard killed on
## the way through. "Kill anything" (no target) only counts once the quest is on.
func already_met(player: Node) -> bool:
	if target == "":
		return false
	var qm = player.get("quests") if player != null else null
	if qm == null:
		return false
	if kind == "quest_done":
		return qm.is_completed(target)
	if kind in QuestManager.DEED_KINDS:
		return qm.deed_count(kind, target) >= required
	return false
