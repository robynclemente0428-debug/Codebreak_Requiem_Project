class_name ExplodeOnKillSupport
extends SupportBehavior

func on_kill(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	if cast.depth > 0:
		return
	var radius := hit.flag("explode_radius")
	if radius <= 0.0:
		return
	var sub := cast.spawn_child()
	ImpactEffect.spawn(cast.effect_parent(), hit.position, radius,
			Color(1.0, 0.35, 0.15), Color(1.0, 0.7, 0.3))
	Coop.show_impact(cast.caster, hit.position, radius, Color(1.0, 0.35, 0.15), Color(1.0, 0.7, 0.3))
	for other in SkillDeliveries.hits_in_circle(sub, hit.position, radius, SkillDeliveries.NO_CAP, [target]):
		sub.hit(other, hit.flag("explode_damage"))
