class_name VarCondition
extends ProgramCondition
## WHEN about the Registry, the set of enemies (see ScriptRegisters). Two forms:
##   when target in registry:        the enemy being hit is in the set (or: not in). Checked per
##                                    hit, so the rule's buffs only land on those hits.
##   when registry.size >= 3:        how many enemies are in the set, checked per cast.
## Every part is a token the player clicks, like the Act II patch puzzles: clicking the first token
## switches between the two forms. (The type id stays "var_compare" so saved scripts still load.)
##
## Discount: registry.size and "not in" get COST_MULT. "target in registry" depends on whether the
## script ever spends a mark: with a registry.remove(target) anywhere in it, each mark pays out
## once (COST_SPENT, the bigger discount); without one, a mark is permanent and the rule is close
## to always on (COST_KEPT). SkillProgram.validate sets `spent` before anything is priced.

const COST_MULT := 0.75
const COST_SPENT := 0.6
const COST_KEPT := 0.9

## Set by SkillProgram.validate: does the script have a registry.remove? Not saved.
var spent := false

@export var key: int = 0                       # index in ScriptRegisters.READ_KEYS: target / size
@export var op: int = 0                        # MEMBER_OPS for target, OPS for size
@export var value: int = 3                     # size comparisons only


## make("target", "in") / make("target", "not in") / make("size", ">=", 3)
static func make(key_name: String, op_text: String, n: int = 3) -> VarCondition:
	var c := VarCondition.new()
	c.key = maxi(ScriptRegisters.READ_KEYS.find(key_name), 0)
	c.op = maxi(c._ops().find(op_text), 0)
	c.value = n
	return c


## "target" (membership) or "size".
func register_name() -> String:
	return ScriptRegisters.READ_KEYS[posmod(key, ScriptRegisters.READ_KEYS.size())]


func is_membership() -> bool:
	return register_name() == "target"


func _ops() -> Array:
	return ScriptRegisters.MEMBER_OPS if is_membership() else ScriptRegisters.OPS


func op_text() -> String:
	var ops := _ops()
	return ops[posmod(op, ops.size())]


func type_id() -> String:
	return "var_compare"


## Membership is about the enemy being hit, so it is checked per hit.
func scope() -> Scope:
	return Scope.HIT if is_membership() else Scope.CAST


## Two different checks are different branches, so The Mimic's DIFF can tell them apart.
func fired_id() -> String:
	return "reg_%s" % op_text() if is_membership() else "size%s%d" % [op_text(), value]


func allows_repeats() -> bool:
	return true


func changes_during_cast() -> bool:
	return true


func modular() -> bool:
	return true


func is_true(cast: SkillCast, target: Node) -> bool:
	var support := ProgramSupport.of(cast.skill) if cast != null else null
	if support == null:
		return false
	if is_membership():
		return ScriptRegisters.has(support.registers, target) == (op_text() == "in")
	return ScriptRegisters.compare(ScriptRegisters.size_of(support.registers), op_text(), value)


## "always" or "never" when no size the set can have changes the answer, otherwise "".
## Membership always depends on the enemy, so it is never constant.
func constant_answer() -> String:
	if is_membership():
		return ""
	var first := ScriptRegisters.compare(0, op_text(), value)
	for v in range(1, ScriptRegisters.MAX_VALUE + 1):
		if ScriptRegisters.compare(v, op_text(), value) != first:
			return ""
	return "always" if first else "never"


func cost_multiplier() -> float:
	if is_membership() and op_text() == "in":
		return COST_SPENT if spent else COST_KEPT
	return COST_MULT


func describe() -> String:
	if is_membership():
		return "WHEN target %s registry" % op_text()
	return "WHEN registry.size %s %d" % [op_text(), value]


func param_names() -> PackedStringArray:
	return PackedStringArray(["key", "op"]) if is_membership() else PackedStringArray(["key", "op", "value"])


func param_text(param: String) -> String:
	match param:
		"key":
			return "target" if is_membership() else "registry.size"
		"op":
			return "%s registry" % op_text() if is_membership() else op_text()
	return str(value)


func param_label(param: String) -> String:
	return {"key": "READ", "op": "OPERATOR", "value": "SIZE"}.get(param, param.to_upper())


func palette_name() -> String:
	return "REGISTRY"


func nudge_param(param: String, clicks: int) -> void:
	if param == "key":                         # switching form: start from its usual operator
		key = posmod(key + clicks, ScriptRegisters.READ_KEYS.size())
		op = 0 if is_membership() else ScriptRegisters.OPS.find(">=")
		clamp_params()
		return
	super.nudge_param(param, clicks)


func clamp_params() -> void:
	key = posmod(key, ScriptRegisters.READ_KEYS.size())
	op = posmod(op, _ops().size())
	value = clampi(value, 0, ScriptRegisters.MAX_VALUE)


## All three parts, whichever form it is, so a switch back keeps the size it had.
func to_dict() -> Dictionary:
	return {"type": type_id(), "key": key, "op": op, "value": value}


func load_params(d: Dictionary) -> void:
	key = int(d.get("key", 0))                 # a counter read from before the Registry: membership
	op = int(d.get("op", 0)) if d.has("key") else 0
	value = int(d.get("value", 3))
	clamp_params()
