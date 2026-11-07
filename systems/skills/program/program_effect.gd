class_name ProgramEffect
extends Resource
## A "do" block: move one knob of the skill by a number of steps (negative = the other way).

@export var knob: StringName
@export var steps: int = 1
## Only for a variable write (ScriptRegisters): [reg] [op] [steps], steps being the value.
@export var reg: int = 0                       # index in ScriptRegisters.NAMES
@export var op: int = 1                        # index in ScriptRegisters.WRITE_OPS: +=
## A buff that grows with a counter: its index in ScriptRegisters.NAMES (-1 = always full strength).
## steps is then how fast it grows: one step's worth every ScriptRegisters.RAMP_PER_STEP counts.
## Damage has 5% steps, so 1 step reads  damage += x * 1%  and 2 steps  damage += x * 2%.
@export var ramp: int = -1


static func make(knob_id: StringName, step_count: int) -> ProgramEffect:
	var e := ProgramEffect.new()
	e.knob = knob_id
	e.steps = step_count
	return e


static func make_write(reg_name: String, op_text: String, value: int) -> ProgramEffect:
	var e := make(ScriptRegisters.WRITE_KNOB, value)
	e.reg = ScriptRegisters.NAMES.find(reg_name)
	e.op = ScriptRegisters.WRITE_OPS.find(op_text)
	return e


func register_name() -> String:
	return ScriptRegisters.NAMES[posmod(reg, ScriptRegisters.NAMES.size())]


func write_op() -> String:
	return ScriptRegisters.WRITE_OPS[posmod(op, ScriptRegisters.WRITE_OPS.size())]


func describe_write() -> String:
	return "%s %s %d" % [register_name(), write_op(), steps]


func ramps() -> bool:
	return ramp >= 0


func ramp_register() -> String:
	return ScriptRegisters.NAMES[posmod(ramp, ScriptRegisters.NAMES.size())]


## How the editor shows the token choosing what it grows with.
func ramp_text() -> String:
	return ramp_register() if ramps() else ""


func to_dict() -> Dictionary:
	var d := {"knob": String(knob), "steps": steps}
	if ramps():
		d["ramp"] = ramp
	if ScriptRegisters.is_write(knob):
		d["reg"] = reg
		d["op"] = op
	return d


static func from_dict(d: Dictionary) -> ProgramEffect:
	var e := make(StringName(str(d.get("knob", ""))), int(d.get("steps", 0)))
	e.reg = int(d.get("reg", 0))
	e.op = int(d.get("op", 1))
	e.ramp = int(d.get("ramp", -1))
	return e
