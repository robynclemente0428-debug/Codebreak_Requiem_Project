class_name StackOverflowCondition
extends ProgramCondition
## WHEN stack_overflow: true for the repeat that reaches the loop cap (5, or 7 with For Loop).
## Only a loop that runs all the way to the cap gets there, so it is cheap.

func type_id() -> String:
	return "stack_overflow"


func per_repeat() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	var i := int(cast.extra.get("loop_index", 0))
	return i > 0 and i >= int(cast.extra.get("loop_cap", ProgramLoop.BASE_CAP))


func cost_multiplier() -> float:
	return 0.4


func describe() -> String:
	return "WHEN stack overflow"


func palette_name() -> String:
	return "STACK OVERFLOW"


## Only true on a loop repeat (see ProgramCondition.needs_loop).
func needs_loop() -> bool:
	return true
