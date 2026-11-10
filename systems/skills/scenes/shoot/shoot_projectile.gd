class_name ShootProjectile
extends Node3D
## A fast bullet. It sweeps its whole path every physics frame so it can't tunnel through
## enemies, reports each enemy it passes through, and stops on world geometry or once it has
## used up its pierce. It does no damage itself: ShootBehavior listens to `hit_enemy`.
## It has no mesh of its own: ShootTracers draws every bullet in the area with one MultiMesh.

## pierced_so_far is 0 for the first enemy hit, 1 for the second, and so on.
signal hit_enemy(target: Node, position: Vector3, pierced_so_far: int)
signal hit_world(position: Vector3)

## Physics layers it collides with: world (layer 1) + enemies (layer 3) by default.
@export_flags_3d_physics var hit_mask: int = 5
## How wide the bullet is against walls.
@export var hit_radius: float = 0.15
## How wide the player's bullets are against enemies and barrels, so near misses still count.
## Enemies' bullets use hit_radius for this too, so they don't get easier to land on the player.
@export var target_radius: float = 0.5
@export var enemy_group: StringName = &"enemies"

## Players' bullets are gold, everyone else's red (ShootBehavior sets it).
const TINT_PLAYER := Color(1.0, 0.85, 0.4)
const TINT_ENEMY := Color(1.0, 0.2, 0.35)

var direction := Vector3.FORWARD
var tint := TINT_PLAYER
var speed := 60.0
var max_distance := 30.0
## Extra enemies it can pass through. 0 = stops at the first enemy it hits.
var pierce := 0
var exclude: Array[RID] = []
## Height the hit check reaches down to (world y). The bullet flies at the gun's height, which is
## above barrels and small enemies, so anything under its path down to here counts as hit.
## Walls are still only checked at the bullet itself. INF = only the bullet itself.
var floor_y := INF
## Where the shooter stands, at the bullet's height. On its first frame the bullet also checks
## from here to where it appeared (the barrel's tip), for enemies right in front of the shooter.
## INF = no such check (fork bullets, which start on an enemy).
var point_blank_from := Vector3.INF

var _travelled := 0.0
var _pierced := 0
var _done := false
var _started := false
var _wall_shape := SphereShape3D.new()
var _box := BoxShape3D.new()             # one step of flight, from the bullet down to floor_y
var _tracers: ShootTracers               # draws this bullet (with every other one in the area)


func _ready() -> void:
	if enemy_group != &"enemies":
		target_radius = hit_radius
	_wall_shape.radius = hit_radius
	look_at(global_position + direction, Vector3.UP)     # point the tracer along its flight
	_tracers = ShootTracers.for_parent(get_parent())
	_tracers.add(self)


func _exit_tree() -> void:
	if is_instance_valid(_tracers):
		_tracers.remove(self)


func _physics_process(delta: float) -> void:
	if _done:
		return
	# First frame: the bullet appears at the gun's barrel, in front of the shooter. Check the
	# gap behind it too, so an enemy standing closer than the barrel's tip still gets hit.
	if not _started:
		_started = true
		if point_blank_from != Vector3.INF and _sweep(point_blank_from, global_position, true, false):
			return
	var step := minf(speed * delta, max_distance - _travelled)
	if _sweep(global_position, global_position + direction * step, false, true):
		return
	global_position += direction * step
	_travelled += step
	if _travelled >= max_distance:
		_finish(global_position)


## Checks the path from `from` to `to` for targets (and walls, if `walls`). True when the bullet
## stopped (out of pierce, or hit a wall). Cheap enough for many bullets at once: one swept sphere
## finds the first wall, then ONE box over the whole step (bullet-wide, from the bullet down to
## floor_y) finds every target on the way, hit in the order the bullet reaches them.
## `_include_start`: kept for the callers; the box always covers the start too.
func _sweep(from: Vector3, to: Vector3, _include_start: bool, walls: bool) -> bool:
	var path := to - from
	var length := path.length()
	var dir := path / length if length > 0.0001 else direction
	var space := get_world_3d().direct_space_state

	# Walls first: how far the bullet gets this step. Targets past that are behind the wall.
	var wall_at := INF
	if walls and length > 0.0001:
		wall_at = _first_wall(space, from, path, length)
	var reach := minf(length, wall_at)

	# Every target in the box over this step
	var r := target_radius
	var drop := from.y - floor_y                     # how far below the bullet still counts
	var bottom := (floor_y if drop > r else minf(from.y, to.y)) - r
	var top := maxf(from.y, to.y) + r
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	_box.size = Vector3(2.0 * r, top - bottom, reach + 2.0 * r)
	var centre := from + dir * reach * 0.5
	centre.y = (top + bottom) * 0.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _box
	q.collision_mask = hit_mask
	q.exclude = exclude
	q.transform = Transform3D(Basis.looking_at(flat.normalized(), Vector3.UP), centre)
	# Room for 32 results: the box also touches the floor and walls, which must not crowd
	# enemies out of the list.
	var found: Array = []                            # [metres along the path, collider, rid]
	for res in space.intersect_shape(q, 32):
		var c := res["collider"] as Node
		if not _is_target(c) or exclude.has(res["rid"]):
			continue
		var t := 0.0
		if c is Node3D:
			t = clampf(((c as Node3D).global_position - from).dot(dir), 0.0, reach)
		found.append([t, c, res["rid"]])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for f in found:
		var c: Node = f[1]
		if not is_instance_valid(c) or exclude.has(f[2]):
			continue
		var pos: Vector3 = from + dir * float(f[0])
		if not SkillTargets.line_is_clear(space, pos, c, f[2]):
			continue
		var at := pos                                # spark on the target, not in the air above it
		if c is Node3D:
			at.y = minf(pos.y, (c as Node3D).global_position.y + 0.6)
		if _hit(c, f[2], at):
			return true

	if wall_at < INF:
		var stop := from + dir * wall_at
		hit_world.emit(stop)
		_finish(stop)
		return true
	return false


## Metres along `path` to the first wall the bullet touches (INF = none). Only the world layer can
## stop a bullet; barrels sit on it too but are targets, so they're skipped and the sweep goes on.
func _first_wall(space: PhysicsDirectSpaceState3D, from: Vector3, path: Vector3, length: float) -> float:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _wall_shape
	q.collision_mask = hit_mask & SkillTargets.WORLD_LAYER_MASK
	var skip: Array[RID] = exclude.duplicate()
	for i in 4:                                      # a few barrels in a row at most
		q.exclude = skip
		q.transform = Transform3D(Basis.IDENTITY, from)
		q.motion = path
		var frac := space.cast_motion(q)
		if frac[1] >= 1.0:
			return INF
		q.transform = Transform3D(Basis.IDENTITY, from + path * frac[1])
		q.motion = Vector3.ZERO
		var info := space.get_rest_info(q)
		if info.is_empty():
			return frac[1] * length
		var c := instance_from_id(info["collider_id"]) as Node
		if not _is_target(c):
			return frac[1] * length
		skip.append(info["rid"])
	return INF


func _is_target(collider: Node) -> bool:
	return collider != null and (collider.is_in_group(enemy_group) \
			or (enemy_group == &"enemies" and collider.is_in_group(&"breakables")))


## Reports one target. True when the bullet stops there (out of pierce).
func _hit(collider: Node, rid: RID, pos: Vector3) -> bool:
	exclude.append(rid)                                # never hit the same enemy twice
	hit_enemy.emit(collider, pos, _pierced)
	if _pierced >= pierce:
		_finish(pos)
		return true
	_pierced += 1
	return false


## Metres flown so far.
func travelled() -> float:
	return _travelled


func _finish(at: Vector3) -> void:
	_done = true
	global_position = at
	queue_free()
