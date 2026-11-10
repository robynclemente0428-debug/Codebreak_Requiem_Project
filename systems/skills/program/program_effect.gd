class_name ProgramEffect
extends Resource
## A "do" block: move one knob of the skill by a number of steps (negative = the other way).

@export var knob: StringName
@export var steps: int = 1
## Only for a registry write (ScriptRegisters): registry.add(target) or registry.remove(target).
## Its index in ScriptRegisters.WRITE_OPS. A write's steps is always 1.
@export var op: int = 0
## A buff that grows with registry.size (-1 = always full strength, 0 = grows). steps is then how
## fast it grows: one step's worth every ScriptRegisters.RAMP_PER_STEP enemies in the set. Damage
## has 5% steps, so 1 step reads  damage += registry.size * 1%.
@export var ramp: int = -1
## Kept so old scripts load (the slot of the old counters). Unused.
@export var reg: int = 0


static func make(knob_id: StringName, step_count: int) -> ProgramEffect:
	var e := ProgramEffect.new()
	e.knob = knob_id
	e.steps = step_count
	return e


## registry.add(target) or registry.remove(target).
static func make_write(op_text: String) -> ProgramEffect:
	var e := make(ScriptRegisters.WRITE_KNOB, 1)
	e.op = maxi(ScriptRegisters.WRITE_OPS.find(op_text), 0)
	return e


## What a write acts on. Always the enemy hit: the registry is a set of enemies.
func register_name() -> String:
	return "target"


func write_op() -> String:
	return ScriptRegisters.WRITE_OPS[posmod(op, ScriptRegisters.WRITE_OPS.size())]


func describe_write() -> String:
	return "registry.%s(target)" % write_op()


func ramps() -> bool:
	return ramp >= 0


## What a growing buff reads: the set's size.
func ramp_register() -> String:
	return "size"


## How the editor shows the token choosing what it grows with.
func ramp_text() -> String:
	return "registry.size" if ramps() else ""


func to_dict() -> Dictionary:
	var d := {"knob": String(knob), "steps": steps}
	if ramps():
		d["ramp"] = 0
	if ScriptRegisters.is_write(knob):
		d["set_op"] = op
	return d


static func from_dict(d: Dictionary) -> ProgramEffect:
	var e := make(StringName(str(d.get("knob", ""))), int(d.get("steps", 0)))
	e.ramp = 0 if int(d.get("ramp", -1)) >= 0 else -1
	if ScriptRegisters.is_write(e.knob):
		if d.has("set_op"):
			e.op = int(d["set_op"])
		else:
			# A script from the counters: "-=" or "= 0" took away, everything else added.
			var old_op := int(d.get("op", 1))
			e.op = 1 if old_op == 2 or (old_op == 0 and e.steps == 0) else 0
		e.steps = 1
	return e
