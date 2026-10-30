class_name SlashEffect
extends RefCounted
## A crescent slash sized to the strike: radius = melee range, sweep = arc angle.
## Built as a mesh at the exact size, so no scaling is needed.

const HEIGHT := 0.9             # waist height, scaled with the caster
const INNER_RATIO := 0.55       # inner edge at the crescent's thickest point (fraction of range)
const SWEEP_TIME := 0.14        # seconds for the blade to travel across the arc
const FADE_DELAY := 0.08
const FADE_TIME := 0.2
const TILT_DEGREES := 18.0      # tilts the arc so it reads as a diagonal cut; 0 = flat

const SHADER_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 color_a : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float flip = 0.0;

void fragment() {
	float u = mix(UV.x, 1.0 - UV.x, flip);               // sweep direction
	float head = progress * 1.4;                         // leading edge of the cut
	float lead = 1.0 - smoothstep(head - 0.05, head, u); // nothing ahead of the edge
	float trail = clamp(1.0 - (head - u) / 0.6, 0.0, 1.0); // brightest at the edge, fading behind
	float rim = smoothstep(0.7, 1.0, UV.y);              // bright outer edge
	vec3 col = mix(color_a.rgb, color_b.rgb, UV.y) * (0.8 + rim * 1.5);
	ALBEDO = col;
	ALPHA = lead * trail * (1.0 - fade) * smoothstep(0.0, 0.25, UV.y);
}
"""

static var _shader: Shader


static func spawn(caster: Node3D, radius: float, arc_degrees: float,
		style: Dictionary, flip: bool = false) -> void:
	if radius <= 0.0 or arc_degrees <= 0.0 or not is_instance_valid(caster):
		return
	var parent: Node = caster.get_tree().current_scene
	if parent == null:
		parent = caster.get_parent()

	var mat := ShaderMaterial.new()
	mat.shader = _get_shader()
	mat.set_shader_parameter("color_a", style["primary"])
	mat.set_shader_parameter("color_b", style["secondary"])
	mat.set_shader_parameter("flip", 1.0 if flip else 0.0)

	var mi := MeshInstance3D.new()
	mi.mesh = _build_mesh(radius, arc_degrees)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

	# +Z is forward, same convention as the body. Placed in world space so it doesn't follow the caster.
	var tilt := deg_to_rad(TILT_DEGREES) * (-1.0 if flip else 1.0)
	var basis := Basis(Vector3.UP, caster.global_rotation.y) * Basis(Vector3(0, 0, 1), tilt)
	var height: float = HEIGHT * caster.global_transform.basis.get_scale().y
	mi.global_transform = Transform3D(basis, caster.global_position + Vector3.UP * height)

	var tw := mi.create_tween().set_parallel(true)
	tw.tween_method(func(v: float): mat.set_shader_parameter("progress", v),
			0.0, 1.0, SWEEP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): mat.set_shader_parameter("fade", v),
			0.0, 1.0, FADE_TIME).set_delay(FADE_DELAY)
	tw.chain().tween_callback(mi.queue_free)


static func _get_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader


## Flat crescent in the XZ plane centred on forward (+Z). UV.x runs along the sweep,
## UV.y runs from the inner edge (0) to the outer edge (1).
static func _build_mesh(radius: float, arc_degrees: float) -> ArrayMesh:
	var segments: int = clampi(int(arc_degrees / 6.0), 8, 64)
	var half: float = deg_to_rad(arc_degrees) * 0.5
	var full_ring: bool = arc_degrees >= 350.0          # no taper for a 360 spin

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	for i in segments + 1:
		var u: float = float(i) / float(segments)
		var a: float = lerpf(-half, half, u)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var thick: float = 1.0 if full_ring else sin(u * PI)    # thin tips, thick middle
		var inner: float = radius * lerpf(1.0, INNER_RATIO, thick)
		verts.append(dir * inner)
		uvs.append(Vector2(u, 0.0))
		verts.append(dir * radius)
		uvs.append(Vector2(u, 1.0))

	for i in segments:
		var k := i * 2
		idx.append(k)
		idx.append(k + 1)
		idx.append(k + 2)
		idx.append(k + 1)
		idx.append(k + 3)
		idx.append(k + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
