class_name AimLine
extends MeshInstance3D
## A line on the ground showing where the player's ranged skill will go (Shoot, Blast...).
##   which skill:  the one on the main attack key, or, while another skill key is held, that one
##   the shots:    the skill's own aim_preview(), so it matches release() exactly (one line per
##                 projectile with Many Projectiles)
##   where it ends: the first wall, or the first enemy (or barrel) unless the shot pierces
##   Blast:        a ring at the end, the size of the explosion
## Hidden for melee skills, while a window has the player locked, and when the gameplay setting
## "aim_line" is off. The player adds it as a child.

@export var color := Color(0.0, 0.9, 1.0)
@export var width := 0.07
@export_range(0.0, 1.0) var opacity := 0.55
## Metres above the floor (just enough not to flicker into it).
@export var lift := 0.05

const PRIMARY_ACTION := &"attack"
const ENEMY_MASK := 4           # layer 3
const WORLD_MASK := 1
const RING_SEGMENTS := 40
const HIT_RADIUS := 0.5         # ShootProjectile.target_radius

var enabled := true
## Where each line ended last frame, in metres from its start (for tests / debugging).
var last_lengths: Array[float] = []
var _player: Node3D
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	_player = get_parent() as Node3D
	top_level = true                      # drawn in world space, whatever the player does
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 1
	material_override = mat
	Settings.bind_to(self, &"enabled", "gameplay", "aim_line")


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	last_lengths.clear()
	global_transform = Transform3D.IDENTITY
	var skill := _current_skill()
	if skill == null:
		return
	var shots: Array = skill.get_behavior().aim_preview(_player, skill)
	if shots.is_empty():
		return
	var alpha := opacity
	var mana = _player.get("mana")
	if mana is ManaComponent and not skill.can_afford(mana):
		alpha *= 0.35                     # can't cast it right now
	var floor_y := _player.global_position.y + lift
	last_lengths.clear()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for shot in shots:
		_draw_shot(shot, floor_y, alpha)
	_mesh.surface_end()


func _current_skill() -> SkillInstance:
	if not enabled or _player == null or _player.get("input_locked") or _player.get("_dead"):
		return null
	var skills := _player.get("skills") as SkillComponent
	if skills == null:
		return null
	var equipment = _player.get("equipment")
	var pick: SkillInstance = null
	for action in SkillComponent.ACTIONS:           # a held ranged skill key wins
		if action != PRIMARY_ACTION and Input.is_action_pressed(action):
			var s := skills.get_skill(action)
			if _is_ranged(s, equipment):
				pick = s
	if pick == null:
		var s := skills.get_skill(PRIMARY_ACTION)
		if _is_ranged(s, equipment):
			pick = s
	return pick


func _is_ranged(s: SkillInstance, equipment) -> bool:
	if s == null or s.gem == null or s.gem.behavior_script == null:
		return false
	if equipment is EquipmentComponent and not s.weapon_allows(equipment):
		return false
	return not s.get_behavior().aim_preview(_player, s).is_empty()


## One projectile: a ribbon from where it starts to where it would stop, fading out, plus a tick
## (or the explosion ring) at the end.
func _draw_shot(shot: Dictionary, floor_y: float, alpha: float) -> void:
	var from: Vector3 = shot["from"]
	var dir: Vector3 = shot["direction"]
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var length := _stop_distance(from, dir, float(shot["range"]), int(shot["pierce"]) > 0)
	last_lengths.append(length)
	var a := Vector3(from.x, floor_y, from.z)
	var b := a + dir * length
	var side := dir.cross(Vector3.UP).normalized() * width * 0.5
	var col_a := Color(color, alpha)
	var col_b := Color(color, alpha * 0.25)
	_quad(a - side, a + side, b + side, b - side, col_a, col_a, col_b, col_b)
	var radius := float(shot["radius"])
	if radius > 0.0:
		_ring(b, radius, Color(color, alpha * 0.8))
	else:
		var tick := side.normalized() * 0.3
		var along := dir * width * 0.5
		var c := Color(color, alpha * 0.9)
		_quad(b - tick - along, b + tick - along, b + tick + along, b - tick + along, c, c, c, c)


## How far the shot flies: to the first wall at its own height, or to the first enemy / barrel
## (checked low, like the bullets' hit column, so short ones count too) unless it pierces.
func _stop_distance(from: Vector3, dir: Vector3, max_range: float, pierces: bool) -> float:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if _player is CollisionObject3D:
		exclude.append((_player as CollisionObject3D).get_rid())
	var best := max_range
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_range, WORLD_MASK)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var d := Vector2(hit.position.x - from.x, hit.position.z - from.z).length()
		var c := hit.collider as Node
		if c != null and c.is_in_group(&"breakables") and pierces:
			pass                             # a piercing shot goes through barrels too
		else:
			best = minf(best, d)
	if not pierces:
		# Enemies: sweep the bullet's own hit column (floor to shot height, bullet-wide) so the line
		# stops on anything the shot would really hit, short or just beside the line
		var feet := _player.global_position.y + 0.2
		var col := CapsuleShape3D.new()
		col.radius = HIT_RADIUS
		col.height = maxf(from.y - feet, 0.0) + 2.0 * HIT_RADIUS
		var cq := PhysicsShapeQueryParameters3D.new()
		cq.shape = col
		cq.collision_mask = ENEMY_MASK
		cq.exclude = exclude
		cq.transform = Transform3D(Basis.IDENTITY, Vector3(from.x, (from.y + feet) * 0.5, from.z))
		cq.motion = dir * best
		var frac := space.cast_motion(cq)
		if frac[1] < 1.0:
			best = minf(best, best * frac[1] + HIT_RADIUS)
		# Barrels sit on the world layer: a low ray finds them
		var low := Vector3(from.x, _player.global_position.y + 0.5, from.z)
		var q2 := PhysicsRayQueryParameters3D.create(low, low + dir * best, WORLD_MASK)
		q2.exclude = exclude
		var h2 := space.intersect_ray(q2)
		if not h2.is_empty() and (h2.collider as Node) != null and (h2.collider as Node).is_in_group(&"breakables"):
			best = minf(best, Vector2(h2.position.x - from.x, h2.position.z - from.z).length())
	return maxf(best, 0.3)


func _ring(center: Vector3, radius: float, col: Color) -> void:
	var inner := maxf(radius - width, 0.0)
	for i in RING_SEGMENTS:
		var t0 := TAU * i / RING_SEGMENTS
		var t1 := TAU * (i + 1) / RING_SEGMENTS
		var d0 := Vector3(cos(t0), 0, sin(t0))
		var d1 := Vector3(cos(t1), 0, sin(t1))
		_quad(center + d0 * inner, center + d0 * radius, center + d1 * radius, center + d1 * inner,
				col, col, col, col)


func _quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	for v in [[p0, c0], [p1, c1], [p2, c2], [p0, c0], [p2, c2], [p3, c3]]:
		_mesh.surface_set_color(v[1])
		_mesh.surface_add_vertex(v[0])
