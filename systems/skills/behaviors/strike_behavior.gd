class_name StrikeBehavior
extends SkillBehavior
## Melee swing: hits enemies inside a cone in front of the caster.
## Flags (set per gem in SkillGemRegistry, changeable by supports through flag_modifiers):
##   arc_angle      width of the cone in degrees
##   range_bonus    extra reach on top of the caster's ATTACK_RANGE stat
##   combo_grace    extra seconds after the attack before the combo restarts from the first clip

func release(cast: SkillCast) -> void:
	var caster := cast.caster
	var forward := caster.global_transform.basis.z      # not flattened, like the original swing
	var reach := cast.melee_range()
	var arc := cast.flag("arc_angle")

	SlashEffect.spawn(caster, reach, arc, SkillStyle.for_caster(caster),
			cast.skill.get_combo_index() % 2 == 0)

	for target in SkillDeliveries.hits_in_arc(cast, caster.global_position, forward, arc, reach):   # everyone in the cone
		cast.hit(target)


## Kept for old tests. The maths now lives in SkillDeliveries.resolve_arc().
static func resolve_hits(caster_pos: Vector3, forward: Vector3, arc_angle_degrees: float,
		attack_range: float, max_targets: int, candidate_positions: Array) -> Array[int]:
	return SkillDeliveries.resolve_arc(caster_pos, forward, arc_angle_degrees, attack_range,
			max_targets, candidate_positions)
