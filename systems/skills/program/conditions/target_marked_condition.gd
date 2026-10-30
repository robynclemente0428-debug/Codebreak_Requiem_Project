class_name TargetMarkedCondition
extends ProgramCondition
## WHEN target_marked. Only with the Breakpoint support (Shoot).
##   in a loop:  the last shot (or repeat) hit an enemy whose breakpoint is still up
##   otherwise:  the enemy this skill hit last still has its breakpoint
## Made for loops:  while target_marked(): cast(max=3)  fires until the breakpoint pops.

func type_id() -> String:
	return "target_marked"


func required_support() -> String:
	return "breakpoint_support"


func per_repeat() -> bool:
	return true


func changes_during_cast() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	var runner := cast.extra.get(ProgramSupport.LOOP_KEY) as ProgramLoopRunner
	if runner != null:                           # a loop deciding whether to go on
		for t in runner.last_targets:
			if BreakpointSupport.is_marked(cast.caster, t):
				return true
		return false
	return BreakpointSupport.is_marked(cast.caster, BreakpointSupport.last_target(cast.caster))


func cost_multiplier() -> float:
	return 0.7


func describe() -> String:
	return "WHEN target marked"


func palette_name() -> String:
	return "TARGET MARKED"
