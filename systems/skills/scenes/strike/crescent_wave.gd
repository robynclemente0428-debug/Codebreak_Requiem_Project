class_name CrescentWave
extends Node3D
## Rending Wave's projectile: a glowing crescent blade that flies forward from the swing and
## cuts every enemy it passes through, once each. The middle of the crescent leads and the
## tips trail behind, so enemies near the edges are cut a moment later than the one in front.
##
##     CrescentWave.launch(cast, start_distance, max_distance, width, speed, damage, exclude)

const HEIGHT := 0.9             # waist height, scaled with the caster
const SWEEP_DEGREES := 110.0    # how strongly the blade curves (tips to middle)
const THICKNESS := 0.28         # thickness at the middle, as a fraction of the width
const HIT_PADDING := 0.45       # roughly a body's radius, so the blade's edge counts as a hit
const FADE_TIME := 0.15

const SHADER_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 color_a : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform float fade : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float edge = smoothstep(0.55, 1.0, UV.y);             // bright leading edge
	float tips = sin(UV.x * 3.14159);                     // fainter towards the tips
	float shimmer = 0.85 + 0.15 * sin(TIME * 40.0 + UV.x * 18.0);
	vec3 col = mix(color_a.rgb, color_b.rgb, UV.y) * (0.7 + edge * 2.0) * shimmer;
	ALBEDO = col;
	ALPHA = (0.35 + edge) * tips * smoothstep(0.0, 0.3, UV.y) * (1.0 - fade);
}
"""

static var _shader: Shader

var _cast: SkillCast
var _origin := Vector3.ZERO     # flat, at the caster's feet
var _fwd := Vector3.FORWARD
var _right := Vector3.RIGHT
var _dist := 0.0
var _end := 0.0
var _half := 1.5
var _bow := 0.5                 # how far the tips trail behind the middle
var _speed := 16.0
var _damage := 0.6
var _hit: Array = []
var _height := 0.9
var _mat: ShaderMaterial
var _done := false


static func launch(cast: SkillCast, start: float, end: float, width: float, speed: float,
		damage: float, exclude: Array) -> CrescentWave:
	var caster := cast.caster
	var parent := cast.effect_parent()
	if parent == null or not is_instance_valid(caster):
		return null
	var w := CrescentWave.new()
	w._cast = cast
	w._origin = caster.global_position
	w._fwd = SkillDeliveries.forward(caster)
	w._right = Vector3.UP.cross(w._fwd).normalized() * -1.0
	w._dist = start
	w._end = maxf(end, start + 0.5)
	w._half = maxf(width, 0.5) * 0.5
	w._speed = maxf(speed, 1.0)
	w._damage = damage
	w._hit = exclude.duplicate()
	w._height = HEIGHT * caster.global_transform.basis.get_scale().y
	var style := SkillStyle.for_caster(caster)
	parent.add_child(w)
	w._build(style)
	w._place()
	return w


func _build(style: Dictionary) -> void:
	_mat = ShaderMaterial.new()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat.shader = _shader
	_mat.set_shader_parameter("color_a", style["primary"])
	_mat.set_shader_parameter("color_b", style["secondary"])
	var mi := MeshInstance3D.new()
	mi.mesh = _build_mesh()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The blade: an arc whose chord is the wave's width, moved so the middle of its leading
## edge sits on this node's origin. UV.x runs tip to tip, UV.y from the back edge (0) to the
## leading edge (1).
func _build_mesh() -> ArrayMesh:
	var half_a := deg_to_rad(SWEEP_DEGREES) * 0.5
	var radius := _half / sin(half_a)
	_bow = radius * (1.0 - cos(half_a))
	var thick := _half * 2.0 * THICKNESS
	var segments := 24
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in segments + 1:
		var u := float(i) / segments
		var a := lerpf(-half_a, half_a, u)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var t := thick * sin(u * PI)                       # pointed tips, thick middle
		verts.append(dir * (radius - t) - Vector3(0, 0, radius))
		uvs.append(Vector2(u, 0.0))
		verts.append(dir * radius - Vector3(0, 0, radius))
		uvs.append(Vector2(u, 1.0))
	for i in segments:
		var k := i * 2
		idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _place() -> void:
	global_transform = Transform3D(Basis.looking_at(-_fwd, Vector3.UP),
			_origin + _fwd * _dist + Vector3.UP * _height)


func _physics_process(delta: float) -> void:
	if _done:
		return
	var prev := _dist
	_dist = minf(_dist + _speed * delta, _end)
	_place()
	_cut(prev, _dist)
	if _dist >= _end:
		_finish()


## Hits everything the blade swept over between two distances. The leading edge at a
## sideways offset x sits at dist - bow * (x / half)^2, so the tips arrive later.
func _cut(from_d: float, to_d: float) -> void:
	if _cast == null or not _cast.is_valid():
		return
	var cap := int(_cast.flag("max_targets"))
	for t in SkillTargets.hittable(_cast.caster):
		if cap > 0 and _hit.size() >= cap + _cast.already_hit.size():
			return
		if not is_instance_valid(t) or not (t is Node3D) or t in _hit:
			continue
		var rel: Vector3 = (t as Node3D).global_position - _origin
		var side := absf(rel.dot(_right))
		if side > _half + HIT_PADDING:
			continue
		var along := rel.dot(_fwd)
		var lag := _bow * pow(clampf(side / _half, 0.0, 1.0), 2.0)
		if along <= to_d - lag + HIT_PADDING and along >= from_d - lag - HIT_PADDING * 2.0:
			_hit.append(t)
			_cast.hit(t, _damage)


func _finish() -> void:
	_done = true
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("fade", v), 0.0, 1.0, FADE_TIME)
	tw.tween_callback(queue_free)
