class_name PointerSupport
extends SupportBehavior
## Blast only. A pointer to the next node, like a linked list:
##   Every explosion HOPS to the nearest enemy it hasn't hit yet near it, and explodes again
##   there for part of the damage, `pointer_hops` times. Works on every cast, no script needed.
##   Loop repeats (which fire from you) also aim at the next enemy instead of straight ahead, so
##   a loop works through a pack. They look around where the last shot exploded: first for an
##   enemy the loop hasn't hit yet that they may turn to, then any enemy it hasn't hit, then one
##   still standing (so `while target_alive()` keeps on one target).
## Flags (SkillGemRegistry._support_flag_modifiers, scriptable through the knobs):
##   pointer_range       metres around an explosion it looks for the next enemy (hops and repeats)
##   pointer_turn        the most degrees a loop repeat may turn away from where you are facing
##   pointer_hops        how many times each explosion hops on
##   pointer_hop_damage  fraction of a normal hit each hop deals

const HOP_DELAY := 0.12          # seconds between links, so the chain reads as travelling
const HOP_RADIUS := 0.7          # a hop's explosion, as a fraction of the Blast's radius
const LINK_COLOR := Color(0.2, 0.9, 1.0)
const HOP_ACCENT := Color(0.55, 0.85, 1.0)


func on_area_impact(cast: SkillCast, center: Vector3, _direction: Vector3) -> void:
	var hops := int(round(cast.flag("pointer_hops")))
	if hops <= 0:
		return
	_hop(cast, cast.spawn_child(), center, hops)


## One link: find the next enemy near `from`, explode there, then the next link a moment later.
## `sub` is shared by every link of this chain, so its already_hit is what the chain has hit.
func _hop(cast: SkillCast, sub: SkillCast, from: Vector3, left: int) -> void:
	if left <= 0 or not cast.is_valid():
		return
	var target: Node3D = null
	for t in SkillDeliveries.hits_in_circle(sub, from, maxf(cast.flag("pointer_range"), 0.5), 32, sub.already_hit):
		if not t.is_in_group(&"breakables"):        # chain through enemies, not barrels
			target = t
			break
	if target == null:
		return
	await cast.caster.get_tree().create_timer(HOP_DELAY, false).timeout
	if not cast.is_valid() or not is_instance_valid(target):
		return
	var at := target.global_position
	_link_fx(cast.effect_parent(), from, at)
	var radius := cast.flag("radius") * HOP_RADIUS
	ImpactEffect.spawn(cast.effect_parent(), at, radius, LINK_COLOR, HOP_ACCENT)
	for t in SkillDeliveries.hits_in_circle(sub, at, radius, int(cast.flag("max_targets")), sub.already_hit):
		sub.hit(t, cast.flag("pointer_hop_damage"))
	if not (target in sub.already_hit):
		sub.already_hit.append(target)               # never hop back to it, even if it was missed
	_hop(cast, sub, at, left - 1)


## A bright line between two links that fades out.
static func _link_fx(parent: Node, a: Vector3, b: Vector3) -> void:
	var lift := Vector3.UP * 0.6
	var seg := (b + lift) - (a + lift)
	var length := seg.length()
	if length < 0.05:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = LINK_COLOR
	mat.emission_enabled = true
	mat.emission = LINK_COLOR
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(line)
	line.global_position = a + lift + seg * 0.5
	line.look_at(b + lift, Vector3.UP if absf(seg.normalized().y) < 0.99 else Vector3.RIGHT)
	var t := line.create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	t.tween_callback(line.queue_free)

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
