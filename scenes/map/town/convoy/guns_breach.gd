class_name GunsBreach
extends HullBreach
## THE LAST MILE's breach (q04c_the_last_mile): Checkpoint's perimeter guns open fire on the
## convoy as it closes in, and the Null board in the chaos. Unlike a road breach it isn't owed
## for a finished stop: it's due while the quest is on and its held_key isn't recovered yet, so
## it starts a few seconds after Brack's dialogue that gave the quest closes.
##   1. The first salvo knocks out the IFF TRANSPONDER (a DeckSystem the Null leave alone):
##      whatever the player does, Checkpoint reads the convoy as Null.
##   2. Hold the route terminal and clear the deck like any breach (HullBreach): held_key
##      ("checkpoint_guns_held") is recovered, the quest's first step.
##   3. The guns keep firing near misses until the IFF is patched (PatchPanel's iff.prog, whose
##      registry shows the two Hardfault records). The patch recovers "iff_patched"
##      (DeckSystem.recovers_on_repair), and Checkpoint Approach opens on the route terminal.
## The guns are only show: tracers out of the void ahead and a flash where they land.

## The system the first salvo takes out.
@export var knock_out_id := "iff"
## The step that silences the guns (the IFF's patch).
@export var silenced_by := "iff_patched"
## Seconds between salvos, and tracers per salvo.
@export var salvo_every := Vector2(1.4, 3.0)
@export var salvo_size := Vector2i(2, 4)
## Where the guns are, from the deck: ahead of the bow and above (metres).
@export var gun_offset := Vector3(90, 34, 0)
## Tracers land within this many metres of the route terminal.
@export var spread := Vector2(16, 9)
@export_multiline var knocked_text := "CHECKPOINT IS FIRING ON US\nThe first salvo hit the IFF Transponder: their guns read the convoy as Null."
@export_multiline var silenced_text := "THE GUNS HOLD FIRE\nCheckpoint reads us as INBOUND. Set course for Checkpoint Approach on the route terminal."

const COL_TRACER := Color(1.0, 0.45, 0.15)
const COL_FLASH := Color(1.0, 0.6, 0.3)

var _salvo_wait := 0.0
var _hooked_iff := false


func _ready() -> void:
	super._ready()
	_hook_iff.call_deferred()


## Due while the quest is on and the deck hasn't been held yet: no stop to finish first.
func is_due() -> bool:
	var qm := _qm()
	return qm != null and qm.is_active(quest_id) and not qm.has_recovered(held_key)


func _start() -> void:
	super._start()
	var iff = _system(knock_out_id)
	if iff != null and iff.is_online():
		iff.knock_out()
		QuestItems.toast(get_tree(), knocked_text, COL_WARN)
	_salvo_wait = 0.6                                  # the first salvo lands as they board


func _held() -> void:
	super._held()
	var qm := _qm()
	if qm != null:
		qm.recover(held_key)                           # the quest's first step


func _process(delta: float) -> void:
	super._process(delta)
	if not _guns_firing():
		return
	_salvo_wait -= delta
	if _salvo_wait > 0.0:
		return
	_salvo_wait = randf_range(salvo_every.x, salvo_every.y)
	for i in randi_range(salvo_size.x, salvo_size.y):
		get_tree().create_timer(i * 0.12).timeout.connect(_fire_tracer)


## From the boarding until the IFF is patched.
func _guns_firing() -> bool:
	var qm := _qm()
	if qm == null or not qm.is_active(quest_id) or qm.has_recovered(silenced_by):
		return false
	return is_running() or qm.has_recovered(held_key)


func _hook_iff() -> void:
	if _hooked_iff:
		return
	var iff = _system(knock_out_id)
	if iff == null:
		return
	_hooked_iff = true
	iff.repaired.connect(func(_s) -> void:
		var qm := _qm()
		if qm != null and qm.is_active(quest_id):
			QuestItems.toast(get_tree(), silenced_text, COL_GOOD))


# ---------- THE GUNS ----------
func _fire_tracer() -> void:
	if not is_inside_tree():
		return
	var anchor := _find_portal()                       # the route terminal: the middle of the deck
	if anchor == null:
		return
	# Offsets are in the deck's own space (the Map node holding the area may be turned)
	var deck := (get_parent() as Node3D).global_basis
	var land := anchor.global_position + deck * Vector3(randf_range(-spread.x, spread.x), 0.0,
			randf_range(-spread.y, spread.y))
	land.y = anchor.global_position.y - 0.9            # the deck under the terminal
	var from := land + deck * (gun_offset + Vector3(0, randf_range(-6, 6), randf_range(-25, 25)))
	var dir := (land - from).normalized()
	var length := 7.0
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, length)
	tracer.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COL_TRACER
	mat.emission_enabled = true
	mat.emission = COL_TRACER
	mat.emission_energy_multiplier = 4.0
	tracer.material_override = mat
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(tracer)
	tracer.global_position = from
	tracer.look_at(land, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var time := from.distance_to(land) / 140.0
	var tw := tracer.create_tween()
	tw.tween_property(tracer, "global_position", land - dir * length * 0.5, time)
	tw.tween_callback(func() -> void:
		tracer.queue_free()
		_flash(land))


## Where a round lands: a burst of light and a puff that grows and fades.
func _flash(at: Vector3) -> void:
	if not is_inside_tree():
		return
	var root := Node3D.new()
	get_parent().add_child(root)
	root.global_position = at + Vector3.UP * 0.3
	var light := OmniLight3D.new()
	light.light_color = COL_FLASH
	light.light_energy = 5.0
	light.omni_range = 6.0
	root.add_child(light)
	var puff := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	puff.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(COL_FLASH, 0.8)
	puff.material_override = mat
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(puff)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.tween_property(puff, "scale", Vector3.ONE * 2.6, 0.35)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(root.queue_free)
