class_name SalvageCache
extends Area3D
## A convoy stop's salvage: one supply cache somewhere off the main path of each route stop
## (DungeonPopulator.place_salvage). Walk into it to recover it: credits, and the deed
## "salvage:<stop id>". Every cache recovered makes Hex's, the Armoursmith's and the Weaponsmith's random stock likelier to
## roll magic and rare (ShopNPC salvage_magic_per / salvage_rare_per). Once per stop: a stop
## whose cache is recovered doesn't place it again. Built in code: SalvageCache.spawn().

const COL := Color(1.0, 0.62, 0.22)
const PICK_RADIUS := 1.3
const DEED := "salvage"
const CREDITS := 60

var stop_id := ""
var _crate: MeshInstance3D
var _t := 0.0
var _taken := false


static func spawn(parent: Node, pos: Vector3, p_stop_id: String) -> SalvageCache:
	var c := SalvageCache.new()
	c.stop_id = p_stop_id
	c.name = "Salvage_" + p_stop_id
	parent.add_child(c)
	c.global_position = pos
	return c


## Caches recovered so far, over every stop (for the shops they improve).
static func recovered(qm: QuestManager) -> int:
	return ScriptBudget._deeds(qm, DEED).size() if qm != null else 0


## The number of convoy stops, for the "3/6" in the message.
static func total() -> int:
	var n := 0
	for act in Waypoints.acts():
		for w in act.waypoints:
			if Waypoints.is_convoy_stop(w):
				n += 1
	return n


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

	# A squat crate with glowing straps, and a beam of light over it so it's easy to find
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.2, 0.18)
	mat.emission_enabled = true
	mat.emission = COL
	mat.emission_energy_multiplier = 0.35
	_crate = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.7, 0.75)
	_crate.mesh = box
	_crate.material_override = mat
	_crate.position.y = 0.35
	add_child(_crate)
	var strap_mat := StandardMaterial3D.new()
	strap_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strap_mat.albedo_color = COL * 2.2                # over 1: the glow picks it up
	for x in [-0.28, 0.28]:
		var strap := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.08, 0.72, 0.78)
		strap.mesh = sm
		strap.material_override = strap_mat
		strap.position = Vector3(x, 0.35, 0.0)
		add_child(strap)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.3
	cyl.height = 5.0
	beam.mesh = cyl
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(COL, 0.18)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = beam_mat
	beam.position.y = 2.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)


func _process(delta: float) -> void:
	_t += delta
	if _crate != null:
		var m := _crate.material_override as StandardMaterial3D
		m.emission_energy_multiplier = 0.3 + 0.25 * (0.5 + 0.5 * sin(_t * 3.0))


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("players"):
		return
	_taken = true
	var qm := body.get("quests") as QuestManager
	GameEvents.report(DEED, stop_id)
	var wallet := body.get("currency") as CurrencyComponent
	if wallet != null:
		wallet.add(CREDITS)
	var n := recovered(qm)
	QuestItems.toast(get_tree(), "SALVAGE RECOVERED  %d/%d\n+%d CREDITS  //  Hex and the smiths restock better" % [
		n, total(), CREDITS], COL)
	SoundManager.play_ui("res://assets/sound/Start_Button_Click.wav", -4.0)
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ONE * 0.05, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)
