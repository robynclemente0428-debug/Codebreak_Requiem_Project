class_name HitNothingCondition
extends ProgramCondition
## if hit_nothing: the last cast or repeat to land hit no enemy. For loops (Architect):
##     if hit_nothing:     break           stop wasting mana on empty repeats
## Judged after each cast or repeat lands (ProgramLoopRunner.landed_hits), so it's never true
## for the original cast itself. Not Try / Except's  except missed  (MissedCondition), which
## needs that gem and retries the repeat instead.

func type_id() -> String:
	return "hit_nothing"


func per_repeat() -> bool:
	return true


func changes_during_cast() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	var runner := cast.extra.get(ProgramSupport.LOOP_KEY) as ProgramLoopRunner
	return runner != null and runner.landed and runner.landed_hits == 0


func cost_multiplier() -> float:
	return 0.7


func describe() -> String:
	return "WHEN the last cast or repeat hit nothing"


func palette_name() -> String:
	return "HIT NOTHING"


## Only true on a loop repeat (see ProgramCondition.needs_loop).
func needs_loop() -> bool:
	return true
