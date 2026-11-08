class_name GlitchBurst
extends GPUParticles3D
## The cyan / magenta pixels that drift up off an enemy as it glitches out (GlitchDeath): ONE
## particle system per world that every death adds its pixels to, run on the GPU and drawn in
## one batch, like ImpactDust. Before, each death made its own CPUParticles3D.
##     GlitchBurst.burst(parent, centre, radius, height)
## burst() places each pixel with emit_particle(); PROCESS_CODE runs them: a short random
## delay, drifting up and slowing, cyan to magenta to gone, shrinking at the end.

const CAPACITY := 1024                  # pixels alive at once, from every death together
const HIDE_AFTER := 2.0                 # seconds after the last burst (every pixel gone): off, so idle costs nothing
const SYSTEM_LIFETIME := 120.0          # see ImpactDust: slots are only recycled this rarely
const LIFETIME := 0.9                   # longest a pixel lives (some live down to half that)
const SPREAD := 70.0                    # degrees off straight up
const SPEED_MIN := 0.8
const SPEED_MAX := 2.6
const PIXEL_SIZE := 0.14                # metres
const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY

## CUSTOM.x = size, CUSTOM.y = seconds since emitted, CUSTOM.z = delay, CUSTOM.w = lifetime.
const PROCESS_CODE := """
shader_type particles;
render_mode disable_velocity;
uniform vec3 gravity = vec3(0.0, 1.2, 0.0);       // they drift up, like data leaving
uniform float max_lifetime = 0.9;
uniform float spread_time = 0.4;                  // pixels leave over this long, not all at once
uniform vec4 col_a : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform vec4 col_b : source_color = vec4(1.0, 0.15, 0.75, 1.0);
uniform float glow = 1.6;                          // past 1.0, so the world's glow picks the pixels up

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
	if (RESTART_POSITION) {
		ACTIVE = false;          // made by the system itself, not by burst(): never shown
	} else {
		uint seed = NUMBER * 7919u + RANDOM_SEED;
		CUSTOM.x = mix(0.7, 1.4, hash(seed));
		CUSTOM.y = 0.0;
		CUSTOM.z = hash(seed + 1u) * spread_time;
		CUSTOM.w = max_lifetime * (1.0 - 0.5 * hash(seed + 2u));
	}
}

void process() {
	CUSTOM.y += DELTA;
	float age = CUSTOM.y - CUSTOM.z;
	float size = 0.0;                             // hidden, and still, until its delay is up
	if (age >= 0.0) {
		float t = age / CUSTOM.w;
		if (t >= 1.0) {
			ACTIVE = false;
		}
		VELOCITY += gravity * DELTA;
		float damping = mix(1.5, 3.0, hash(NUMBER * 31u + RANDOM_SEED));
		float speed = length(VELOCITY);
		if (speed > 0.0001) {
			VELOCITY *= max(speed - damping * DELTA, 0.0) / speed;
		}
		TRANSFORM[3].xyz += VELOCITY * DELTA;     // moved here (disable_velocity), so it waits out the delay
		// size: 1 to 0.8 over the first 70%, then down to 0
		float curve = t < 0.7 ? mix(1.0, 0.8, t / 0.7) : mix(0.8, 0.0, (t - 0.7) / 0.3);
		size = CUSTOM.x * max(curve, 0.0);
		vec4 c = t < 0.5 ? mix(col_a, col_b, t / 0.5) : mix(col_b, vec4(col_b.rgb, 0.0), (t - 0.5) / 0.5);
		COLOR = vec4(c.rgb * glow, c.a);
	}
	TRANSFORM[0].xyz = vec3(size, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, size, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, size);
}
"""

static var _current: GlitchBurst
static var _process_shader: Shader

var _hide_in := HIDE_AFTER


## Pixels for one death: from a box round the body (radius wide, height tall, centred on
## `centre`), clampi(28 x height, 16, 90) of them, times `pixels` (GlitchDeath's share).
static func burst(parent: Node, centre: Vector3, radius: float, height: float, pixels := 1.0) -> void:
	var sys := _for(parent)
	if sys == null:
		return
	sys._wake()
	var count := maxi(roundi(clampi(roundi(28.0 * height), 16, 90) * pixels), 1)
	var extents := Vector3(radius, height * 0.5, radius)
	for i in count:
		var offset := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * extents
		var dir := Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(randf() * SPREAD)) \
				.rotated(Vector3.UP, randf() * TAU)
		sys.emit_particle(Transform3D(Basis(), centre + offset), dir * randf_range(SPEED_MIN, SPEED_MAX),
				Color.WHITE, Color(), FLAGS)


## The world's burst system, made under `parent` if that world has none yet (`parent` may be
## a 3D node or the SubViewport itself).
static func _for(parent: Node) -> GlitchBurst:
	if parent == null or not parent.is_inside_tree():
		return null
	var world := (parent as Node3D).get_world_3d() if parent is Node3D \
			else parent.get_viewport().find_world_3d()
	if is_instance_valid(_current) and _current.is_inside_tree() and _current.get_world_3d() == world:
		return _current
	_current = GlitchBurst.new()
	_current.name = "GlitchBurst"
	parent.add_child(_current)
	_current.top_level = true
	_current.global_transform = Transform3D.IDENTITY
	return _current


func _wake() -> void:
	_hide_in = HIDE_AFTER
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_hide_in -= delta
	if _hide_in <= 0.0:
		visible = false
		set_process(false)


func _init() -> void:
	amount = CAPACITY
	lifetime = SYSTEM_LIFETIME
	emitting = true                             # emit_particle() needs a running system
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-1000, -50, -1000), Vector3(2000, 100, 2000))

	if _process_shader == null:
		_process_shader = Shader.new()
		_process_shader.code = PROCESS_CODE
	var pm := ShaderMaterial.new()
	pm.shader = _process_shader
	pm.set_shader_parameter("max_lifetime", LIFETIME)
	pm.set_shader_parameter("col_a", GlitchDeath.COL_A)
	pm.set_shader_parameter("col_b", GlitchDeath.COL_B)
	process_material = pm

	var pixel := QuadMesh.new()                 # flat squares facing the camera: crisp pixels
	pixel.size = Vector2.ONE * PIXEL_SIZE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pixel.material = mat
	draw_pass_1 = pixel
