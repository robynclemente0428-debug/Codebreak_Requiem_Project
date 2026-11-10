class_name ImpactEffect
extends Node3D
## A ground impact built entirely in code: an expanding shockwave ring, a burst of dust
## (ImpactDust, shared by every impact) and a short light flash. No scene to set up. Use it from any skill:
##     ImpactEffect.spawn(caster.get_parent(), center, radius, Color(1.0, 0.8, 0.5))
## It frees itself when it is done.
## The ring's mesh and material are shared by every impact (its colour and fade are per-instance
## shader values), so many small hits a second (a rifle with pierce and forks) stay cheap.
## `light`: false leaves out the flash light (Shoot's bullet hits: the muzzle flash lights already).

const LIFETIME := 1.2                 # seconds before the effect node removes itself
const RING_TIME := 0.35               # how long the shockwave takes to expand and fade
## The ring is drawn this much brighter than its colour, past full white, so the world's glow
## (WorldEnvironment, threshold 1.0) picks it up: a slight glow, at no extra cost.
const RING_GLOW := 1.8
const RING_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
instance uniform vec4 ring_color : source_color = vec4(1.0);
void fragment() {
	ALBEDO = ring_color.rgb;
	ALPHA = ring_color.a;
}
"""

static var _ring_mesh: TorusMesh
static var _ring_mat: ShaderMaterial


static func spawn(parent: Node, pos: Vector3, radius: float,
		color: Color = Color(1.0, 0.8, 0.5), accent: Color = Color(0, 0, 0, 0), light := true) -> void:
	var fx := ImpactEffect.new()
	parent.add_child(fx)
	fx.global_position = pos
	fx.play(maxf(radius, 0.5), color, accent if accent.a > 0.0 else color, light)


func play(radius: float, color: Color, accent: Color, light := true) -> void:
	_add_ring(radius, color)
	_add_dust(radius, accent)
	if light:
		_add_flash(radius, color)
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


## The ring mesh (low-poly: it's thin and fades fast) and its material, made once.
static func _make_shared() -> void:
	if _ring_mesh != null:
		return
	var shader := Shader.new()
	shader.code = RING_SHADER_CODE
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = shader
	_ring_mesh = TorusMesh.new()          # lies flat on the ground
	_ring_mesh.inner_radius = 0.9
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 32
	_ring_mesh.ring_segments = 4
	_ring_mesh.material = _ring_mat


func _add_ring(radius: float, color: Color) -> void:
	_make_shared()
	var glow := Color(color.r * RING_GLOW, color.g * RING_GLOW, color.b * RING_GLOW, color.a)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.05                # just above the floor so it doesn't flicker
	ring.scale = Vector3(radius * 0.2, 1.0, radius * 0.2)
	ring.set_instance_shader_parameter(&"ring_color", glow)
	add_child(ring)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 1.0, radius), RING_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void:
		ring.set_instance_shader_parameter(&"ring_color", Color(glow, a)), glow.a, 0.0, RING_TIME)


func _add_dust(radius: float, color: Color) -> void:
	ImpactDust.burst(get_parent(), global_position, radius, color)   # one shared GPU system for every impact


func _add_flash(radius: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = radius * 1.5
	light.light_energy = 4.0
	light.position = Vector3(0, 0.5, 0)
	if not GraphicsQuality.allow_effect_light(light):  # GRAPHICS > EFFECT LIGHTS
		light.free()
		return
	add_child(light)
	create_tween().tween_property(light, "light_energy", 0.0, 0.25)
