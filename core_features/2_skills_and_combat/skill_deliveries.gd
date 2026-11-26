class_name SkillDeliveries
extends RefCounted


static func forward(caster: Node3D) -> Vector3:
	var f := caster.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


static func spawn_point(caster: Node3D, height: float, forward_offset: float) -> Vector3:
	return caster.global_position + Vector3.UP * height + forward(caster) * forward_offset


static func fan_directions(fwd: Vector3, count: int, step_degrees: float) -> Array[Vector3]:
	var dirs: Array[Vector3] = []
	count = maxi(count, 1)
	for i in count:
		var offset_deg := (float(i) - (count - 1) * 0.5) * step_degrees
		dirs.append(fwd.rotated(Vector3.UP, deg_to_rad(offset_deg)))
	return dirs


const NO_CAP := 0


static func hits_in_circle(cast: SkillCast, center: Vector3, radius: float, max_targets := NO_CAP,
		exclude: Array = []) -> Array:
	var targets := _candidates(cast, exclude)
	var indices := resolve_circle(center, radius, max_targets, _positions(targets))
	return _pick(targets, indices)


static func hits_in_arc(cast: SkillCast, origin: Vector3, fwd: Vector3, arc_degrees: float,
		reach: float, max_targets := NO_CAP, exclude: Array = []) -> Array:
	var targets := _candidates(cast, exclude)
	var indices := resolve_arc(origin, fwd, arc_degrees, reach, max_targets, _positions(targets))
	return _pick(targets, indices)


static func nearest_target(cast: SkillCast, point: Vector3, max_distance: float,
		exclude: Array = []) -> Node3D:
	var found := hits_in_circle(cast, point, max_distance, 1, exclude)
	return found[0] if not found.is_empty() else null


static func resolve_circle(center: Vector3, radius: float, max_targets: int,
		candidate_positions: Array) -> Array[int]:
	var found: Array = []
	for i in candidate_positions.size():
		var pos: Vector3 = candidate_positions[i]
		var dist := Vector2(pos.x - center.x, pos.z - center.z).length()
		if dist <= radius:
			found.append([dist, i])
	return _closest(found, max_targets)


static func resolve_arc(origin: Vector3, fwd: Vector3, arc_degrees: float, reach: float,
		max_targets: int, candidate_positions: Array) -> Array[int]:
	var found: Array = []
	for i in candidate_positions.size():
		var pos: Vector3 = candidate_positions[i]
		var to_target: Vector3 = pos - origin
		var dist := to_target.length()
		if dist > reach or dist < 0.001:
			continue
		var angle_deg := rad_to_deg(fwd.angle_to(to_target.normalized()))
		if angle_deg <= arc_degrees / 2.0:
			found.append([dist, i])
	return _closest(found, max_targets)


static func _candidates(cast: SkillCast, exclude: Array) -> Array:
	var result: Array = []
	for t in SkillTargets.hittable(cast.caster):
		if is_instance_valid(t) and t is Node3D and not (t in exclude):
			result.append(t)
	return result


static func _positions(targets: Array) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for t in targets:
		positions.append((t as Node3D).global_position)
	return positions


static func _pick(targets: Array, indices: Array[int]) -> Array:
	var picked: Array = []
	for i in indices:
		picked.append(targets[i])
	return picked


static func _closest(found: Array, max_targets: int) -> Array[int]:
	found.sort_custom(func(a, b): return a[0] < b[0])
	var hits: Array[int] = []
	for entry in found:
		if max_targets > 0 and hits.size() >= max_targets:
			break
		hits.append(entry[1])
	return hits
