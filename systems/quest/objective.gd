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
## turned in before the quest was taken still counts.
func already_met(player: Node) -> bool:
	if kind == "quest_done" and target != "":
		var qm = player.get("quests") if player != null else null
		return qm != null and qm.is_completed(target)
	return false
