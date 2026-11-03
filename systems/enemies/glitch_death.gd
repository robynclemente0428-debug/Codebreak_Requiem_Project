class_name GlitchDeath
extends RefCounted
## The enemy death effect: the body glitches and pixelates out instead of lying there.
## EnemyBase._on_died calls play() and frees the enemy once it returns.
##   1. HOLD     the death clip starts, with a few flickers
##   2. GLITCH   slices jump, the model snaps to blocks, flickers cyan / magenta and breaks
##               apart block by block (glitch_death.gdshader), while pixel cubes burst off it
## The model keeps its own texture and colour until it breaks up.

const SHADER := preload("res://assets/shaders/glitch_death/glitch_death.gdshader")
const HOLD := 0.3                           # seconds of death clip before it starts to go
const GLITCH := 0.85                        # seconds from whole to gone
const COL_A := Color(0.0, 0.9, 1.0)
const COL_B := Color(1.0, 0.15, 0.75)

## One glitch material per original material, shared by every enemy wearing it (how far each
## one has glitched is a per-instance value, so sharing is fine).
static var _materials: Dictionary = {}


## Runs the effect on everything under `model_root`. `radius` and `height` are the body's, for
## the pixel burst. Returns once the model is gone.
static func play(enemy: Node3D, model_root: Node3D, radius: float, height: float) -> void:
	var tree := enemy.get_tree()
	var meshes: Array[GeometryInstance3D] = []
	for n in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, _glitch_material(mi.get_active_material(s)))
		mi.material_override = null
		mi.set_instance_shader_parameter(&"glitch", 0.0)
		meshes.append(mi)
	if meshes.is_empty():
		return

	# Timed on the clock, so a slow frame (the shader compiling on the first death) skips ahead
	# instead of stretching the effect
	var start := Time.get_ticks_msec()
	var burst := false
	while true:
		await tree.process_frame
		if not is_instance_valid(enemy):
			return
		var t := (Time.get_ticks_msec() - start) / 1000.0
		if t < HOLD:
			# HOLD: the death clip plays, with a couple of quick flickers
			_set_glitch(meshes, 0.35 if fmod(t, 0.12) < 0.04 else 0.0)
			continue
		if not burst:
			burst = true
			_burst(enemy, radius, height)
		# GLITCH: whole to gone
		_set_glitch(meshes, clampf((t - HOLD) / GLITCH, 0.0, 1.0))
		if t >= HOLD + GLITCH:
			return


static func _set_glitch(meshes: Array[GeometryInstance3D], v: float) -> void:
	for m in meshes:
		if is_instance_valid(m):
			m.set_instance_shader_parameter(&"glitch", v)


static func _glitch_material(original: Material) -> ShaderMaterial:
	var key: Variant = original if original != null else &"none"
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"glitch_a", COL_A)
	m.set_shader_parameter(&"glitch_b", COL_B)
	if original is BaseMaterial3D:
		var b := original as BaseMaterial3D
		m.set_shader_parameter(&"albedo_color", b.albedo_color)
		if b.albedo_texture != null:
			m.set_shader_parameter(&"albedo_tex", b.albedo_texture)
	_materials[key] = m
	return m


## Cyan and magenta pixels drifting up off the body. Added to the enemy's parent so they
## outlive it, and freed when done.
static func _burst(enemy: Node3D, radius: float, height: float) -> void:
	var parent := enemy.get_parent()
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = clampi(roundi(28.0 * height), 16, 90)
	p.lifetime = 0.9
	p.explosiveness = 0.55
	p.randomness = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(radius, height * 0.5, radius)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0.0, 1.2, 0.0)          # they drift up, like data leaving
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.7, 0.8))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var ramp := Gradient.new()
	ramp.set_color(0, COL_A)
	ramp.set_color(1, Color(COL_B, 0.0))
	ramp.add_point(0.5, COL_B)
	p.color_ramp = ramp
	var pixel := QuadMesh.new()                 # flat squares facing the camera: crisp pixels
	pixel.size = Vector2.ONE * 0.14
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pixel.material = mat
	p.mesh = pixel
	parent.add_child(p)
	p.global_position = enemy.global_position + Vector3.UP * height * 0.5
	p.emitting = true
	p.finished.connect(p.queue_free)
