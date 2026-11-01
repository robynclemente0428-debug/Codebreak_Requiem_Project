class_name WardBeacon
extends Area3D
## A ward beacon, one per middle district (DungeonPopulator.ward_beacon_id). It stands dark and
## flickering until the player reaches it, then comes back online (QuestManager.recover) and
## stays lit for good, in every instance of that district. The WARD BEACONS quests ask for
## them; reaching one before taking the quest still counts.
## Not solid and not in the navmesh: enemies and the player walk right through it.

const COL_DARK := Color(0.45, 0.20, 0.75)
const COL_LIT := Color(0.0, 0.90, 1.0)
const REACH := 1.6

var beacon_id := ""
var _lit := false
var _core_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _core: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0


static func spawn(parent: Node, pos: Vector3, id: String) -> WardBeacon:
	var b := WardBeacon.new()
	b.beacon_id = id
	b.name = "WardBeacon"
	parent.add_child(b)
	b.global_position = pos
	return b


func is_lit() -> bool:
	return _lit


func _ready() -> void:
	add_to_group("ward_beacons")               # the minimap rings it while a quest wants it
	collision_layer = 0
	collision_mask = 3                         # finds the player's body (same as portals and NPCs)
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = REACH
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_build()
	_set_lit(QuestItems.owned(get_tree(), beacon_id), false)


func _build() -> void:
	# Base: a squat dark plinth
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.08, 0.09, 0.12)
	base_mat.metallic = 0.6
	base_mat.roughness = 0.4
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.35
	base_mesh.bottom_radius = 0.5
	base_mesh.height = 0.3
	base_mesh.radial_segments = 6
	base_mesh.material = base_mat
	var base := MeshInstance3D.new()
	base.mesh = base_mesh
	base.position.y = 0.15
	add_child(base)
	# Mast
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.06
	mast_mesh.bottom_radius = 0.12
	mast_mesh.height = 1.3
	mast_mesh.radial_segments = 6
	mast_mesh.material = base_mat
	var mast := MeshInstance3D.new()
	mast.mesh = mast_mesh
	mast.position.y = 0.95
	add_child(mast)
	# Glowing ring on the plinth
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.emission_enabled = true
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.42
	ring_mesh.outer_radius = 0.5
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 6
	ring_mesh.material = _ring_mat
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.position.y = 0.31
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# Core: a floating octahedron over the mast
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.emission_enabled = true
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.2
	core_mesh.height = 0.5
	core_mesh.radial_segments = 4
	core_mesh.rings = 2
	core_mesh.material = _core_mat
	_core = MeshInstance3D.new()
	_core.mesh = core_mesh
	_core.position.y = 1.9
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	_light = OmniLight3D.new()
	_light.position.y = 1.8
	_light.omni_range = 4.0
	add_child(_light)


func _set_lit(on: bool, announce: bool) -> void:
	_lit = on
	var col := COL_LIT if on else COL_DARK
	for m in [_core_mat, _ring_mat]:
		m.albedo_color = col
		m.emission = col
		m.emission_energy_multiplier = 3.0 if on else 1.2
	_light.light_color = col
	_light.light_energy = 2.0 if on else 0.6
	if on and announce:
		var flash := create_tween()
		_core.scale = Vector3.ONE * 2.0
		flash.tween_property(_core, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK)


func _process(delta: float) -> void:
	_t += delta
	_core.rotation.y = _t * (1.5 if _lit else 0.4)
	if _lit:
		_core.position.y = 1.9 + sin(_t * 2.0) * 0.06
	else:
		# Dark beacons flicker like a dying signal
		var flick := 0.6 + 0.4 * absf(sin(_t * 7.0) * sin(_t * 2.3))
		_light.light_energy = 0.6 * flick
		_core_mat.emission_energy_multiplier = 1.2 * flick


func _on_body_entered(body: Node3D) -> void:
	if _lit or not body.is_in_group("players"):
		return
	var qm = body.get("quests")
	if qm == null:
		return
	qm.recover(beacon_id)
	_set_lit(true, true)
