class_name AftershockSupport
extends SupportBehavior

func before_release(cast: SkillCast) -> void:
	if cast.depth > 0:
		return
	var count := int(round(cast.flag("aftershock_count")))
	if count <= 0:
		return
	var center := cast.caster.global_position + cast.forward() * cast.flag("center_offset")
	_echoes(cast, center, count)


func _echoes(cast: SkillCast, center: Vector3, count: int) -> void:
	var tree := cast.caster.get_tree()
	var radius := cast.flag("radius")
	for i in count:
		await tree.create_timer(maxf(cast.flag("aftershock_delay"), 0.1), false).timeout
		if not cast.is_valid() or SkillBehavior.is_dead(cast.caster):
			return
		var sub := cast.spawn_child()
		sub.already_hit = []
		var r := radius * (1.0 + cast.flag("aftershock_growth") * float(i + 1))
		ImpactEffect.spawn(cast.effect_parent(), center, r, Color(1.0, 0.65, 0.3))
		SoundManager.play_skill("slam", cast.caster, 0.0)
		for target in SkillDeliveries.hits_in_circle(sub, center, r):
			sub.hit(target, cast.flag("aftershock_damage"))
