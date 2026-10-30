class_name ShootProjectile
extends Node3D
## A fast bullet. It sweeps its whole path every physics frame so it can't tunnel through
## enemies, reports each enemy it passes through, and stops on world geometry or once it has
## used up its pierce. It does no damage itself: ShootBehavior listens to `hit_enemy`.

## pierced_so_far is 0 for the first enemy hit, 1 for the second, and so on.
signal hit_enemy(target: Node, position: Vector3, pierced_so_far: int)
signal hit_world(position: Vector3)

## Physics layers it collides with: world (layer 1) + enemies (layer 3) by default.
@export_flags_3d_physics var hit_mask: int = 5
@export var hit_radius: float = 0.15
@export var enemy_group: StringName = &"enemies"

var direction := Vector3.FORWARD
var speed := 60.0
var max_distance := 30.0
## Extra enemies it can pass through. 0 = stops at the first enemy it hits.
var pierce := 0
var exclude: Array[RID] = []
## Height the hit check reaches down to (world y). The bullet flies at the gun's height, which is
## above barrels and small enemies, so anything under its path down to here counts as hit.
## Walls are still only checked at the bullet itself. INF = only the bullet itself.
var floor_y := INF

var _travelled := 0.0
var _pierced := 0
var _done := false
var _shape := SphereShape3D.new()
var _column := CapsuleShape3D.new()      # from the bullet down to floor_y


func _ready() -> void:
	_shape.radius = hit_radius
	_column.radius = hit_radius
	look_at(global_position + direction, Vector3.UP)     # point the tracer along its flight


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := minf(speed * delta, max_distance - _travelled)
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.collision_mask = hit_mask
	var drop := global_position.y - floor_y          # how far below the bullet still counts
	var column: PhysicsShapeQueryParameters3D = null
	if drop > hit_radius:
		_column.height = drop + 2.0 * hit_radius
		column = PhysicsShapeQueryParameters3D.new()
		column.shape = _column
		column.collision_mask = hit_mask

	# Test a point every hit_radius along this frame's path, so a fast bullet can't skip an enemy.
	var samples := maxi(ceili(step / hit_radius), 1)
	for i in samples:
		var pos := global_position + direction * step * float(i + 1) / float(samples)
		# Enemies (and barrels) first, anywhere in the column under the bullet
		if column != null:
			column.transform = Transform3D(Basis.IDENTITY, pos + Vector3.DOWN * drop * 0.5)
			column.exclude = exclude
			for r in space.intersect_shape(column, 8):
				var c := r["collider"] as Node
				if _is_target(c) and not exclude.has(r["rid"]):
					var at := pos                       # spark on the target, not in the air above it
					if c is Node3D:
						at.y = minf(pos.y, (c as Node3D).global_position.y + 0.6)
					if _hit(c, r["rid"], at):
						return
		# Then the bullet itself: enemies at its height, and walls (always stop it)
		query.transform = Transform3D(Basis.IDENTITY, pos)
		query.exclude = exclude
		for r in space.intersect_shape(query, 8):
			var collider := r["collider"] as Node
			if _is_target(collider):
				if _hit(collider, r["rid"], pos):
					return
			else:
				hit_world.emit(pos)                    # walls always stop it
				_finish(pos)
				return

	global_position += direction * step
	_travelled += step
	if _travelled >= max_distance:
		_finish(global_position)


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
