class_name ImpactDust
extends GPUParticles3D
## The dust of every ImpactEffect (slams, blasts, aftershocks...), for players and enemies alike:
## ONE particle system per world that every impact adds its puffs to, simulated on the GPU and
## drawn in one batch. Before, each impact made its own CPUParticles3D, which the CPU had to run.
##     ImpactDust.burst(parent, position, radius, colour)
## The system is made on first use, under `parent`. burst() places each puff with
## emit_particle(); PROCESS_CODE runs them (fall, fade, grow) and switches off at once the
## particles the system would make on its own.

const CAPACITY := 2048                  # puffs alive at once, from every impact together
const LIFETIME := 0.7
const GRAVITY := Vector3(0, -6, 0)
const SPREAD := 70.0                    # degrees off straight up
const SPEED_MIN := 1.5
const SPEED_MAX := 3.5
const SCALE_MIN := 0.6
const SCALE_MAX := 1.4
const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY \
		| GPUParticles3D.EMIT_FLAG_COLOR

# A long system lifetime: the system only recycles a particle slot (which would end a puff
# early) once every SYSTEM_LIFETIME seconds; each puff ends itself after LIFETIME.
const SYSTEM_LIFETIME := 120.0

## Runs every puff. CUSTOM.x = size, CUSTOM.y = age (0..1).
const PROCESS_CODE := """
shader_type particles;
uniform vec3 gravity = vec3(0.0, -6.0, 0.0);
uniform float puff_lifetime = 0.7;
uniform float scale_min = 0.6;
uniform float scale_max = 1.4;

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
	if (RESTART_POSITION) {
		ACTIVE = false;          // made by the system itself, not by burst(): never shown
	} else {
		CUSTOM.x = mix(scale_min, scale_max, hash(NUMBER + RANDOM_SEED));
		CUSTOM.y = 0.0;
	}
}

void process() {
	CUSTOM.y += DELTA / puff_lifetime;
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	VELOCITY += gravity * DELTA;
	COLOR.a = 0.9 * (1.0 - clamp(CUSTOM.y, 0.0, 1.0));
	TRANSFORM[0].xyz = vec3(CUSTOM.x, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, CUSTOM.x, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, CUSTOM.x);
}
"""

static var _current: ImpactDust
static var _process_shader: Shader


## Puffs for one impact: int(12 + radius * 6) of them, from inside a sphere of radius * 0.6
## around `pos`, thrown upwards and falling back while they fade (as the old per-impact dust).
static func burst(parent: Node, pos: Vector3, radius: float, colour: Color) -> void:
	var dust := _for(parent)
	if dust == null:
		return
	var tint := colour.lerp(Color(0.55, 0.5, 0.45), 0.6)
	tint.a = 1.0
	var count := int(12 + radius * 6.0)
	var reach := radius * 0.6
	for i in count:
		var offset := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		while offset.length_squared() > 1.0:     # inside the sphere, not just its box
			offset = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		var dir := Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(randf() * SPREAD)) \
				.rotated(Vector3.UP, randf() * TAU)
		var at := Transform3D(Basis(), pos + offset * reach)
		dust.emit_particle(at, dir * randf_range(SPEED_MIN, SPEED_MAX), tint, Color(), FLAGS)


## The world's dust system, made under `parent` if that world has none yet. `parent` may be a
## 3D node or the SubViewport itself (where skills put their effects: SkillCast.effect_parent).
static func _for(parent: Node) -> ImpactDust:
	if parent == null or not parent.is_inside_tree():
		return null
	var world := (parent as Node3D).get_world_3d() if parent is Node3D \
			else parent.get_viewport().find_world_3d()
	if is_instance_valid(_current) and _current.is_inside_tree() and _current.get_world_3d() == world:
		return _current
	_current = ImpactDust.new()
	_current.name = "ImpactDust"
	parent.add_child(_current)
	_current.top_level = true                   # world-space puffs, wherever the parent is
	_current.global_transform = Transform3D.IDENTITY
	return _current


func _init() -> void:
	amount = CAPACITY
	lifetime = SYSTEM_LIFETIME
	emitting = true                             # emit_particle() needs a running system
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-1000, -50, -1000), Vector3(2000, 100, 2000))   # anywhere in the area

	if _process_shader == null:
		_process_shader = Shader.new()
		_process_shader.code = PROCESS_CODE
	var pm := ShaderMaterial.new()
	pm.shader = _process_shader
	pm.set_shader_parameter("gravity", GRAVITY)
	pm.set_shader_parameter("puff_lifetime", LIFETIME)
	pm.set_shader_parameter("scale_min", SCALE_MIN)
	pm.set_shader_parameter("scale_max", SCALE_MAX)
	process_material = pm

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true       # the impact's tint, fading (PROCESS_CODE)
	var puff := SphereMesh.new()
	puff.radius = 0.12
	puff.height = 0.24
	puff.radial_segments = 8                    # small puffs: few triangles are plenty
	puff.rings = 4
	puff.material = mat
	draw_pass_1 = puff
