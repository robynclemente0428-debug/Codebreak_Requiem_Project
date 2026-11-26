class_name StrikeBehavior
extends SkillBehavior

func release(cast: SkillCast) -> void:
	var caster := cast.caster
	var forward := caster.global_transform.basis.z
	var reach := cast.melee_range()
	var arc := cast.flag("arc_angle")

	SlashEffect.spawn(caster, reach, arc, SkillStyle.for_caster(caster),
			cast.skill.get_combo_index() % 2 == 0)

	for target in SkillDeliveries.hits_in_arc(cast, caster.global_position, forward, arc, reach):
		cast.hit(target)


static func resolve_hits(caster_pos: Vector3, forward: Vector3, arc_angle_degrees: float,
		attack_range: float, max_targets: int, candidate_positions: Array) -> Array[int]:
	return SkillDeliveries.resolve_arc(caster_pos, forward, arc_angle_degrees, attack_range,
			max_targets, candidate_positions)
