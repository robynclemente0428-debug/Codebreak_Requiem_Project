class_name OverclockedCondition
extends ProgramCondition
## WHEN overclocked >= N. Only with the Overclock support (Shoot): true while this shot fires
## with at least N stacks, e.g.  when overclocked(5): pierce += 1

@export var n: int = 3


func type_id() -> String:
	return "overclocked"


func required_support() -> String:
	return "overclock_support"


func is_true(cast: SkillCast, _target: Node) -> bool:
	if cast.extra.has(OverclockSupport.STACKS_KEY):
		return int(cast.extra[OverclockSupport.STACKS_KEY]) >= n
	var oc := OverclockSupport.on_skill(cast.skill)
	return oc != null and oc.stacks_for(cast) >= n


## More stacks needed = only in long bursts = cheaper effects.
func cost_multiplier() -> float:
	return clampf(0.95 - 0.1 * n, 0.45, 0.85)


func describe() -> String:
	return "WHEN overclocked >= %d" % n


func param_names() -> PackedStringArray:
	return PackedStringArray(["n"])


func param_label(_param: String) -> String:
	return "STACKS"


func palette_name() -> String:
	return "OVERCLOCKED"


func clamp_params() -> void:
	n = clampi(n, 1, 8)
