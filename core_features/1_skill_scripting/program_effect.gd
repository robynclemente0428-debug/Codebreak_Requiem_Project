class_name ProgramEffect
extends Resource

@export var knob: StringName
@export var steps: int = 1
@export var op: int = 0
@export var ramp: int = -1
@export var reg: int = 0
@export var sort_by: int = 0

const CALL_KNOB := &"call"


static func make(knob_id: StringName, step_count: int) -> ProgramEffect:
	var e := ProgramEffect.new()
	e.knob = knob_id
	e.steps = step_count
	return e


static func make_write(op_text: String) -> ProgramEffect:
	var e := make(ScriptRegisters.WRITE_KNOB, 1)
	e.op = maxi(ScriptRegisters.WRITE_OPS.find(op_text), 0)
	return e


static func make_sort(order: int) -> ProgramEffect:
	var e := make_write("sort")
	e.sort_by = order
	return e


static func make_call(index: int) -> ProgramEffect:
	var e := make(CALL_KNOB, 1)
	e.op = index
	return e


func is_call() -> bool:
	return knob == CALL_KNOB


func register_name() -> String:
	return "target"


func write_op() -> String:
	return ScriptRegisters.WRITE_OPS[posmod(op, ScriptRegisters.WRITE_OPS.size())]


func describe_write() -> String:
	if write_op() == "sort":
		return "registry.sort(%s)" % ScriptRegisters.sort_text(sort_by)
	return "registry.%s(target)" % write_op()


func ramps() -> bool:
	return ramp >= 0


func ramp_register() -> String:
	return "size"


func ramp_text() -> String:
	return "registry.size" if ramps() else ""


func to_dict() -> Dictionary:
	var d := {"knob": String(knob), "steps": steps}
	if ramps():
		d["ramp"] = 0
	if ScriptRegisters.is_write(knob):
		d["set_op"] = op
		if write_op() == "sort":
			d["sort_by"] = sort_by
	if is_call():
		d = {"knob": String(CALL_KNOB), "steps": 1, "routine": op}
	return d


static func from_dict(d: Dictionary) -> ProgramEffect:
	var e := make(StringName(str(d.get("knob", ""))), int(d.get("steps", 0)))
	if e.is_call():
		e.steps = 1
		e.op = int(d.get("routine", 0))
		return e
	e.ramp = 0 if int(d.get("ramp", -1)) >= 0 else -1
	if ScriptRegisters.is_write(e.knob):
		if d.has("set_op"):
			e.op = int(d["set_op"])
			e.sort_by = int(d.get("sort_by", 0))
		else:
			var old_op := int(d.get("op", 1))
			e.op = 1 if old_op == 2 or (old_op == 0 and e.steps == 0) else 0
		e.steps = 1
	return e
