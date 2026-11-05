class_name AftershockSupport
extends SupportBehavior
## Slam only. The ground keeps shaking: after the slam lands, echo slams hit the same spot again
## in wider and wider rings for part of the damage. "boom ... BOOM".
## Flags (SkillGemRegistry._support_flag_modifiers, scriptable through the knobs):
##   aftershock_count      echoes after the main slam (whole number)
##   aftershock_delay      seconds between echoes
##   aftershock_damage     fraction of a normal hit each echo deals (0.4 = 40%)
##   aftershock_growth     each echo's radius grows by this fraction of the slam's (0.35 = +35%)
##
## Echoes are child casts (depth 1), so they can hit the same enemies again, but on-kill
## supports that only react to the main hit (Explode on Kill) ignore them.

func before_release(cast: SkillCast) -> void:
	if cast.depth > 0:
		return
	var count := int(round(cast.flag("aftershock_count")))
	if count <= 0:
		return
	# Same centre the slam uses, fixed now: the echoes stay put even if the caster moves on
	var center := cast.caster.global_position + cast.forward() * cast.flag("center_offset")
	_echoes(cast, center, count)


func _echoes(cast: SkillCast, center: Vector3, count: int) -> void:
	var tree := cast.caster.get_tree()
	var radius := cast.flag("radius")
	for i in count:
		await tree.create_timer(maxf(cast.flag("aftershock_delay"), 0.1), false).timeout
		if not cast.is_valid() or SkillBehavior.is_dead(cast.caster):
			return                                    # the caster died or left the area
		var sub := cast.spawn_child()
		sub.already_hit = []                          # an echo may hit everyone again
		var r := radius * (1.0 + cast.flag("aftershock_growth") * float(i + 1))
		ImpactEffect.spawn(cast.effect_parent(), center, r, Color(1.0, 0.65, 0.3))
		SoundManager.play_skill("slam", cast.caster, 0.0)      # another thud
		for target in SkillDeliveries.hits_in_circle(sub, center, r):
			sub.hit(target, cast.flag("aftershock_damage"))
