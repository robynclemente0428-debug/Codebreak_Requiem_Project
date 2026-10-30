class_name FinishingBlowSupport
extends SupportBehavior
## Strike only. Every Nth swing of a combo is a finishing blow: it hits much harder, sweeps a
## wider arc and reaches further. Keep swinging to build up to it; pausing long enough to
## break the combo starts the count again.
## Flags (SkillGemRegistry._support_flag_modifiers, scriptable through the knobs):
##   finisher_every    which swing is the finisher (3 = the 3rd, 6th, 9th... swing of a combo)
##   finisher_damage   extra damage on the finisher (0.8 = 80% more)
##   finisher_arc      extra degrees of arc on the finisher
##   finisher_reach    extra metres of reach on the finisher
##
## The finisher only changes this one cast (flag_bonus / damage_mult), so nothing leaks into
## the next swing. cast.extra["finisher"] = true lets other supports react to it.
##
## The swing count is the skill's shared combo count (SkillInstance.count_swing), so a script's
## every_nth_cast counts the very same swings and always lines up with the finisher.


func before_release(cast: SkillCast) -> void:
	if cast.depth > 0 or cast.extra.get("hologram", false):
		return                                   # a Multicast copy already carries the finisher
	# A pause longer than a swing plus the grace restarts the combo (see SkillInstance.count_swing)
	var swing := cast.skill.count_swing(cast)
	var every := maxi(int(round(cast.flag("finisher_every"))), 2)
	if swing % every != 0:
		return
	cast.extra["finisher"] = true
	cast.damage_mult *= 1.0 + cast.flag("finisher_damage")
	cast.flag_bonus["arc_angle"] = cast.flag_bonus.get("arc_angle", 0.0) + cast.flag("finisher_arc")
	cast.flag_bonus["range_bonus"] = cast.flag_bonus.get("range_bonus", 0.0) + cast.flag("finisher_reach")
	# A heavier thud and a burst in front, so the finisher reads differently from a normal swing
	var at := cast.caster.global_position + cast.forward() * cast.melee_range() * 0.6
	ImpactEffect.spawn(cast.effect_parent(), at, cast.melee_range() * 0.55,
			Color(1.0, 0.85, 0.35), Color(1.0, 0.55, 0.2))
	SoundManager.play_skill("slam", cast.caster, 0.0)
