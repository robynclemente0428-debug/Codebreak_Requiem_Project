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


## Cyan and magenta pixels drifting up off the body, on the world's shared GlitchBurst system
## (so they outlive the enemy, and every death's pixels draw together).
static func _burst(enemy: Node3D, radius: float, height: float) -> void:
	var parent := enemy.get_parent()
	if parent == null:
		return
	GlitchBurst.burst(parent, enemy.global_position + Vector3.UP * height * 0.5, radius, height)
