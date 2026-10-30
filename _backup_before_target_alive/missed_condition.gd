class_name MissedCondition
extends ProgramCondition
## except missed:  only with the Try / Except support. True for a repeat that is being tried
## again because the one before it hit nothing. The rule's effects only change that retry.

func type_id() -> String:
	return "missed"


func keyword() -> String:
	return "except"


func required_support() -> String:
	return "try_except_support"


func per_repeat() -> bool:
	return true


func changes_during_cast() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	return bool(cast.extra.get("loop_retry", false))


func cost_multiplier() -> float:
	return 0.5


func describe() -> String:
	return "EXCEPT missed"


func palette_name() -> String:
	return "MISSED"
