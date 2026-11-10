class_name ShootTracers
extends MultiMeshInstance3D
## Draws every Shoot bullet (ShootProjectile) in one area with a single MultiMesh: one draw call
## for all of them, the player's and the enemies' alike, instead of one MeshInstance3D each.
## The rings where bullets hit (spark()) are a second MultiMesh beside it, also one draw call:
## a rifle with pierce and forks lands dozens of hits a second, and a node, two tweens and a
## timer for each of those cost far more than drawing them.
##
## One lives next to the bullets (the area root, SkillCast.effect_parent), made on demand by
## for_parent(). Bullets add() themselves when they enter the tree and remove() themselves when
## they leave; every frame each live bullet becomes one instance: its transform (head at the
## bullet, pointing along its flight) and its colour (ShootProjectile.tint, gold or red).
## The tracer look itself is shoot_tracer.gdshader.

const NODE_NAME := &"ShootTracers"
const SHADER := preload("res://systems/skills/scenes/shoot/shoot_tracer.gdshader")
const WIDTH := 0.2                         # metres across
const TAIL := 1.0                          # metres from the head back to the tail's end
const START_CAPACITY := 32                 # instances; doubles when a fight needs more
## Hit rings: like ImpactEffect's (expand with an ease-out while fading, drawn past white so the
## glow picks them up), with the dust from ImpactDust.
const RING_TIME := 0.35
const RING_GLOW := 1.8
const RING_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"""

var _bullets: Array[ShootProjectile] = []
var _rings: MultiMeshInstance3D
## Live hit rings: [position, colour (linear, glow applied), radius, age]
var _sparks: Array = []
var _warm_frames := 0                      # prewarm(): frames left drawing one hidden tracer
var _warm_at := Vector3.ZERO


## Called while an area loads (EffectWarmup): draws one invisible tracer at `at` for a few
## frames, so its shader compiles behind the loading fade and not on the first shot.
static func prewarm(parent: Node, at: Vector3) -> void:
	var t := for_parent(parent)
	t._warm_at = at
	t._warm_frames = 30


## The tracer renderer under `parent`, made the first time a bullet needs it.
static func for_parent(parent: Node) -> ShootTracers:
	var existing := parent.get_node_or_null(NodePath(NODE_NAME)) as ShootTracers
	if existing != null and not existing.is_queued_for_deletion():
		return existing
	var t := ShootTracers.new()
	t.name = NODE_NAME
	parent.add_child(t)
	return t


## A bullet's hit: a ring that expands and fades at `pos`, plus ImpactDust's puff. Cheap: no node
## of its own. `radius` as for ImpactEffect.spawn (at least 0.5).
static func spark(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var t := for_parent(parent)
	var glow := Color(color.r * RING_GLOW, color.g * RING_GLOW, color.b * RING_GLOW, color.a)
	t._sparks.append([pos + Vector3.UP * 0.05, glow.srgb_to_linear(), maxf(radius, 0.5), 0.0])
	ImpactDust.burst(parent, pos, maxf(radius, 0.5), color)


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Instances are spread over the whole area and the shader moves the vertices, so the node's
	# own bounds mean nothing: never cull it.
	custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
	var quad := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"width", WIDTH)
	mat.set_shader_parameter(&"tail", TAIL)
	quad.material = mat
	multimesh = _new_multimesh(quad)

	var ring_shader := Shader.new()
	ring_shader.code = RING_SHADER_CODE
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = ring_shader
	var torus := TorusMesh.new()           # lies flat; thin and quick, so few segments
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	torus.material = ring_mat
	_rings = MultiMeshInstance3D.new()
	_rings.name = "HitRings"
	_rings.top_level = true
	_rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rings.custom_aabb = custom_aabb
	_rings.multimesh = _new_multimesh(torus)
	add_child(_rings)


static func _new_multimesh(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = START_CAPACITY
	mm.visible_instance_count = 0
	return mm


func add(bullet: ShootProjectile) -> void:
	if not bullet in _bullets:
		_bullets.append(bullet)


func remove(bullet: ShootProjectile) -> void:
	_bullets.erase(bullet)


## Live bullets drawn right now (for tests / debugging).
func count() -> int:
	return _bullets.size()


## Hit rings showing right now (for tests / debugging).
func spark_count() -> int:
	return _sparks.size()


func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	_draw_bullets()
	_draw_sparks(delta)


func _draw_bullets() -> void:
	var n := 0
	for b in _bullets:
		if is_instance_valid(b) and b.is_inside_tree():
			_bullets[n] = b
			n += 1
	_bullets.resize(n)
	var mm := multimesh
	if n == 0 and _warm_frames > 0:                     # prewarm(): one invisible tracer
		_warm_frames -= 1
		mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, _warm_at))
		mm.set_instance_color(0, Color(0, 0, 0, 0))
		mm.visible_instance_count = 1
		return
	_fit(mm, n)
	for i in n:
		var b := _bullets[i]
		mm.set_instance_transform(i, b.global_transform)
		mm.set_instance_color(i, b.tint.srgb_to_linear())   # the shader takes it as-is (linear)
	mm.visible_instance_count = n


func _draw_sparks(delta: float) -> void:
	_rings.global_transform = Transform3D.IDENTITY
	var n := 0
	for s in _sparks:
		s[3] += delta
		if s[3] < RING_TIME:
			_sparks[n] = s
			n += 1
	_sparks.resize(n)
	var mm := _rings.multimesh
	_fit(mm, n)
	for i in n:
		var s: Array = _sparks[i]
		var t: float = s[3] / RING_TIME
		var grow := 1.0 - pow(1.0 - t, 3.0)                # cubic ease-out, like ImpactEffect
		var r: float = s[2] * lerpf(0.2, 1.0, grow)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, 1.0, r)), s[0]))
		var c: Color = s[1]
		mm.set_instance_color(i, Color(c, c.a * (1.0 - t)))
	mm.visible_instance_count = n


## Room for `n` instances (resizing clears the buffer, so it's refilled right after).
static func _fit(mm: MultiMesh, n: int) -> void:
	if n > mm.instance_count:
		mm.visible_instance_count = 0
		mm.instance_count = maxi(n, mm.instance_count * 2)
