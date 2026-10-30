class_name ImpactEffect
extends Node3D
## A ground impact built entirely in code: an expanding shockwave ring, a burst of dust,
## and a short light flash. No scene to set up. Use it from any skill:
##     ImpactEffect.spawn(caster.get_parent(), center, radius, Color(1.0, 0.8, 0.5))
## It frees itself when it is done.

const LIFETIME := 1.2                 # seconds before the effect node removes itself
const RING_TIME := 0.35               # how long the shockwave takes to expand and fade

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
	mat.albedo_color = color

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
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true     # lets the gradient below fade the puffs out
	mat.albedo_color = color.lerp(Color(0.55, 0.5, 0.45), 0.6)

	var puff := SphereMesh.new()
	puff.radius = 0.12
	puff.height = 0.24
	puff.material = mat

	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))

	var p := CPUParticles3D.new()
	p.mesh = puff
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = int(12 + radius * 6.0)
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.6
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.color_ramp = fade
	add_child(p)
	p.emitting = true


func _add_flash(radius: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = radius * 1.5
	light.light_energy = 4.0
	light.position = Vector3(0, 0.5, 0)
	add_child(light)
	create_tween().tween_property(light, "light_energy", 0.0, 0.25)
