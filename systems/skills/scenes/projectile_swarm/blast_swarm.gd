class_name BlastSwarm
extends MultiMeshInstance3D
## One MultiMesh that draws AND simulates every blast projectile of one team.
## Make TWO of these in the SubViewport (sibling of Player / AreaManager), identity transform:
##   PlayerBlastSwarm   use_style_material = true,  group_name = &"player_blast_swarm"
##   EnemyBlastSwarm    use_style_material = false, group_name = &"enemy_blast_swarm"
## The player swarm wears the equipped orb's own shader; the enemy swarm is a plain glowing
## ball tinted per projectile. It does no damage itself: each projectile carries an
## `on_impact` Callable that BlastBehavior bound to its cast.

const MAX := 512
const BALL_RADIUS := 0.2        # same as the SphereMesh in blast_projectile.tscn
const HIT_RADIUS := 0.35        # same as BlastProjectile.hit_radius

## Skills find the swarm through this group.
@export var group_name: StringName = &"player_blast_swarm"
## true = wear the orb's ShaderMaterial from the style (player). false = plain tinted ball.
@export var use_style_material := true
@export var emission_energy := 4.0
## The player swarm: how much brighter than the orb's own look (an additive pass on top of
## whatever shader the orb has, in each projectile's colour; 0 = none).
@export var orb_boost := 0.6

# One entry per live projectile (parallel arrays, swap-remove keeps them dense).
var _pos := PackedVector3Array()
var _dir := PackedVector3Array()
var _left := PackedFloat32Array()    # distance remaining
var _speed := PackedFloat32Array()
var _mask := PackedInt32Array()
var _exclude: Array[RID] = []
var _on_impact: Array[Callable] = []

var _query := PhysicsShapeQueryParameters3D.new()
var _no_exclude: Array[RID] = []
var _one_exclude: Array[RID] = [RID()]
var _fallback_mat: ShaderMaterial
var _style_source: Material          # the orb material currently being worn (identity check)

# Drawn over the orb's own shader (next_pass): adds each projectile's colour, strongest in the
# middle of the ball, so it reads brighter and the world's glow picks it up.
const _BOOST_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, shadows_disabled, fog_disabled;
uniform float boost = 0.6;
void fragment() {
	float core = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	ALBEDO = COLOR.rgb * boost * (0.4 + core);
}
"""

const _SHADER := """
shader_type spatial;
uniform float energy = 4.0;
void fragment() {
	// COLOR is the per-instance color set in spawn()
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * energy;
}
"""


func _ready() -> void:
	add_to_group(group_name)
	add_to_group("blast_swarms")         # AreaManager: get_tree().call_group("blast_swarms", "clear")

	var hit_shape := SphereShape3D.new()
	hit_shape.radius = HIT_RADIUS
	_query.shape = hit_shape

	var ball := SphereMesh.new()
	ball.radius = BALL_RADIUS
	ball.height = BALL_RADIUS * 2.0

	var shader := Shader.new()
	shader.code = _SHADER
	_fallback_mat = ShaderMaterial.new()
	_fallback_mat.shader = shader
	_fallback_mat.set_shader_parameter("energy", emission_energy)
	material_override = _fallback_mat

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = ball
	multimesh.instance_count = MAX
	multimesh.visible_instance_count = 0

	# MultiMesh culls using bounds around its own origin; without this, far-away
	# projectiles can disappear.
	custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))


## Call before spawn(). Makes the swarm wear the caster's orb shader (player swarm only).
## Projectiles already in flight change look too, since they share one material.
func set_style(style: Dictionary) -> void:
	var src = style.get("material")
	if not use_style_material or not (src is ShaderMaterial):
		_style_source = null
		if material_override != _fallback_mat:
			material_override = _fallback_mat
		return
	if src == _style_source:
		return                            # same orb as last time, nothing to do
	_style_source = src
	var worn := (src as ShaderMaterial).duplicate() as ShaderMaterial
	if orb_boost > 0.0 and worn.next_pass == null:
		worn.next_pass = _boost_material()
	material_override = worn


func _boost_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _BOOST_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("boost", orb_boost)
	return m


## Fire one projectile. `on_impact` is called with the impact position (Vector3).
func spawn(from: Vector3, dir: Vector3, color: Color, speed: float, max_range: float,
		hit_mask: int, exclude_rid: RID, on_impact: Callable) -> void:
	if _pos.size() >= MAX:
		return
	_pos.append(from)
	_dir.append(dir.normalized())
	_left.append(max_range)
	_speed.append(speed)
	_mask.append(hit_mask)
	_exclude.append(exclude_rid)
	_on_impact.append(on_impact)
	multimesh.set_instance_color(_pos.size() - 1, color)


## Drop every projectile in flight (call this when the area changes).
func clear() -> void:
	_pos.clear(); _dir.clear(); _left.clear(); _speed.clear(); _mask.clear()
	_exclude.clear(); _on_impact.clear()
	multimesh.visible_instance_count = 0


func _physics_process(delta: float) -> void:
	if _pos.is_empty():
		return
	var space := get_world_3d().direct_space_state

	# Backwards, so swap-remove never skips a projectile.
	var i := _pos.size() - 1
	while i >= 0:
		var step := _speed[i] * delta
		var next := _pos[i] + _dir[i] * step
		_left[i] -= step

		_query.transform = Transform3D(Basis.IDENTITY, next)
		_query.collision_mask = _mask[i]
		if _exclude[i].is_valid():
			_one_exclude[0] = _exclude[i]
			_query.exclude = _one_exclude
		else:
			_query.exclude = _no_exclude

		if _left[i] <= 0.0 or not space.intersect_shape(_query, 1).is_empty():
			var cb := _on_impact[i]
			_remove(i)
			if cb.is_valid():
				cb.call(next)             # after removal, so the callback can safely spawn more
		else:
			_pos[i] = next
		i -= 1

	multimesh.visible_instance_count = _pos.size()
	for j in _pos.size():
		multimesh.set_instance_transform(j, Transform3D(Basis.IDENTITY, _pos[j]))


func _remove(i: int) -> void:   # swap-remove
	var last := _pos.size() - 1
	if i != last:
		_pos[i] = _pos[last]
		_dir[i] = _dir[last]
		_left[i] = _left[last]
		_speed[i] = _speed[last]
		_mask[i] = _mask[last]
		_exclude[i] = _exclude[last]
		_on_impact[i] = _on_impact[last]
		multimesh.set_instance_color(i, multimesh.get_instance_color(last))
	_pos.resize(last); _dir.resize(last); _left.resize(last)
	_speed.resize(last); _mask.resize(last)
	_exclude.resize(last); _on_impact.resize(last)
