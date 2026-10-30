class_name ForkedCondition
extends ProgramCondition
## WHEN forked. Only with the Fork support (Shoot). True for the bullets a fork split off, so
## its effects only change those:  when forked(): pierce += 1
## (ShootBehavior applies these rules when a bullet forks: ProgramSupport.apply_fork_rules.)

func type_id() -> String:
	return "forked"


func required_support() -> String:
	return "fork_support"


func is_true(cast: SkillCast, _target: Node) -> bool:
	return cast.extra.get("forked", false)


## Forks only carry part of the damage, so their buffs are cheaper.
func cost_multiplier() -> float:
	return 0.6


func describe() -> String:
	return "WHEN forked"


func palette_name() -> String:
	return "FORKED"
