class_name PointerSupport
extends SupportBehavior
## Blast only. Loop repeats (which fire from you) aim at the next enemy instead of straight
## ahead, so a loop works through a pack like a chain. It looks around where the last shot
## exploded: first for an enemy this loop hasn't hit yet that it may turn to, then any enemy it
## hasn't hit, then one that is still standing (so `while target_alive()` keeps on one target).
## Flags (SkillGemRegistry._support_flag_modifiers, scriptable through the knobs):
##   pointer_range   metres around the last explosion it looks for an enemy
##   pointer_turn    the most degrees a repeat may turn away from where you are facing
## Only changes loop repeats: without a for / while loop in the script it does nothing.

func aim_repeat(cast: SkillCast, aim: Dictionary) -> void:
	var origin: Vector3 = aim["from"]
	var seek_from: Vector3 = aim["seek_from"]
	var facing: Vector3 = aim["direction"]
	var reach := maxf(cast.flag("pointer_range"), 0.5)
	var max_turn := deg_to_rad(clampf(cast.flag("pointer_turn"), 0.0, 180.0))
	var hit_before: Array = cast.extra.get("loop_hit_so_far", [])
	# Closest to the last explosion first.
	var found := SkillDeliveries.hits_in_circle(cast, seek_from, reach, 32)
	var target: Node3D = null
	for pass_no in 4:
		for t in found:
			var fresh: bool = not (t in hit_before)
			var reachable: bool = facing.angle_to(_flat(t.global_position - origin, facing)) <= max_turn + 0.001
			if (pass_no == 0 and fresh and reachable) or (pass_no == 1 and fresh) \
					or (pass_no == 2 and reachable) or pass_no == 3:
				target = t
				break
		if target != null:
			break
	if target == null:
		return
	var to := target.global_position - origin
	to.y = 0.0
	var want := _flat(to, facing)
	var angle := facing.angle_to(want)
	if angle <= max_turn + 0.001:
		aim["direction"] = want
		aim["range"] = maxf(aim["range"], to.length() + 1.5)
	else:
		# Too sharp a turn: bend as far as it may
		var side := signf(facing.cross(want).y)
		aim["direction"] = facing.rotated(Vector3.UP, max_turn * (side if side != 0.0 else 1.0))


static func _flat(v: Vector3, fallback: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.05 else fallback
