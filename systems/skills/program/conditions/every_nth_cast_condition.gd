class_name EveryNthCastCondition
extends ProgramCondition
## WHEN this is every Nth use of the skill (3 = the 3rd, 6th, 9th cast...).

@export var n: int = 3


func type_id() -> String:
	return "every_nth_cast"


func is_true(cast: SkillCast, _target: Node) -> bool:
	var number := int(cast.extra.get(ProgramSupport.CAST_NUMBER_KEY, 0))
	return number > 0 and number % n == 0


## Active 1 cast in n, priced a little above that.
func cost_multiplier() -> float:
	return clampf(1.0 / n + 0.1, 0.25, 0.8)


func describe() -> String:
	return "WHEN every %d%s cast" % [n, _ordinal(n)]


func param_names() -> PackedStringArray:
	return PackedStringArray(["n"])


func param_label(_param: String) -> String:
	return "N"


func palette_name() -> String:
	return "EVERY NTH CAST"


func clamp_params() -> void:
	n = clampi(n, 2, 6)


static func _ordinal(v: int) -> String:
	match v:
		2: return "nd"
		3: return "rd"
	return "th"
