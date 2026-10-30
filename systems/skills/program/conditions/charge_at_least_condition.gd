class_name ChargeAtLeastCondition
extends ProgramCondition
## WHEN charge >= N. Only with the Variable Store support. When the rule fires, N charge is spent.

@export var n: int = 5


func type_id() -> String:
	return "charge_at_least"


func changes_during_cast() -> bool:
	return true


func required_support() -> String:
	return "variable_store_support"


func is_true(cast: SkillCast, _target: Node) -> bool:
	return VariableStoreSupport.read(cast.caster, cast.skill) >= n


func on_fired(cast: SkillCast) -> void:
	VariableStoreSupport.spend(cast.caster, cast.skill, n)


## The more charge it needs, the rarer it fires, so the cheaper its effects.
func cost_multiplier() -> float:
	return clampf(0.9 - 0.055 * n, 0.35, 0.85)


func describe() -> String:
	return "WHEN charge >= %d" % n


func param_names() -> PackedStringArray:
	return PackedStringArray(["n"])


func param_label(_param: String) -> String:
	return "CHARGE"


func palette_name() -> String:
	return "CHARGE AT LEAST"


func clamp_params() -> void:
	n = clampi(n, 1, 20)
