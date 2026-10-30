class_name MulticastSupport
extends SupportBehavior
## Any skill. Every cast also summons a hologram of the caster where they stand, which plays the
## same animation and uses the same skill a moment later: same supports, same program rules,
## same per-cast bonuses (a Finishing Blow finisher is copied too), at reduced damage.
## Flags (SkillGemRegistry._support_flag_modifiers, scriptable through the knobs):
##   multicast_effectiveness  damage of the hologram's cast compared to yours (0.6 = 40% less)
##   multicast_offset         metres to the side the hologram appears (0 = right where you are,
##                            facing the same way; above 0 alternates left / right)
##   multicast_linger         seconds the hologram stays visible after its hit
##
## The hologram is a stripped copy of the caster's model drawn with hologram_glitch.gdshader: no
## collision, no health, not in any group, so nothing can target it. It counts as the same
## side as its caster (an enemy's hologram hits players), see SkillTargets.is_enemy().
## Its cast is marked cast.extra["hologram"] = true; supports that only change the numbers
## of a cast (programs, Finishing Blow) skip it, since those numbers are copied from yours.

const SHADER := preload("res://assets/shaders/materials/game_shaders/hologram_glitch.gdshader")
const KEEP_ALIVE := 6.0          # seconds the (hidden) hologram stays so projectiles / echoes can finish

var _side := 1.0


func before_release(cast: SkillCast) -> void:
	if cast.depth > 0 or cast.extra.get("hologram", false):
		return
	_side = -_side
	_summon(cast, _side)


func _summon(cast: SkillCast, side: float) -> void:
	var caster := cast.caster
	var parent := cast.effect_parent()
	if parent == null:
		return
	# Wait one frame: the other supports finish before_release and release() runs first,
	# so the copied per-cast bonuses are complete.
	await caster.get_tree().process_frame
	if not cast.is_valid():
		return

	var holo := Hologram.new()
	holo.source = caster
	if SkillTargets.is_enemy(caster):
		holo.set_meta(&"hologram_of_enemy", true)
	parent.add_child(holo)
	# Same spot and facing as the caster at the moment of the cast (it stays there even if
	# the caster moves on), nudged sideways only if multicast_offset is set
	var right := caster.global_transform.basis.x.normalized()
	holo.global_transform = caster.global_transform
	holo.global_position += right * side * cast.flag("multicast_offset")
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	holo.build_visual(caster, mat)

	# Same clip, same speed and same hit moment as the caster's own swing
	var hit_in := holo.play_like(caster, cast.skill, cast.behavior.recovery_time(cast))
	SoundManager.play_skill(cast.skill.get_current_animation(), holo, hit_in)
	await caster.get_tree().create_timer(maxf(hit_in, 0.12), false).timeout
	if not is_instance_valid(holo):
		return
	if not cast.is_valid():
		holo.queue_free()
		return

	var copy := SkillCast.new(holo, cast.skill, cast.stats, cast.behavior)
	copy.flag_bonus = cast.flag_bonus.duplicate()
	copy.extra = cast.extra.duplicate()
	copy.extra["hologram"] = true
	copy.damage_mult = cast.damage_mult * cast.flag("multicast_effectiveness")
	for s in cast.skill.support_behaviors:
		s.before_release(copy)                    # Aftershock, Rending Wave... from the hologram
	cast.behavior.release(copy)
	holo.vanish(maxf(cast.flag("multicast_linger"), 0.1), KEEP_ALIVE)


## The hologram body. Only a visual: a copy of the caster's model without scripts, collision
## or animation tree, every mesh drawn with the hologram shader.
class Hologram extends Node3D:
	var source: Node3D
	var _mat: ShaderMaterial
	var _anim: AnimationPlayer

	## Skill effects ask the caster for colours; the hologram borrows its owner's.
	func get_effect_style() -> Dictionary:
		return SkillStyle.for_caster(source) if is_instance_valid(source) else SkillStyle.default_style()

	func build_visual(from: Node3D, mat: ShaderMaterial) -> void:
		_mat = mat
		var visual := _visual_root(from)
		if visual == null:
			return
		var copy := visual.duplicate(0) as Node3D              # no scripts, groups or signals
		add_child(copy)
		copy.transform = from.global_transform.affine_inverse() * visual.global_transform
		for n in copy.find_children("*", "", true, false):
			if n is AnimationTree or n is CollisionObject3D or n is CollisionShape3D \
					or n is Light3D or n is AudioStreamPlayer3D or n is GPUParticles3D:
				n.queue_free()
			elif n is GeometryInstance3D:
				(n as GeometryInstance3D).material_override = mat
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if copy is GeometryInstance3D:
			(copy as GeometryInstance3D).material_override = mat
		_fit_shader(copy)
		var players := copy.find_children("*", "AnimationPlayer", true, false)
		_anim = players[0] if not players.is_empty() else null

	## hologram_glitch works in the mesh's own units: the upward sweep needs the mesh's height
	## range, and the glitch shift / band size are tuned for a ~1.8 unit tall mesh. Character
	## meshes are often authored in other units (centimetres under a scaled armature), so the
	## numbers are scaled to the tallest mesh in the copy.
	func _fit_shader(root: Node) -> void:
		var best := AABB()
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var box := (n as MeshInstance3D).get_aabb()
			if box.size.y > best.size.y:
				best = box
		if best.size.y <= 0.0001:
			return
		var k := best.size.y / 1.8
		_mat.set_shader_parameter("height_min", best.position.y)
		_mat.set_shader_parameter("height_max", best.end.y)
		_mat.set_shader_parameter("glitch_strength", 0.12 * k)
		_mat.set_shader_parameter("band_density", 12.0 / k)
		_mat.set_shader_parameter("scan_density", 60.0)          # world space, no scaling needed

	## Plays the clip the caster's skill just used, fitted the same way the player's model does.
	## Returns the seconds until its hit frame.
	func play_like(from: Node3D, skill: SkillInstance, recovery: float) -> float:
		var model = from.get_node_or_null("model")
		var key := skill.get_current_animation()
		if _anim == null or model == null or key == "" or not model.has_method("get_clip_length"):
			return 0.25
		var length: float = model.get_clip_length(key)
		if length <= 0.0:
			return 0.25
		var speed := clampf(length / maxf(recovery * 0.9, 0.05), model.min_action_speed, model.max_action_speed)
		var clip: String = model._clip(key)
		if not _anim.has_animation(clip):
			return 0.25
		_anim.play(clip, 0.0, speed)
		return length * float(model.hit_points.get(key, 0.5)) / speed

	## Fades out, then stays hidden a while: projectiles and echoes from its cast check that
	## their caster still exists.
	func vanish(after: float, keep_alive: float) -> void:
		var t := create_tween()
		t.tween_interval(after)
		var start = _mat.get_shader_parameter("intensity") if _mat else null
		var from_v: float = float(start) if start != null else 1.6      # the shader's default
		t.tween_method(func(v: float) -> void:
				if _mat: _mat.set_shader_parameter("intensity", v), from_v, 0.0, 0.35)
		t.tween_callback(hide)
		t.tween_interval(keep_alive)
		t.tween_callback(queue_free)

	static func _visual_root(from: Node3D) -> Node3D:
		var model = from.get_node_or_null("model")
		if model != null and model.get("_model") is Node3D:
			return model.get("_model")                   # the player's character model
		for c in from.get_children():                    # enemies: the first child with meshes
			if c is Node3D and not (c is CollisionObject3D or c is CollisionShape3D) \
					and not c.find_children("*", "MeshInstance3D", true, false).is_empty():
				return c
		return null
