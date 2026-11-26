class_name OverclockSupport
extends SupportBehavior

const STACKS_KEY := "overclock"

var _stacks := 0
var _last_msec := -100000
var _window := 0.0


func speed_mult(skill: SkillInstance) -> float:
	return 1.0 + maxf(skill.get_flag("overclock_speed"), 0.0) * _peek(skill)


func before_release(cast: SkillCast) -> void:
	stacks_for(cast)


func stacks_for(cast: SkillCast) -> int:
	if cast.extra.has(STACKS_KEY):
		return int(cast.extra[STACKS_KEY])
	if cast.depth > 0 or cast.extra.get("hologram", false):
		return 0
	cast.skill.count_swing(cast)
	_stacks = _peek(cast.skill)
	_last_msec = Time.get_ticks_msec()
	var base := maxf(cast.flag("recovery_mult"), 1.0) / maxf(cast.stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 0.1)
	_window = base + maxf(cast.flag("overclock_grace"), 0.0)
	cast.extra[STACKS_KEY] = _stacks
	return _stacks


func current_stacks() -> int:
	return _stacks if _alive() else 0


func _peek(skill: SkillInstance) -> int:
	if not _alive():
		return 0
	return mini(_stacks + 1, maxi(int(round(skill.get_flag("overclock_max"))), 0))


func _alive() -> bool:
	return _last_msec > 0 and (Time.get_ticks_msec() - _last_msec) / 1000.0 <= _window


static func on_skill(skill: SkillInstance) -> OverclockSupport:
	if skill == null:
		return null
	for s in skill.support_behaviors:
		if s is OverclockSupport:
			return s
	return null
