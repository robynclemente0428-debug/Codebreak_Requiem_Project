class_name MulticastSupport
extends SupportBehavior

const SHADER := preload("res://assets/shaders/materials/game_shaders/hologram_glitch.gdshader")
const KEEP_ALIVE := 6.0

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
	await caster.get_tree().process_frame
	if not cast.is_valid():
		return

	var holo := Hologram.new()
	holo.source = caster
	if SkillTargets.is_enemy(caster):
		holo.set_meta(&"hologram_of_enemy", true)
	parent.add_child(holo)
	var right := caster.global_transform.basis.x.normalized()
	holo.global_transform = caster.global_transform
	holo.global_position += right * side * cast.flag("multicast_offset")
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	holo.build_visual(caster, mat)

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
		s.before_release(copy)
	cast.behavior.release(copy)
	holo.vanish(maxf(cast.flag("multicast_linger"), 0.1), KEEP_ALIVE)


class Hologram extends Node3D:
	var source: Node3D
	var _mat: ShaderMaterial
	var _anim: AnimationPlayer

	func get_effect_style() -> Dictionary:
		return SkillStyle.for_caster(source) if is_instance_valid(source) else SkillStyle.default_style()

	func build_visual(from: Node3D, mat: ShaderMaterial) -> void:
		_mat = mat
		var visual := _visual_root(from)
		if visual == null:
			return
		var copy := visual.duplicate(0) as Node3D
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
		_mat.set_shader_parameter("scan_density", 60.0)

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

	func vanish(after: float, keep_alive: float) -> void:
		var t := create_tween()
		t.tween_interval(after)
		var start = _mat.get_shader_parameter("intensity") if _mat else null
		var from_v: float = float(start) if start != null else 1.6
		t.tween_method(func(v: float) -> void:
				if _mat: _mat.set_shader_parameter("intensity", v), from_v, 0.0, 0.35)
		t.tween_callback(hide)
		t.tween_interval(keep_alive)
		t.tween_callback(queue_free)

	static func _visual_root(from: Node3D) -> Node3D:
		var model = from.get_node_or_null("model")
		if model != null and model.get("_model") is Node3D:
			return model.get("_model")
		for c in from.get_children():
			if c is Node3D and not (c is CollisionObject3D or c is CollisionShape3D) \
					and not c.find_children("*", "MeshInstance3D", true, false).is_empty():
				return c
		return null
