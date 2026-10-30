class_name QuestState
extends RefCounted

enum Status { ACTIVE, READY_TO_TURN_IN, COMPLETED }

var def: QuestDefinition
var progress: Array[int] = []
var status: Status = Status.ACTIVE

func _init(d: QuestDefinition) -> void:
	def = d
	progress.resize(d.objectives.size())
	progress.fill(0)

func objective_done(i: int) -> bool:
	return progress[i] >= def.objectives[i].required

func all_done() -> bool:
	for i in def.objectives.size():
		if not objective_done(i):
			return false
	return true

## Returns true if any progress changed.
func handle_event(kind: String, target: String, amount: int) -> bool:
	var changed := false
	for i in def.objectives.size():
		if objective_done(i):
			continue
		if def.ordered and i > 0 and not objective_done(i - 1):
			break
		if def.objectives[i].matches(kind, target):
			progress[i] = mini(progress[i] + amount, def.objectives[i].required)
			changed = true
	return changed

func to_dict() -> Dictionary:
	return {"id": def.id, "progress": progress, "status": status}
