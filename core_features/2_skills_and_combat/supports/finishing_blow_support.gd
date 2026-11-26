class_name FinishingBlowSupport
extends SupportBehavior


func before_release(cast: SkillCast) -> void:
	if cast.depth > 0 or cast.extra.get("hologram", false):
		return
	var swing := cast.skill.count_swing(cast)
	var every := maxi(int(round(cast.flag("finisher_every"))), 2)
	if swing % every != 0:
		return
	cast.extra["finisher"] = true
	cast.damage_mult *= 1.0 + cast.flag("finisher_damage")
	cast.flag_bonus["arc_angle"] = cast.flag_bonus.get("arc_angle", 0.0) + cast.flag("finisher_arc")
	cast.flag_bonus["range_bonus"] = cast.flag_bonus.get("range_bonus", 0.0) + cast.flag("finisher_reach")
	var at := cast.caster.global_position + cast.forward() * cast.melee_range() * 0.6
	ImpactEffect.spawn(cast.effect_parent(), at, cast.melee_range() * 0.55,
			Color(1.0, 0.85, 0.35), Color(1.0, 0.55, 0.2))
	SoundManager.play_skill("slam", cast.caster, 0.0)
