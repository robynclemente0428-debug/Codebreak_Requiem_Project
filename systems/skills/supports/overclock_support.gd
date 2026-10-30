class_name OverclockSupport
extends SupportBehavior
## Shoot only. Keep the trigger down and the rifle speeds up:
##   each shot fired soon after the previous one adds a stack (up to overclock_max)
##   every stack makes the next shots overclock_speed faster (0.08 = 8%)
##   a pause longer than one shot plus overclock_grace drops every stack
## Flags (SkillGemRegistry._support_flag_modifiers, scriptable through the knobs):
##   overclock_speed   attack speed per stack
##   overclock_max     the most stacks
##   overclock_grace   seconds of pause allowed on top of a shot's own time
##
## The shots are counted with the skill's shared combo count (SkillInstance.count_swing), the one
## every_nth_cast uses while this gem is socketed, so "every 3rd shot" and the stacks agree.
## The script block WHEN overclocked >= N (OverclockedCondition) reads this cast's stacks.
## The skill bar shows the stacks on the skill's slot.

const STACKS_KEY := "overclock"

var _stacks := 0
var _last_msec := -100000
var _window := 0.0           # seconds the next shot has to start in to keep the stacks


## SkillInstance asks this for the cooldown and the animation speed of the shot about to start.
func speed_mult(skill: SkillInstance) -> float:
	return 1.0 + maxf(skill.get_flag("overclock_speed"), 0.0) * _peek(skill)


func before_release(cast: SkillCast) -> void:
	stacks_for(cast)


## The stacks this cast fires with (counted once per cast; repeats and holograms copy theirs).
func stacks_for(cast: SkillCast) -> int:
	if cast.extra.has(STACKS_KEY):
		return int(cast.extra[STACKS_KEY])
	if cast.depth > 0 or cast.extra.get("hologram", false):
		return 0
	cast.skill.count_swing(cast)                 # keeps every_nth_cast lined up with the shots
	_stacks = _peek(cast.skill)
	_last_msec = Time.get_ticks_msec()
	var base := maxf(cast.flag("recovery_mult"), 1.0) / maxf(cast.stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 0.1)
	_window = base + maxf(cast.flag("overclock_grace"), 0.0)
	cast.extra[STACKS_KEY] = _stacks
	return _stacks


## Stacks right now, for UI: 0 once the pause was too long.
func current_stacks() -> int:
	return _stacks if _alive() else 0


## What the next shot will fire with: one more stack if it comes in time, else none.
func _peek(skill: SkillInstance) -> int:
	if not _alive():
		return 0
	return mini(_stacks + 1, maxi(int(round(skill.get_flag("overclock_max"))), 0))


func _alive() -> bool:
	return _last_msec > 0 and (Time.get_ticks_msec() - _last_msec) / 1000.0 <= _window


## The Overclock on a skill (null when it isn't socketed).
static func on_skill(skill: SkillInstance) -> OverclockSupport:
	if skill == null:
		return null
	for s in skill.support_behaviors:
		if s is OverclockSupport:
			return s
	return null
