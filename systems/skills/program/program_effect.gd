class_name ProgramEffect
extends Resource
## A "do" block: move one knob of the skill by a number of steps (negative = the other way).

@export var knob: StringName
@export var steps: int = 1


static func make(knob_id: StringName, step_count: int) -> ProgramEffect:
	var e := ProgramEffect.new()
	e.knob = knob_id
	e.steps = step_count
	return e


func to_dict() -> Dictionary:
	return {"knob": String(knob), "steps": steps}


static func from_dict(d: Dictionary) -> ProgramEffect:
	return make(StringName(str(d.get("knob", ""))), int(d.get("steps", 0)))
