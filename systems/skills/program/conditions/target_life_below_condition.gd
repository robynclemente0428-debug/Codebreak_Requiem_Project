class_name TargetLifeBelowCondition
extends ProgramCondition
## WHEN the target being hit is below `fraction` of its maximum life. Checked per hit,
## so it can only change damage (an "execute" rule).

@export var fraction: float = 0.3


func type_id() -> String:
	return "target_life_below"


func scope() -> Scope:
	return Scope.HIT


func is_true(_cast: SkillCast, target: Node) -> bool:
	return target != null and ProgramCondition.health_fraction(target) < fraction


func cost_multiplier() -> float:
	return clampf(0.2 + fraction * 0.6, 0.3, 0.8)


func describe() -> String:
	return "WHEN target life < %d%%" % roundi(fraction * 100.0)


func param_names() -> PackedStringArray:
	return PackedStringArray(["fraction"])


func param_step(_param: String) -> float:
	return 0.05


func param_label(_param: String) -> String:
	return "LIFE %"


func palette_name() -> String:
	return "TARGET LIFE BELOW"


func clamp_params() -> void:
	fraction = clampf(fraction, 0.1, 0.9)
