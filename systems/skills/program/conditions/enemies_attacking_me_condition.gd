class_name EnemiesAttackingMeCondition
extends ProgramCondition
## WHEN at least `min_count` enemies are attacking the caster: targeting it and in reach to
## swing (not just nearby, like enemies_nearby).

@export var min_count: int = 2


func type_id() -> String:
	return "enemies_attacking_me"


func changes_during_cast() -> bool:
	return true


func defensive() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	var count := 0
	for t in SkillTargets.candidates(cast.caster):
		var ai := t.get("ai") as AIComponent
		if ai == null or ai.target != cast.caster or ai.state != AIComponent.State.ATTACK:
			continue
		if ProgramCondition.health_fraction(t) <= 0.0:
			continue
		count += 1
		if count >= min_count:
			return true
	return false


## Bigger crowds on you are rarer, so cheaper.
func cost_multiplier() -> float:
	return clampf(0.85 - 0.12 * min_count, 0.35, 0.8)


func describe() -> String:
	return "WHEN %d+ enemies attacking me" % min_count


func param_names() -> PackedStringArray:
	return PackedStringArray(["min_count"])


func param_label(_param: String) -> String:
	return "COUNT"


func palette_name() -> String:
	return "ENEMIES ATTACKING ME"


func clamp_params() -> void:
	min_count = clampi(min_count, 1, 6)
