class_name RegistryPositionCondition
extends ProgramCondition
## WHEN about a place in the Registry's order, the Defragmenter rank's sorting (ScriptRegisters):
##   when target is registry[0]:      the enemy being hit is first in the order
##   when target is registry[-1]:     ... last
##   when target in registry[:3]:     ... one of the first three
## The order is the registry's own (oldest first) or the one a registry.sort line set this cast,
## so  registry.sort(key=hp)  then  when target is registry[0]:  is "the weakest one I marked".
## Checked per hit, like  target in registry, so the rule can change damage, leech, barrier,
## guard and support effects on that hit. One token, clicked to cycle ScriptRegisters.POSITIONS.
##
## Discount: one place is rare (COST_ONE), a slice of two or three less so.

const COST_ONE := 0.6
const COST_SLICE := {"[:2]": 0.68, "[:3]": 0.75}

@export var pos: int = 0                       # index in ScriptRegisters.POSITIONS


static func make(position_text: String) -> RegistryPositionCondition:
	var c := RegistryPositionCondition.new()
	c.pos = maxi(ScriptRegisters.POSITIONS.find(position_text), 0)
	return c


## "registry[0]", "registry[:3]".
func pos_text() -> String:
	return "registry" + ScriptRegisters.POSITIONS[posmod(pos, ScriptRegisters.POSITIONS.size())]


func type_id() -> String:
	return "registry_pos"


func scope() -> Scope:
	return Scope.HIT


## Each place is its own branch, so The Mimic's DIFF can tell them apart.
func fired_id() -> String:
	return "reg_pos%d" % posmod(pos, ScriptRegisters.POSITIONS.size())


func allows_repeats() -> bool:
	return true


func changes_during_cast() -> bool:
	return true


func modular() -> bool:
	return true


func is_true(cast: SkillCast, target: Node) -> bool:
	var support := ProgramSupport.of(cast.skill) if cast != null else null
	if support == null or target == null:
		return false
	var order := support.registry_order()
	return ScriptRegisters.at_position(order.find(ScriptRegisters.entry_key(target)), order.size(), pos)


func cost_multiplier() -> float:
	var p: String = ScriptRegisters.POSITIONS[posmod(pos, ScriptRegisters.POSITIONS.size())]
	return float(COST_SLICE.get(p, COST_ONE))


func describe() -> String:
	return "WHEN target %s %s" % ["in" if ScriptRegisters.is_slice(pos) else "is", pos_text()]


func param_names() -> PackedStringArray:
	return PackedStringArray(["pos"])


func param_text(_param: String) -> String:
	return describe().trim_prefix("WHEN ")


func param_label(_param: String) -> String:
	return "POSITION"


func palette_name() -> String:
	return "REGISTRY ORDER"


func clamp_params() -> void:
	pos = posmod(pos, ScriptRegisters.POSITIONS.size())


func to_dict() -> Dictionary:
	return {"type": type_id(), "pos": pos}


func load_params(d: Dictionary) -> void:
	pos = int(d.get("pos", 0))
	clamp_params()
