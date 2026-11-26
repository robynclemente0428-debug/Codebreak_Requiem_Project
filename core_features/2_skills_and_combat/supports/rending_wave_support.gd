class_name RendingWaveSupport
extends SupportBehavior

func before_release(cast: SkillCast) -> void:
	if cast.depth > 0:
		return
	var reach := cast.flag("wave_range")
	if reach <= cast.melee_range() * 0.5:
		return
	_throw(cast, reach)


func _throw(cast: SkillCast, reach: float) -> void:
	var caster := cast.caster
	await caster.get_tree().create_timer(maxf(cast.flag("wave_delay"), 0.0), false).timeout
	if not cast.is_valid() or SkillBehavior.is_dead(caster):
		return
	var sub := cast.spawn_child()
	CrescentWave.launch(sub, cast.melee_range() * 0.5, reach, cast.flag("wave_width"),
			cast.flag("wave_speed"), cast.flag("wave_damage"), cast.already_hit)
