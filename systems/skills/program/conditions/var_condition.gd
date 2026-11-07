class_name VarCondition
extends ProgramCondition
## WHEN a variable compares true: when [x] [>=] [3]:  (see ScriptRegisters). All three parts are
## tokens the player clicks, like the Act II patch puzzles. The script decides how often this is
## true, so it gets one flat discount, whatever the comparison is. That holds even if nothing in
## the script lowers the counter, since counters clear after every fight (ScriptRegisters).

const COST_MULT := 0.75

@export var reg: int = 0                       # index in ScriptRegisters.NAMES
@export var op: int = 3                        # index in ScriptRegisters.OPS: >=
@export var value: int = 3


static func make(reg_name: String, op_text: String, n: int) -> VarCondition:
	var c := VarCondition.new()
	c.reg = ScriptRegisters.NAMES.find(reg_name)
	c.op = ScriptRegisters.OPS.find(op_text)
	c.value = n
	return c


func register_name() -> String:
	return ScriptRegisters.NAMES[reg]


func op_text() -> String:
	return ScriptRegisters.OPS[op]


func type_id() -> String:
	return "var_compare"


## Two different comparisons are different branches, so The Mimic's DIFF can tell them apart.
func fired_id() -> String:
	return "%s%s%d" % [register_name(), op_text(), value]


func allows_repeats() -> bool:
	return true


func changes_during_cast() -> bool:
	return true


func modular() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	return ScriptRegisters.compare(ProgramSupport.register_value(cast.skill, register_name()), op_text(), value)


## "always" or "never" when no value a register can hold changes the answer, otherwise "".
func constant_answer() -> String:
	var first := ScriptRegisters.compare(0, op_text(), value)
	for v in range(1, ScriptRegisters.MAX_VALUE + 1):
		if ScriptRegisters.compare(v, op_text(), value) != first:
			return ""
	return "always" if first else "never"


func cost_multiplier() -> float:
	return COST_MULT


func describe() -> String:
	return "WHEN %s %s %d" % [register_name(), op_text(), value]


func param_names() -> PackedStringArray:
	return PackedStringArray(["reg", "op", "value"])


func param_text(param: String) -> String:
	match param:
		"reg":
			return register_name()
		"op":
			return op_text()
	return str(value)


func param_label(param: String) -> String:
	return {"reg": "COUNTER", "op": "OPERATOR", "value": "VALUE"}.get(param, param.to_upper())


func palette_name() -> String:
	return "COUNTER"


func clamp_params() -> void:
	reg = posmod(reg, ScriptRegisters.NAMES.size())
	op = posmod(op, ScriptRegisters.OPS.size())
	value = clampi(value, 0, ScriptRegisters.MAX_VALUE)
