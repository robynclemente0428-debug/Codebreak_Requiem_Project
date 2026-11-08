class_name GlitchDeath
extends RefCounted
## The enemy death effect: the body glitches and pixelates out instead of lying there.
## EnemyBase._on_died calls play() and frees the enemy once it returns.
##   1. HOLD     the death clip starts, with a few flickers
##   2. GLITCH   slices jump, the model snaps to blocks, flickers cyan / magenta and breaks
##               apart block by block (glitch_death.gdshader), while pixel cubes burst off it
## The model keeps its own texture and colour until it breaks up.
##
## Only so many dissolve at once (MAX_DISSOLVES): past that, an enemy just bursts into a few pixels
## and goes. A dissolve sets its start time once and the shader animates it from one shared clock
## (the glitch_clock global), so nothing is sent per enemy per frame.

const SHADER := preload("res://assets/shaders/glitch_death/glitch_death.gdshader")
const HOLD := 0.3                           # seconds of death clip before it starts to go (and in the shader)
const GLITCH := 0.85                        # seconds from whole to gone (and in the shader)
const MAX_DISSOLVES := 8                    # dissolving at once
const MAX_DISSOLVES_LOW := 4                # the same on the LOW graphics preset
const PIXELS_LOW := 0.5                     # share of the pixel burst on LOW
const PIXELS_CROWD := 0.25                  # share of it for a death past the limit
const CLOCK := &"glitch_clock"
const COL_A := Color(0.0, 0.9, 1.0)
const COL_B := Color(1.0, 0.15, 0.75)

## One glitch material per original material, shared by every enemy wearing it (how far each
## one has glitched is a per-instance value, so sharing is fine).
static var _materials: Dictionary = {}
static var _dying := 0                      # dissolving now
static var _clock := 0.0                    # seconds on the shared clock, from 0 whenever it restarts
static var _clock_running := false
static var _prewarmed := false


## Call while an area loads, with the screen dark: draws the effect once, out of sight, so its
## shaders compile here and not on the first kill. Only the first area needs it.
static func prewarm(area: Node3D, at: Vector3) -> void:
	if _prewarmed:
		return
	_prewarmed = true
	var probe := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.05
	probe.mesh = box
	probe.material_override = _glitch_material(null)
	probe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(probe)
	probe.global_position = at + Vector3.UP
	probe.set_instance_shader_parameter(&"glitch_start", -100.0)   # long gone: every pixel is cut
	GlitchBurst._for(area)
	area.get_tree().create_timer(1.0, true).timeout.connect(probe.queue_free)


## Runs the effect on everything under `model_root`. `radius` and `height` are the body's, for
## the pixel burst. Returns once the model is gone.
static func play(enemy: Node3D, model_root: Node3D, radius: float, height: float) -> void:
	var tree := enemy.get_tree()
	var low := GraphicsQuality.matching_preset() == "low"
	var pixels := PIXELS_LOW if low else 1.0
	if _dying >= (MAX_DISSOLVES_LOW if low else MAX_DISSOLVES):
		_burst(enemy, radius, height, pixels * PIXELS_CROWD)
		return
	_dying += 1
	_run_clock(tree)
	var any := false
	for n in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, _glitch_material(mi.get_active_material(s)))
		mi.material_override = null
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter(&"glitch_start", _clock)
		any = true
	if not any:
		_dying -= 1
		return

	# On real time, like the clock, so slow frames skip ahead instead of stretching the effect
	await tree.create_timer(HOLD, true, false, true).timeout
	if is_instance_valid(enemy):
		_burst(enemy, radius, height, pixels)
	await tree.create_timer(GLITCH, true, false, true).timeout
	_dying -= 1


## The shared clock: one value a frame, only while something is dissolving. It starts from 0
## each time, so it never gets big enough to lose precision.
static func _run_clock(tree: SceneTree) -> void:
	if _clock_running:
		return
	_clock_running = true
	var start := Time.get_ticks_msec()
	_clock = 0.0
	RenderingServer.global_shader_parameter_set(CLOCK, _clock)
	while _dying > 0:
		await tree.process_frame
		_clock = (Time.get_ticks_msec() - start) / 1000.0
		RenderingServer.global_shader_parameter_set(CLOCK, _clock)
	_clock_running = false


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
static func _burst(enemy: Node3D, radius: float, height: float, pixels: float) -> void:
	var parent := enemy.get_parent()
	if parent == null:
		return
	GlitchBurst.burst(parent, enemy.global_position + Vector3.UP * height * 0.5, radius, height, pixels)
