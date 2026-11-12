class_name KilledCondition
extends ProgramCondition
## if killed: the last cast or repeat to land killed something. For loops (Architect):
##     if killed:          damage += 20%   the next repeat hits harder after a kill
##     if killed:          break           stop once something dies
## Judged after each cast or repeat lands (ProgramLoopRunner.landed_kills), so it's never true
## for the original cast itself, only for the repeats after it and for the break check.

func type_id() -> String:
	return "killed"


func per_repeat() -> bool:
	return true


func changes_during_cast() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	var runner := cast.extra.get(ProgramSupport.LOOP_KEY) as ProgramLoopRunner
	return runner != null and runner.landed and runner.landed_kills > 0


func cost_multiplier() -> float:
	return 0.65


func describe() -> String:
	return "WHEN the last cast or repeat killed"


func palette_name() -> String:
	return "KILLED"


## Only true on a loop repeat (see ProgramCondition.needs_loop).
func needs_loop() -> bool:
	return true
