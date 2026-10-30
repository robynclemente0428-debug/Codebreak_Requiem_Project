class_name LoopIndexCondition
extends ProgramCondition
## WHEN loop == N: 0 is the original cast, 1 the first repeat of a loop, 2 the second...

@export var n: int = 1


func type_id() -> String:
	return "loop_index"


func per_repeat() -> bool:
	return true


func changes_during_cast() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	return int(cast.extra.get("loop_index", 0)) == n


## Every cast has a loop 0, so that's nearly full price; repeats are cheaper.
func cost_multiplier() -> float:
	return 0.9 if n == 0 else 0.6


func describe() -> String:
	return "WHEN loop == %d" % n


func param_names() -> PackedStringArray:
	return PackedStringArray(["n"])


func param_label(_param: String) -> String:
	return "LOOP"


func palette_name() -> String:
	return "LOOP INDEX"


func clamp_params() -> void:
	n = clampi(n, 0, ProgramLoop.BASE_CAP + ForLoopSupport.CAP_BONUS)
