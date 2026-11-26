extends "res://scenes/map/dungeon/dungeon.gd"
## One floor of The Recursion (Tower). A single scene for every floor: the instance's level is the
## FLOOR NUMBER, and its seed is the floor's saved roll, so before anything is generated this
## turns the floor into its real level (Tower.level_of) and puts on its look (Tower.theme_of_seed:
## a campaign DungeonTheme, its tiles and its enemy pool). Threats come with the instance
## (DungeonThreats.roll_for -> Tower.threats_of_seed).
##
## The exit is the portal you came in by, back to the Core's tower terminal. Clearing the floor
## (DungeonPopulator calls on_floor_cleared) reveals the next one.
##
## Floor TRIAL_FLOOR also opens the THEORIST TRIAL: a gold gate into Sudo's sandbox (ExamChamber,
## data/exams/theorist.tres). That floor gets a room of its own for it (TRIAL_ROOM_AT, added to
## the layout before it generates, past the far room). The gate opens in the middle of that room
## when the floor is cleared, and stands there on every later visit. Walking through starts the
## exam_theorist quest if it isn't started yet.

## This visit's floor, 1 to Tower.FLOORS.
var floor_number := 1
## A Null floor (MERGE) is stained this many times as much.
const NULL_DECALS := 4.0
const COL_NULL := Color(0.72, 0.42, 1.0)
## The floor with the Theorist trial's gate.
const TRIAL_FLOOR := 10
const TRIAL_RANK := "theorist"
const COL_TRIAL := Color(1.0, 0.82, 0.38)
## Where floor TRIAL_FLOOR's trial room goes (Layout space): south of the far room, away from
## the portal back to the Core.
const TRIAL_ROOM_AT := Vector3(180.0, 0.0, 160.0)
const TRIAL_ROOM_SIZE := Vector2i(9, 9)
var _trial_gate: Node3D
var _trial_marker: Node3D


func _announce_null() -> void:
	await get_tree().create_timer(1.2, false).timeout
	if is_inside_tree():
		QuestItems.toast(get_tree(), "NULL FLOOR\nThe Null built this one: %s.\n%s" % [
				DungeonThreats.label(Tower.null_extra(instance.rng_seed)) if Tower.null_extra(instance.rng_seed) != "" else "no new threat",
				Tower.rewards_line(instance.threats, true)], COL_NULL)


func _on_instance() -> void:
	floor_number = clampi(instance.level, 1, Tower.FLOORS)
	dungeon_level = Tower.level_of(floor_number)
	var theme := Tower.theme_of_seed(instance.rng_seed)
	if theme != null:
		director.dungeon_theme = theme
		grid_map.mesh_library = theme.mesh_library
	else:
		push_warning("TowerFloor: no theme for floor %d (seed %d)" % [floor_number, instance.rng_seed])
	if floor_number == TRIAL_FLOOR:
		_add_trial_room()
	var null_floor := Tower.is_null_floor(instance.rng_seed)
	populator.rewards = Tower.rewards_for(instance.threats, null_floor)   # what the threats pay (drops)
	if null_floor:
		null_decal_mult = NULL_DECALS
		_announce_null.call_deferred()
	var look := Tower.look_of_seed(instance.rng_seed)
	print("[Tower] floor %d: level %d, %s, threats %s (staked %s), pays: %s" % [floor_number, dungeon_level,
			look["name"], ", ".join(instance.threats), ", ".join(Tower.stakes_of_seed(instance.rng_seed)),
			Tower.rewards_line(instance.threats, null_floor)])


## Floor TRIAL_FLOOR: a room marker for the trial's gate, before the layout is read.
func _add_trial_room() -> void:
	var marker := RoomMarker.new()
	marker.name = "TrialRoom"
	marker.room_size = TRIAL_ROOM_SIZE
	$Layout.add_child(marker)
	marker.position = TRIAL_ROOM_AT
	_trial_marker = marker


## The middle of the trial room, on its floor.
func _trial_room_point() -> Vector3:
	if _trial_marker == null:
		return Vector3.INF
	var c3 := grid_map.local_to_map(grid_map.to_local(_trial_marker.global_position))
	var cell := Vector2i(c3.x, c3.z)
	if not _is_floor(Vector3i(cell.x, FLOOR_LAYER, cell.y)):
		cell = _nearby_floor(cell, 0, 4)
	return _grid_to_world(cell)


## AreaManager: the player is placed. A floor TRIAL_FLOOR already on the climb has its gate open.
func on_player_arrived(player: Node3D) -> void:
	if floor_number == TRIAL_FLOOR and Tower.is_cleared(TRIAL_FLOOR):
		_open_trial_gate(player, false)


## The Theorist trial's gate, a few steps in front of the player. Only for a character who
## holds Defragmenter (the rank below).
func _open_trial_gate(player: Node3D, announce: bool) -> void:
	if is_instance_valid(_trial_gate) or player == null:
		return
	var qm := player.get("quests") as QuestManager
	if qm == null or not qm.is_completed("exam_defragmenter"):
		return
	var at := _trial_room_point()
	if at == Vector3.INF:
		return
	_trial_gate = _TrialGate.new()
	_trial_gate.name = "TheoristTrialGate"
	add_child(_trial_gate)
	_trial_gate.global_position = at
	var mm := get_tree().get_first_node_in_group("minimap") as Minimap
	if mm != null:
		mm.add_gate(_trial_gate, "T", "THEORIST TRIAL", COL_TRIAL)   # a gold "T" badge
	if announce:
		QuestItems.toast(get_tree(), "THE THEORIST TRIAL IS OPEN\nA gold gate has opened in a room of its own, past the far end of floor %d." % TRIAL_FLOOR, COL_TRIAL)


## Every enemy is dead (DungeonPopulator._check_cleared): this character's climb moves up.
func on_floor_cleared() -> void:
	if bool(populator.rewards.get("bonus_rare", false)):          # PAGED pays a rare on clearing
		var player := get_tree().get_first_node_in_group("players") as Node3D
		if player != null:
			populator.drop_bonus_rare(player.global_position + player.global_basis.z * -1.2)
	var advanced := Tower.floor_cleared(floor_number)
	var title := "FLOOR %d" % floor_number
	var reward := ""
	if advanced and floor_number >= Tower.FLOORS:
		reward = "THE TOP OF THE RECURSION"
	elif advanced:
		reward = "FLOOR %d REVEALED: TAKE THE PORTAL BACK TO THE TERMINAL" % Tower.revealed()
	elif Tower.is_cleared(floor_number):
		reward = "CLEARED AGAIN: ITS NEXT RUN IS A NEW ROLL"
	else:
		reward = "NOT ON YOUR CLIMB YET: CLEAR FLOOR %d FIRST" % Tower.revealed()
	if advanced and floor_number % Tower.PATCH_EVERY == 0 and Tower._ending() == "overwrite":
		reward += "\n+1 PATCH  (%d / %d)" % [Tower.patches(), Tower.MAX_PATCHES]   # OVERWRITE
	AreaClearedBanner.announce(get_tree(), title, reward)
	if floor_number == TRIAL_FLOOR and Tower.is_cleared(TRIAL_FLOOR):
		_open_trial_gate(get_tree().get_first_node_in_group("players") as Node3D, true)


## The gold gate: [T] THEORIST TRIAL. Starts the quest if it isn't, then into the sandbox.
class _TrialGate extends Interactable:
	func _ready() -> void:
		prompt_text = "THEORIST TRIAL"
		prompt_height = 3.0
		face_player = false
		collision_layer = 0
		collision_mask = 3
		var s := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 2.0
		s.shape = sphere
		add_child(s)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = COL_TRIAL
		var ring := TorusMesh.new()
		ring.inner_radius = 1.1
		ring.outer_radius = 1.3
		ring.material = mat
		var vis := MeshInstance3D.new()
		vis.mesh = ring
		vis.rotation.x = PI * 0.5                 # stood upright, like a portal
		vis.position.y = 1.4
		add_child(vis)
		var core := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.1
		disc.bottom_radius = 1.1
		disc.height = 0.02
		var core_mat := StandardMaterial3D.new()
		core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		core_mat.albedo_color = Color(COL_TRIAL, 0.25)
		disc.material = core_mat
		core.mesh = disc
		core.rotation.x = PI * 0.5
		core.position.y = 1.4
		add_child(core)
		var light := OmniLight3D.new()
		light.light_color = COL_TRIAL
		light.light_energy = 2.0
		light.omni_range = 6.0
		light.position.y = 1.4
		add_child(light)
		super()

	func interact(player: Node3D) -> void:
		var qm := player.get("quests") as QuestManager if player != null else null
		if qm != null and not qm.is_active("exam_theorist") and not qm.is_completed("exam_theorist"):
			qm.start_by_id("exam_theorist")
		ExamChamber.enter(get_tree(), TRIAL_RANK)
