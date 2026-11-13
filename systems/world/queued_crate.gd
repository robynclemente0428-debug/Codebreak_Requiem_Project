class_name QueuedCrate
extends Area3D
## A crate a Yard Sweep deleted, waiting in C-0's deletion queue inside the Sweep (YardCrates).
## DungeonPopulator.place_queued_crates puts one in a room off the way for each crate still queued,
## until the Collector falls. Walk into it to send it back to the yard: the deed
## "crate_restored:<crate>", and the crate is back on the yard's floor next time you're there.
## Built in code: QueuedCrate.spawn().

const PICK_RADIUS := 1.4

var crate_id := ""
var _box: MeshInstance3D
var _t := 0.0
var _taken := false


static func spawn(parent: Node, pos: Vector3, p_crate_id: String) -> QueuedCrate:
	var c := QueuedCrate.new()
	c.crate_id = p_crate_id
	c.name = "Queued_" + p_crate_id
	parent.add_child(c)
	c.global_position = pos
	return c


func _ready() -> void:
	collision_layer = 0
	collision_mask = 3                         # the player's body (as portals and keys)
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICK_RADIUS
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)
	var col := YardCrates.COL

	# The crate, dark, inside a cage of red bars: it's queued for the furnace
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.18, 0.17)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.25
	_box = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.75, 0.8)
	_box.mesh = box
	_box.material_override = mat
	_box.position.y = 0.38
	add_child(_box)
	var bar_mat := StandardMaterial3D.new()
	bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar_mat.albedo_color = col * 2.0                 # over 1: the glow picks it up
	for x in [-0.65, -0.22, 0.22, 0.65]:
		for z in [-0.55, 0.55]:
			var bar := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.05, 1.5, 0.05)
			bar.mesh = bm
			bar.material_override = bar_mat
			bar.position = Vector3(x, 0.75, z)
			add_child(bar)
	for y in [0.02, 1.5]:
		var rim := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(1.4, 0.05, 1.15)
		rim.mesh = rm
		rim.material_override = bar_mat
		rim.position.y = y
		add_child(rim)

	var plate := Label3D.new()
	plate.text = "DELETION QUEUE\n%s" % YardCrates.name_of(crate_id)
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.no_depth_test = true
	plate.pixel_size = 0.005
	plate.font_size = 36
	plate.outline_size = 8
	plate.modulate = col
	plate.position.y = 2.1
	add_child(plate)

	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.35
	cyl.height = 5.0
	beam.mesh = cyl
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(col, 0.16)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = beam_mat
	beam.position.y = 2.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)


func _process(delta: float) -> void:
	_t += delta
	if _box != null:
		var m := _box.material_override as StandardMaterial3D
		m.emission_energy_multiplier = 0.2 + 0.3 * (0.5 + 0.5 * sin(_t * 4.0))


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("players"):
		return
	var qm := body.get("quests") as QuestManager
	if not YardCrates.is_queued(qm, crate_id):
		return
	_taken = true
	GameEvents.report(YardCrates.RESTORED, crate_id)
	QuestItems.toast(get_tree(), "PULLED FROM THE DELETION QUEUE\n%s goes back to the yard, and back to %s." % [
		YardCrates.name_of(crate_id), YardCrates.owner_of(crate_id)], Color(0.45, 1.0, 0.6))
	SoundManager.play_ui("res://assets/sound/Start_Button_Click.wav", -4.0)
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ONE * 0.05, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)
