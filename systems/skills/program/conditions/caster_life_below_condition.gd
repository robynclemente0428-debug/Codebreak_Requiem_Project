class_name CasterLifeBelowCondition
extends ProgramCondition
## WHEN the caster's life is below `fraction` of its maximum (0.5 = below half).

@export var fraction: float = 0.5

const NullLawsRef := preload("res://systems/world/null_laws.gd")   # Act IV's Null Laws


func type_id() -> String:
	return "caster_life_below"


func changes_during_cast() -> bool:
	return true


func defensive() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	if NullLawsRef.on("life_inverted", cast.caster):          # LIFE READS INVERTED
		return ProgramCondition.health_fraction(cast.caster) > 1.0 - fraction
	return ProgramCondition.health_fraction(cast.caster) < fraction


## Lower thresholds are rarer and riskier, so cheaper.
func cost_multiplier() -> float:
	return clampf(0.2 + fraction * 0.6, 0.3, 0.8)


func describe() -> String:
	return "WHEN my life < %d%%" % roundi(fraction * 100.0)


func param_names() -> PackedStringArray:
	return PackedStringArray(["fraction"])


func param_step(_param: String) -> float:
	return 0.05


func param_label(_param: String) -> String:
	return "LIFE %"


func palette_name() -> String:
	return "MY LIFE BELOW"


func clamp_params() -> void:
	fraction = clampf(fraction, 0.1, 0.9)
