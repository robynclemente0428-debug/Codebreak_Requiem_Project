class_name TremorChainSupport
extends SupportBehavior

func on_kill(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	var link: int = cast.extra.get("tremor", 0)
	if link >= int(round(hit.flag("tremor_max_chain"))):
		return
	var radius := cast.flag("radius") * hit.flag("tremor_radius")
	if radius <= 0.1:
		return
	_tremor(cast, target, hit.position, radius, link + 1)


func _tremor(cast: SkillCast, dead: Node, at: Vector3, radius: float, link: int) -> void:
	await cast.caster.get_tree().create_timer(maxf(cast.flag("tremor_delay"), 0.0), false).timeout
	if not cast.is_valid() or SkillBehavior.is_dead(cast.caster):
		return
	var sub := cast.spawn_child()
	sub.extra["tremor"] = link
	ImpactEffect.spawn(cast.effect_parent(), at, radius, Color(1.0, 0.45, 0.2), Color(1.0, 0.75, 0.35))
	Coop.show_impact(cast.caster, at, radius, Color(1.0, 0.45, 0.2), Color(1.0, 0.75, 0.35))
	for other in SkillDeliveries.hits_in_circle(sub, at, radius, SkillDeliveries.NO_CAP, [dead]):
		sub.hit(other, cast.flag("tremor_damage"))
