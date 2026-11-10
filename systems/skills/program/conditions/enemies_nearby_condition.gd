class_name EnemiesNearbyCondition
extends ProgramCondition
## WHEN at least `min_count` enemies are within `radius` metres of the caster.

@export var min_count: int = 3
@export var radius: float = 4.0


const NullLawsRef := preload("res://systems/world/null_laws.gd")   # Act IV's Null Laws


func type_id() -> String:
	return "enemies_nearby"


func changes_during_cast() -> bool:
	return true


func is_true(cast: SkillCast, _target: Node) -> bool:
	var origin := cast.caster.global_position
	var count := 0
	var far := NullLawsRef.on("near_is_far", cast.caster)     # NEAR MEANS FAR: beyond the radius
	for t in SkillTargets.candidates(cast.caster):
		if not (t is Node3D) or ProgramCondition.health_fraction(t) <= 0.0:
			continue
		var d: Vector3 = (t as Node3D).global_position - origin
		var dist := Vector2(d.x, d.z).length()
		if (dist > radius and dist <= radius * NullLawsRef.FAR_REACH) if far else dist <= radius:
			count += 1
			if count >= min_count:
				return true
	return false


## Bigger crowds are rarer, so cheaper. A wider radius makes it easier, so pricier.
func cost_multiplier() -> float:
	var base := 0.9 - 0.1 * min_count          # 1 enemy 0.8, 3 enemies 0.6, 5 enemies 0.4
	return clampf(base + (radius - 4.0) * 0.05, 0.35, 0.9)


func describe() -> String:
	return "WHEN %d+ enemies within %.1f m" % [min_count, radius]


func param_names() -> PackedStringArray:
	return PackedStringArray(["min_count", "radius"])


func param_step(param: String) -> float:
	return 0.5 if param == "radius" else 1.0


func param_label(param: String) -> String:
	return "RADIUS" if param == "radius" else "COUNT"


func palette_name() -> String:
	return "ENEMIES NEARBY"


func clamp_params() -> void:
	min_count = clampi(min_count, 1, 6)
	radius = clampf(radius, 2.0, 8.0)
