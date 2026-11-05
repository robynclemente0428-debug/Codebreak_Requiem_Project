class_name WardBeacon
extends Area3D
## A ward beacon, one per middle district (DungeonPopulator.ward_beacon_id). It stands dark and
## flickering until the player reboots it, then comes back online (QuestManager.recover) and
## stays lit for good, in every instance of that district. The WARD BEACONS quests ask for
## them; rebooting one before taking the quest still counts.
## The reboot is a fight:
##   1. Touching the beacon starts it. It boots over boot_time seconds, but only while the
##      player stands inside the ring on the floor (hold_radius); outside, booting stops.
##   2. The Null come for it in waves: the district's own enemies, from the floor around it.
##   3. Booted, and the last of those waves down: the beacon is lit.
## Dying calls it off: the waves leave and it starts over from 0 next time.
## Not solid and not in the navmesh: enemies and the player walk right through it.
## A wave event (DungeonPopulator.WAVE_EVENTS): its area only counts as cleared once it is lit.

## Emitted once it is lit (see DungeonPopulator.WAVE_EVENTS).
signal wave_event_finished

const COL_DARK := Color(0.45, 0.20, 0.75)
const COL_LIT := Color(0.0, 0.90, 1.0)
const COL_WARN := Color(1.0, 0.35, 0.35)
const COL_GOOD := Color(0.25, 1.0, 0.55)
const REACH := 1.6
const FONT_PATH := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const READOUT_WIDTH := 260.0
const READOUT_HEIGHT := 2.7                # metres: where the readout sits over the beacon

@export var boot_time := 20.0
@export var hold_radius := 7.0
@export var wave_every := 6.0
@export var wave_sizes: Array[int] = [8, 13, 18]
## Every wave is tougher than the last, like DockDefense: wave n gets +100 x n health and
## armour (flat, on the base), then +25% x n of both, and +12% damage per wave after the first.
## All on top of the dungeon's level.
@export var wave_health_flat := 100.0
@export var wave_armour_flat := 100.0
@export var wave_health_growth := 0.25
@export var wave_armour_growth := 0.25
@export var wave_damage_growth := 0.12
## Where waves come from: floor this far from the beacon (metres).
@export var spawn_min := 8.0
@export var spawn_max := 13.0

enum State { DARK, BOOTING, CLEARING, LIT }
var state := State.DARK
var progress := 0.0                        # 0..1, the reboot

var beacon_id := ""
var _lit := false
var _core_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _core: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0
var _zone: MeshInstance3D                  # the ring on the floor you hold
var _zone_mat: StandardMaterial3D
var _readout: CanvasLayer
var _status: Label
var _bar: ProgressBar
var _wave := 0
var _next_wave := 0.0
var _alive: Array[Node3D] = []
var _spawn_points: Array[Vector3] = []


static func spawn(parent: Node, pos: Vector3, id: String) -> WardBeacon:
	var b := WardBeacon.new()
	b.beacon_id = id
	b.name = "WardBeacon"
	parent.add_child(b)
	b.global_position = pos
	return b


func is_lit() -> bool:
	return _lit


## Lit (now, or on an earlier visit): no waves left to fight here.
func wave_event_done() -> bool:
	return _lit


## What the "area not cleared yet" message calls it.
func wave_event_label() -> String:
	return "reboot %s" % QuestItems.name_of(beacon_id).to_upper()


func is_rebooting() -> bool:
	return state == State.BOOTING or state == State.CLEARING


func _ready() -> void:
	add_to_group("ward_beacons")               # the minimap rings it while a quest wants it
	add_to_group(DungeonPopulator.WAVE_EVENTS)
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
	if _lit:
		state = State.LIT


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
	# The hold zone: a thin ring on the floor, shown only while rebooting
	_zone_mat = StandardMaterial3D.new()
	_zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_mat.albedo_color = Color(COL_LIT, 0.5)
	var zone_mesh := TorusMesh.new()
	zone_mesh.inner_radius = hold_radius - 0.45   # wide enough to survive the low-res view
	zone_mesh.outer_radius = hold_radius
	zone_mesh.rings = 64
	zone_mesh.ring_segments = 4
	zone_mesh.material = _zone_mat
	_zone = MeshInstance3D.new()
	_zone.mesh = zone_mesh
	_zone.scale.y = 0.1
	_zone.position.y = 0.06
	_zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone.visible = false
	add_child(_zone)
	_build_readout()


## REBOOTING 42% and a boot bar over the beacon. Drawn as 2D on the game window, like the NPC
## name plates, so it stays sharp (the world renders at a third of the resolution).
func _build_readout() -> void:
	_readout = CanvasLayer.new()
	_readout.layer = 5                         # with the name plates: under the HUD
	_readout.visible = false
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	box.custom_minimum_size.x = READOUT_WIDTH
	_readout.add_child(box)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	if ResourceLoader.exists(FONT_PATH):
		_status.add_theme_font_override("font", load(FONT_PATH))
	box.add_child(_status)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(READOUT_WIDTH, 8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_LIT
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.01, 0.03, 0.05, 0.85)
	back.border_color = Color(COL_LIT, 0.5)
	back.set_border_width_all(1)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	box.add_child(_bar)
	get_tree().root.add_child.call_deferred(_readout)


func _exit_tree() -> void:
	if is_instance_valid(_readout):
		_readout.queue_free()


func _show_readout(on: bool) -> void:
	_zone.visible = on
	_readout.visible = on


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
	if is_rebooting():
		_run(delta)
	_core.rotation.y = _t * (1.5 if _lit else 0.4 + progress * 2.0)
	if _lit:
		_core.position.y = 1.9 + sin(_t * 2.0) * 0.06
	else:
		# Dark beacons flicker like a dying signal; booting ones warm up towards cyan
		var flick := 0.6 + 0.4 * absf(sin(_t * 7.0) * sin(_t * 2.3))
		var col := COL_DARK.lerp(COL_LIT, progress * 0.8)
		for m in [_core_mat, _ring_mat]:
			m.albedo_color = col
			m.emission = col
		_light.light_color = col
		_light.light_energy = lerpf(0.6 * flick, 1.6, progress)
		_core_mat.emission_energy_multiplier = lerpf(1.2 * flick, 2.6, progress)


func _on_body_entered(body: Node3D) -> void:
	if state != State.DARK or not body.is_in_group("players") or body.get("quests") == null:
		return
	_start(body)


# ---------- THE REBOOT ----------
## The dungeon the populator put us in: its grid, enemy pool and level.
func _dungeon() -> Node:
	return get_parent()


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


func _start(player: Node3D) -> void:
	state = State.BOOTING
	progress = 0.0
	_wave = 0
	_next_wave = 1.5                         # a breath before the first wave
	_collect_spawn_points()
	var hp := player.get("health") as HealthComponent
	if hp != null and not hp.died.is_connected(_on_player_died):
		hp.died.connect(_on_player_died)
	_show_readout(true)
	QuestItems.toast(get_tree(), "REBOOTING THE %s\nStay in the ring while it boots. The Null will come for it."
			% QuestItems.name_of(beacon_id), COL_WARN)


## Floor around the beacon, spawn_min..spawn_max metres away, for the waves to come from.
func _collect_spawn_points() -> void:
	_spawn_points.clear()
	var d := _dungeon()
	var gm = d.get("grid_map")
	if not gm is GridMap or not d.has_method("_is_floor"):
		return
	for c: Vector3i in (gm as GridMap).get_used_cells():
		if c.y != 0 or not d._is_floor(c):
			continue
		var at: Vector3 = d._grid_to_world(Vector2i(c.x, c.z))
		var dist := Vector2(at.x - global_position.x, at.z - global_position.z).length()
		if dist >= spawn_min and dist <= spawn_max:
			_spawn_points.append(at)


func _run(delta: float) -> void:
	_alive.assign(_alive.filter(func(e) -> bool: return is_instance_valid(e) and e.is_in_group("enemies")))
	var player := _player()
	if player == null:
		return
	var flat := player.global_position - global_position
	flat.y = 0.0
	var holding := flat.length() <= hold_radius
	if state == State.BOOTING:
		if holding:
			progress = minf(progress + delta / boot_time, 1.0)
		_next_wave -= delta
		if _next_wave <= 0.0 and _wave < wave_sizes.size():
			_spawn_wave()
			_next_wave = wave_every
		if progress >= 1.0:
			state = State.CLEARING
	if state == State.CLEARING and _alive.is_empty() and _wave >= wave_sizes.size():
		_finish()
		return
	_update_status(holding)


func _spawn_wave() -> void:
	var d := _dungeon()
	var director = d.get("director")
	var pool: Array = director.dungeon_theme.enemy_pool if director != null else []
	var root := d.get_node_or_null("Enemies")      # the minimap counts these as hostiles
	var count := wave_sizes[_wave]
	_wave += 1
	if _spawn_points.is_empty() or pool.is_empty() or root == null:
		return
	var level := int(d.get("dungeon_level")) if d.get("dungeon_level") != null else 1
	for i in count:
		var at: Vector3 = _spawn_points[randi() % _spawn_points.size()] + Vector3.UP * 0.1
		# The last wave brings a magic one
		var rarity := "magic" if i % 4 == 0 and _wave >= 2 else "normal"
		var def := EnemyDefinition.pick(pool, rarity)
		if def == null:
			continue
		var e := EnemySpawner.spawn_enemy(def, rarity, root, at, level, [])
		if e == null:
			continue
		var grow := float(_wave)                 # this is wave `grow`, counting from 1
		EnemySpawner.empower(e, wave_health_growth * grow, wave_armour_growth * grow,
				wave_damage_growth * (grow - 1.0), "wave", wave_health_flat * grow, wave_armour_flat * grow)
		e.ai.aggro_range = spawn_max * 3.0          # they all come for the beacon
		_alive.append(e)
		var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
		if numbers:
			numbers.track(e.health)


func _finish() -> void:
	state = State.LIT
	_show_readout(false)
	var player := _player()
	var qm = player.get("quests") if player != null else null
	if qm != null:
		qm.recover(beacon_id)
	_set_lit(true, true)
	QuestItems.toast(get_tree(), "%s ONLINE\nThe ward holds here again." % QuestItems.name_of(beacon_id), COL_GOOD)
	wave_event_finished.emit()


## Dying calls it off: the Null leave, and it boots from 0 next time.
func _on_player_died() -> void:
	if not is_rebooting():
		return
	for e in _alive:
		if is_instance_valid(e):
			e.queue_free()
	_alive.clear()
	state = State.DARK
	progress = 0.0
	_show_readout(false)


func _update_status(holding: bool) -> void:
	var pct := roundi(progress * 100.0)
	_bar.value = progress
	var pr: Dictionary = NpcNameplates.project(global_position + Vector3.UP * READOUT_HEIGHT)
	if not pr.is_empty():
		var box := _status.get_parent() as Control
		box.position = (pr.pos - Vector2(box.size.x * 0.5, box.size.y)).round()
		box.visible = not pr.behind
	if state == State.CLEARING:
		_status.text = "BOOTED. CLEAR THE NULL: %d" % _alive.size()
		_status.add_theme_color_override("font_color", COL_GOOD)
	elif not holding:
		_status.text = "RETURN TO THE RING  %d%%" % pct
		_status.add_theme_color_override("font_color", COL_WARN)
	else:
		_status.text = "REBOOTING  %d%%   WAVE %d/%d" % [pct, _wave, wave_sizes.size()]
		_status.add_theme_color_override("font_color", Color(0.85, 0.96, 1.0))
	# The ring pulses, and turns red while you're outside it
	var a := 0.22 + 0.18 * absf(sin(_t * 3.0))
	_zone_mat.albedo_color = Color(COL_WARN if not holding and state == State.BOOTING else COL_LIT, a)
