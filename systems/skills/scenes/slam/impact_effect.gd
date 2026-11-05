class_name ImpactEffect
extends Node3D
## A ground impact built entirely in code: an expanding shockwave ring, a burst of dust
## (ImpactDust, shared by every impact) and a short light flash. No scene to set up. Use it from any skill:
##     ImpactEffect.spawn(caster.get_parent(), center, radius, Color(1.0, 0.8, 0.5))
## It frees itself when it is done.

const LIFETIME := 1.2                 # seconds before the effect node removes itself
const RING_TIME := 0.35               # how long the shockwave takes to expand and fade
## The ring is drawn this much brighter than its colour, past full white, so the world's glow
## (WorldEnvironment, threshold 1.0) picks it up: a slight glow, at no extra cost.
const RING_GLOW := 1.8

static func spawn(parent: Node, pos: Vector3, radius: float,
		color: Color = Color(1.0, 0.8, 0.5), accent: Color = Color(0, 0, 0, 0)) -> void:
	var fx := ImpactEffect.new()
	parent.add_child(fx)
	fx.global_position = pos
	fx.play(maxf(radius, 0.5), color, accent if accent.a > 0.0 else color)


func play(radius: float, color: Color, accent: Color) -> void:
	_add_ring(radius, color)
	_add_dust(radius, accent)
	_add_flash(radius, color)
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


func _add_ring(radius: float, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r * RING_GLOW, color.g * RING_GLOW, color.b * RING_GLOW, color.a)

	var torus := TorusMesh.new()          # lies flat on the ground
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.material = mat

	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.position.y = 0.05                # just above the floor so it doesn't flicker
	ring.scale = Vector3(radius * 0.2, 1.0, radius * 0.2)
	add_child(ring)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 1.0, radius), RING_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, RING_TIME)


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
