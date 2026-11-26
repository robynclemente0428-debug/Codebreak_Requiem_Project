class_name SlamBehavior
extends SkillBehavior

func release(cast: SkillCast) -> void:
	var radius := cast.flag("radius")
	var center := cast.caster.global_position + cast.forward() * cast.flag("center_offset")
	ImpactEffect.spawn(cast.effect_parent(), center, radius, Color(1.0, 0.8, 0.5))
	for target in SkillDeliveries.hits_in_circle(cast, center, radius):
		cast.hit(target)


static func resolve_hits(center: Vector3, radius: float, max_targets: int,
		candidate_positions: Array) -> Array[int]:
	return SkillDeliveries.resolve_circle(center, radius, max_targets, candidate_positions)
