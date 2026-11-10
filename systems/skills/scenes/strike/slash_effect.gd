class_name SlashEffect
extends RefCounted
## A crescent slash sized to the strike: radius = melee range, sweep = arc angle.
## Built as a mesh at the exact size, so no scaling is needed.
##
## The look, all in one shader (SHADER_CODE):
##   blade edge  a thin white-hot line along the outer rim, where the weapon's edge passed
##   streaks     faint lines running along the arc, like motion smear
##   head flare  the leading edge burns brightest, the trail behind it fades out
##   dissolve    when it fades it breaks up in blocks (the game's glitch look) instead of dimming
## Its inner edge starts just in front of the body (BODY_GAP) whatever the reach, so a long
## reach makes the cut wider, never a ring floating away from the caster.
##
## Cheap to swing fast: one shared material (each slash's colours, progress and fade are
## per-instance shader values) and meshes cached by size. EffectWarmup draws one while the first
## area loads, so the shader is compiled before the first swing.

const HEIGHT := 0.9             # waist height, scaled with the caster
const INNER_RATIO := 0.55       # inner edge at the crescent's thickest point, for short reaches (fraction of range)
## ...but never further out than this (metres from the caster): past it the cut would float away
## from the body. A longer reach makes the crescent wider instead.
const BODY_GAP := 0.4
const SWEEP_TIME := 0.14        # seconds for the blade to travel across the arc
const FADE_DELAY := 0.08
const FADE_TIME := 0.22
const TILT_DEGREES := 18.0      # tilts the arc so it reads as a diagonal cut; 0 = flat (see tilt_for)
const FLOOR_CLEARANCE := 0.15   # metres the tilted slash's lowest point keeps above the floor
const MESH_CACHE_MAX := 32

const SHADER_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

instance uniform vec4 color_a : source_color = vec4(1.0, 0.45, 0.1, 1.0);   // inner (deep)
instance uniform vec4 color_b : source_color = vec4(1.0, 0.8, 0.5, 1.0);    // outer (bright)
instance uniform float progress = 0.0;      // 0..1: where the blade is along the arc
instance uniform float fade = 0.0;          // 0..1: how far it has dissolved
instance uniform float flip = 0.0;          // 1 = sweeps the other way
instance uniform float strength = 1.0;      // the afterimage is fainter

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float u = mix(UV.x, 1.0 - UV.x, flip);              // along the sweep
	float v = UV.y;                                     // inner edge 0 .. outer edge 1
	float head = progress * 1.3;                        // the blade's leading edge
	float behind = head - u;                            // how far behind the blade
	float lead = smoothstep(-0.02, 0.03, behind);       // nothing ahead of the blade
	float trail = pow(clamp(1.0 - behind / 0.6, 0.0, 1.0), 1.4);
	float flare = exp(-behind * behind * 180.0);        // the leading edge burns brightest

	float body = smoothstep(0.0, 0.35, v);              // soft inside, solid towards the rim
	float edge = smoothstep(0.82, 0.95, v) * (1.0 - smoothstep(0.97, 1.0, v));   // the blade's line
	float streak = 0.72 + 0.28 * sin(v * 46.0) * sin(v * 17.0 + 1.3);         // smear along the arc

	vec3 col = mix(color_a.rgb, color_b.rgb, v) * (1.0 + 0.8 * flare);
	col = mix(col, vec3(1.0), edge * 0.85);             // white-hot edge
	col *= 1.2 + edge * 1.6 + flare * 1.2;              // past 1.0: the world's glow picks it up

	// Fading breaks it up in blocks, outer edge last
	float cell = hash(floor(vec2(u * 46.0, v * 7.0)));
	float keep = step(fade * 1.15, cell * 0.85 + v * 0.15);

	ALBEDO = col;
	ALPHA = clamp(lead * trail * body * streak * keep * strength + edge * lead * trail * keep * 0.5 * strength, 0.0, 1.0);
}
"""

static var _shader: Shader
static var _material: ShaderMaterial
static var _meshes: Dictionary = {}       # "radius|arc" -> ArrayMesh


static func spawn(caster: Node3D, radius: float, arc_degrees: float,
		style: Dictionary, flip: bool = false) -> void:
	if radius <= 0.0 or arc_degrees <= 0.0 or not is_instance_valid(caster):
		return
	var parent: Node = caster.get_tree().current_scene
	if parent == null:
		parent = caster.get_parent()
	# +Z is forward, same convention as the body. Placed in world space so it doesn't follow the caster.
	var height: float = HEIGHT * caster.global_transform.basis.get_scale().y
	var tilt := tilt_for(radius, arc_degrees, height) * (-1.0 if flip else 1.0)
	var basis := Basis(Vector3.UP, caster.global_rotation.y) * Basis(Vector3(0, 0, 1), tilt)
	var at := Transform3D(basis, caster.global_position + Vector3.UP * height)
	_add_slash(parent, _mesh_for(radius, arc_degrees), at, style, flip, 1.0, 0.0)


## The tilt (radians) for a slash this wide at `height` above the floor: TILT_DEGREES, but never
## so much that its low side dips into the floor. The tilt turns the crescent round the forward
## axis, so its far side drops by (sideways reach x sin tilt): 0.9 m at 6 m of reach, 3.7 m at 12.
## The floor then hid that part, cut off along a straight line, and the other side rose towards
## the camera. Long reaches flatten out instead, keeping FLOOR_CLEARANCE above the floor.
static func tilt_for(radius: float, arc_degrees: float, height: float) -> float:
	var half := deg_to_rad(minf(arc_degrees, 360.0)) * 0.5
	var sideways := radius * (sin(half) if half < PI * 0.5 else 1.0)   # how far out to the side it reaches
	var room := maxf(height - FLOOR_CLEARANCE, 0.0)
	if sideways <= room:
		return deg_to_rad(TILT_DEGREES)
	return minf(deg_to_rad(TILT_DEGREES), asin(room / sideways))


## One crescent: sweeps, then dissolves, then frees itself.
static func _add_slash(parent: Node, mesh: ArrayMesh, at: Transform3D, style: Dictionary, flip: bool,
		strength: float, delay: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _get_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter(&"color_a", style.get("primary", Color(1.0, 0.45, 0.1)))
	mi.set_instance_shader_parameter(&"color_b", style.get("secondary", Color(1.0, 0.8, 0.5)))
	mi.set_instance_shader_parameter(&"flip", 1.0 if flip else 0.0)
	mi.set_instance_shader_parameter(&"strength", strength)
	mi.set_instance_shader_parameter(&"progress", 0.0)
	mi.set_instance_shader_parameter(&"fade", 0.0)
	parent.add_child(mi)
	mi.global_transform = at

	var tw := mi.create_tween().set_parallel(true)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter(&"progress", v),
			0.0, 1.0, SWEEP_TIME).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter(&"fade", v),
			0.0, 1.0, FADE_TIME).set_delay(delay + FADE_DELAY)
	tw.chain().tween_callback(mi.queue_free)


## Draws one slash at `at` (under the floor, out of sight) while an area loads, so the shader
## compiles before the first swing (EffectWarmup).
static func prewarm(parent: Node, at: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	_add_slash(parent, _mesh_for(1.5, 120.0), Transform3D(Basis.IDENTITY, at), {}, false, 1.0, 0.0)


static func _get_material() -> ShaderMaterial:
	if _material == null:
		if _shader == null:
			_shader = Shader.new()
			_shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = _shader
	return _material


## The crescent for this reach and arc, built once and reused (a few sizes per build).
static func _mesh_for(radius: float, arc_degrees: float) -> ArrayMesh:
	var key := "%d|%d" % [roundi(radius * 20.0), roundi(arc_degrees)]
	if not _meshes.has(key):
		if _meshes.size() >= MESH_CACHE_MAX:
			_meshes.clear()
		_meshes[key] = _build_mesh(radius, arc_degrees)
	return _meshes[key]


## Flat crescent in the XZ plane centred on forward (+Z). UV.x runs along the sweep,
## UV.y runs from the inner edge (0) to the outer edge (1).
static func _build_mesh(radius: float, arc_degrees: float) -> ArrayMesh:
	var segments: int = clampi(int(arc_degrees / 4.0), 12, 96)   # smooth curve
	var half: float = deg_to_rad(arc_degrees) * 0.5
	var full_ring: bool = arc_degrees >= 350.0          # no taper for a 360 spin
	var near: float = minf(radius * INNER_RATIO, BODY_GAP)   # the inner edge's closest point

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	for i in segments + 1:
		var u: float = float(i) / float(segments)
		var a: float = lerpf(-half, half, u)
		var dir := Vector3(sin(a), 0.0, cos(a))
		# Thin, sharp tips and a thick middle (the power makes the tips come to a point)
		var thick: float = 1.0 if full_ring else pow(sin(u * PI), 0.75)
		var inner: float = lerpf(radius, near, thick)
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
