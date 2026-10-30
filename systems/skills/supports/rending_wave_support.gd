class_name RendingWaveSupport
extends SupportBehavior
## Strike only. Each swing throws a crescent blade of force that flies forward like a
## projectile, cutting every enemy it passes through for part of the damage. Enemies the
## swing itself already hit are skipped, so it only cuts the ones further out.
## Flags (SkillGemRegistry._support_flag_modifiers, scriptable through the knobs):
##   wave_range    how far the crescent flies, in metres from the caster
##   wave_width    tip-to-tip width of the crescent in metres
##   wave_speed    metres per second
##   wave_damage   fraction of a normal hit it deals (0.6 = 60%)
##   wave_delay    seconds after the swing before it's thrown
##
## The crescent's hits are a child cast (depth 1): they can trigger on-hit effects, but not
## another wave. See CrescentWave for the projectile itself.

func before_release(cast: SkillCast) -> void:
	if cast.depth > 0:
		return
	var reach := cast.flag("wave_range")
	if reach <= cast.melee_range() * 0.5:
		return
	_throw(cast, reach)


## Waits a moment so release() has run: cast.already_hit then holds what the swing hit.
func _throw(cast: SkillCast, reach: float) -> void:
	var caster := cast.caster
	await caster.get_tree().create_timer(maxf(cast.flag("wave_delay"), 0.0), false).timeout
	if not cast.is_valid() or SkillBehavior.is_dead(caster):
		return
	var sub := cast.spawn_child()
	CrescentWave.launch(sub, cast.melee_range() * 0.5, reach, cast.flag("wave_width"),
			cast.flag("wave_speed"), cast.flag("wave_damage"), cast.already_hit)
