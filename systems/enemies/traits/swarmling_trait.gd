extends EnemyTrait
## SWARMLING: a smaller, weaker copy (the modifier multiplies its health by 0.5 and damage by
## 0.6, after its other modifiers, so it can never stack below zero). A swarm
## dungeon spawns twice as many enemies, so area skills (blast spread, hits that splash) win.

## Model and body size, on top of the rarity's size.
@export var size := 0.75


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	var mount := enemy.get("model_mount") as Node3D
	if mount != null:
		mount.scale *= size
	var body := enemy.get("collision") as CollisionShape3D
	if body != null and body.shape is CylinderShape3D and enemy.has_method("apply_size"):
		var shape := body.shape as CylinderShape3D
		enemy.apply_size(shape.radius * size, shape.height * size)
