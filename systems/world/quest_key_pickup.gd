class_name QuestKeyPickup
extends Area3D
## A quest key lying where its carrier fell: a spinning gold shard with a beam of light over
## it, so it's easy to spot after a fight. Walking into it picks it up (QuestManager.recover),
## which opens the portal it unlocks. Built in code, no scene needed: QuestKeyPickup.spawn().

const COL := Color(1.0, 0.82, 0.30)
const PICK_RADIUS := 1.2

var key_id := ""
var _shard: MeshInstance3D
var _t := 0.0


static func spawn(parent: Node, pos: Vector3, id: String) -> QuestKeyPickup:
	var k := QuestKeyPickup.new()
	k.key_id = id
	k.name = "Key_" + id
	parent.add_child(k)
	k.global_position = pos
	return k


func _ready() -> void:
	add_to_group("quest_pickups")              # the minimap rings it while a quest wants it
	collision_layer = 0
	collision_mask = 3                         # finds the player's body (same as portals and NPCs)
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICK_RADIUS
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COL
	mat.emission_enabled = true
	mat.emission = COL
	mat.emission_energy_multiplier = 3.0
	var mesh := SphereMesh.new()               # 4 sides, 2 rings: an octahedron, the "shard"
	mesh.radius = 0.22
	mesh.height = 0.6
	mesh.radial_segments = 4
	mesh.rings = 2
	mesh.material = mat
	_shard = MeshInstance3D.new()
	_shard.mesh = mesh
	_shard.position.y = 0.9
	_shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shard)

	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(COL, 0.35)
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.05
	beam_mesh.bottom_radius = 0.25
	beam_mesh.height = 4.0
	beam_mesh.material = beam_mat
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.position.y = 2.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	var light := OmniLight3D.new()
	light.light_color = COL
	light.light_energy = 1.5
	light.omni_range = 3.0
	light.position.y = 1.0
	add_child(light)


func _process(delta: float) -> void:
	_t += delta
	_shard.rotation.y = _t * 2.0
	_shard.position.y = 0.9 + sin(_t * 3.0) * 0.1


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("players"):
		return
	var qm = body.get("quests")
	if qm == null:
		return
	qm.recover(key_id)
	queue_free()
