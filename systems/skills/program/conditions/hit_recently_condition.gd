class_name HitRecentlyCondition
extends ProgramCondition
## WHEN the caster took damage in the last `seconds` (a barrier soaking all of it doesn't count).

@export var seconds: float = 2.0


func type_id() -> String:
	return "hit_recently"


func changes_during_cast() -> bool:
	return true


func defensive() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	var hp := cast.caster.get("health") as HealthComponent
	return hp != null and Time.get_ticks_msec() - hp.last_damaged_msec <= int(seconds * 1000.0)


## A short window is true less often, so cheaper.
func cost_multiplier() -> float:
	return clampf(0.4 + seconds * 0.1, 0.45, 0.85)


func describe() -> String:
	return "WHEN hit in the last %.1f s" % seconds


func param_names() -> PackedStringArray:
	return PackedStringArray(["seconds"])


func param_step(_param: String) -> float:
	return 0.5


func param_label(_param: String) -> String:
	return "SECONDS"


func palette_name() -> String:
	return "HIT RECENTLY"


func clamp_params() -> void:
	seconds = clampf(seconds, 0.5, 5.0)
