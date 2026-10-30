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

func already_met(_player: Node) -> bool:
	return false
