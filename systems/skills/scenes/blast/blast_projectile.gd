class_name BlastProjectile
extends Node3D
## Flies in a straight line and reports where it hit. It does no damage itself:
## BlastBehavior listens to `impacted` and handles the explosion.

signal impacted(position: Vector3)

## Physics layers it explodes on: world (layer 1) + enemies (layer 3) by default.
@export_flags_3d_physics var hit_mask: int = 5
@export var hit_radius: float = 0.35
## true = the projectile wears the orb's own animated shader. false = a plain glowing ball.
@export var use_orb_shader: bool = true


var direction := Vector3.FORWARD
var speed := 14.0
var max_distance := 20.0
var exclude: Array[RID] = []

var _travelled := 0.0
var _done := false
var _shape := SphereShape3D.new()

func _ready() -> void:
	_shape.radius = hit_radius

func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := speed * delta
	var next := global_position + direction * step

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, next)
	query.collision_mask = hit_mask
	query.exclude = exclude
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		_explode(next)
		return

	global_position = next
	_travelled += step
	if _travelled >= max_distance:
		_explode(global_position)               # fizzles out at the end of its range

func _explode(at: Vector3) -> void:
	_done = true
	impacted.emit(at)
	queue_free()

func apply_style(style: Dictionary) -> void:
	var mesh_node := get_node_or_null("MeshInstance3D") as MeshInstance3D
	var light := get_node_or_null("OmniLight3D") as OmniLight3D
	var orb_mat = style.get("material")
	if mesh_node != null:
		if use_orb_shader and orb_mat is ShaderMaterial:
			mesh_node.material_override = (orb_mat as ShaderMaterial).duplicate()
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = style["primary"]
			mat.emission_enabled = true
			mat.emission = style["primary"]
			mat.emission_energy_multiplier = 4.0
			mesh_node.material_override = mat
	if light != null:
		light.light_color = style["secondary"]
