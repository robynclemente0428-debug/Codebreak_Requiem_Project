class_name TargetAliveCondition
extends ProgramCondition
## WHEN target_alive: the last cast (or repeat) hit an enemy that is still standing.
## Made for loops:  while target_alive(): cast(max=3)  keeps hitting until it dies.
## Never true on the original cast (nothing has been hit yet), only on repeats.

func type_id() -> String:
	return "target_alive"


func per_repeat() -> bool:
	return true


func changes_during_cast() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	var runner := cast.extra.get(ProgramSupport.LOOP_KEY) as ProgramLoopRunner
	return runner != null and runner.any_target_alive()


func cost_multiplier() -> float:
	return 0.75


func describe() -> String:
	return "WHEN target alive"


func palette_name() -> String:
	return "TARGET ALIVE"


## Only true on a loop repeat (see ProgramCondition.needs_loop).
func needs_loop() -> bool:
	return true
