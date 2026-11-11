class_name DockDefense
extends Node3D
## A hold-the-portal fight for THE ROAD OUT. Put it in a TownArea. It finds the portal leading
## to dock_target and fights there. Two of them make the way out of Act I:
##   Hardfault: the Null break in as the outpost leaves. Everyone runs for the portal to the
##              dock (evacuate_npcs) while you hold it: held_key "outpost_evacuated".
##   The dock:  hold the convoy's gangway while it loads: held_key "dock_held".
##
##   1. With the quest active, after_key recovered and held_key not yet, walking up to the
##      portal starts it. With start_anywhere (Hardfault) it starts straight away, wherever
##      the player is: once the dialogue that gave the quest closes, or on arrival.
##   2. Progress runs over load_time seconds, but only while you stay at the portal: wander
##      off and it stops (away_text). Null waves come in from the floor around it.
##   3. Done, and the last Null down: QuestManager.recover(held_key), which opens the sealed
##      portal and completes that step of the quest.
## Dying calls it off: everything resets (the townsfolk back at their posts), and it starts
## again when you come back.
## Towns have no navmesh (no enemies), so the area's is baked when the fight starts: the tiles
## and furniture as before, plus the NPCs and anything else standing on the floor, so paths go
## round them, with room for the biggest boarders (NAV_CLEARANCE).
##
## Keeping the Null moving, quietly:
##   - waves only come from floor that is on the navmesh and has a path to the fight (a cell
##     walled off from it, or on top of a crate, is never used), snapped onto the navmesh
##   - wave enemies pass through NPCs (the townsfolk never pin one in place)
##   - a wave enemy that makes no headway for STUCK_TIME, or ends up off the floor, hops a couple
##     of metres along its path; on screen that's a two-frame Null flicker. One with no path at all
##     goes back to a spawn point, but only off screen.

@export var quest_id := "q02b_the_road_out"
## What winning counts as (QuestItems id): the portal is sealed by it.
@export var held_key := "dock_held"
## Only starts once this is recovered too ("" = no such step before it).
@export var after_key := ""
## The portal this fight is at: the one leading here.
@export_file("*.tscn") var dock_target := "res://scenes/map/town/act_2_convoy.tscn"
@export var trigger_radius := 9.0
## Start as soon as the quest allows it, wherever the player is in the area, instead of
## waiting for them to walk up to the portal: the Null flood Hardfault the moment it moves.
@export var start_anywhere := false
## After dying calls it off, wait this long before it starts again (start_anywhere only).
@export var restart_delay := 4.0
## Progress only runs while the player is this close to the portal.
@export var hold_radius := 11.0
@export var load_time := 45.0
@export var wave_every := 9.0
@export var wave_sizes: Array[int] = [12, 17, 22, 27, 32]
@export var enemy_level := 9
## Every wave is tougher than the last. Wave n gets health_flat x n more health and
## armour_flat x n more armour (added to the base, so the level and percentages scale it too),
## then health_growth x n and armour_growth x n on top (0.25 = +25%, the third wave +75%).
## Damage grows by damage_growth for each wave after the first. All on top of enemy_level.
@export var wave_health_flat := 100.0
@export var wave_armour_flat := 100.0
@export var wave_health_growth := 0.25
@export var wave_armour_growth := 0.25
@export var wave_damage_growth := 0.12
## Mini-bosses with every wave (rare, rolling their own modifiers), grown like the rest.
@export var mini_bosses: Array[EnemyDefinition] = [
	preload("res://data/enemies/raider_boss.tres"),
	preload("res://data/enemies/enchanter_boss.tres"),
]
@export var mini_boss_rarity := "rare"
## The mini-bosses come once, with the last wave (the fight's climax), instead of with every wave.
@export var bosses_last_wave_only := false
## Where waves come from: floor this far from the portal (metres).
@export var spawn_min := 9.0
@export var spawn_max := 15.0
## No wave spawns this close to any other portal in the area (metres).
@export var portal_clearance := 8.0
@export var swarm: EnemyDefinition = preload("res://data/enemies/glitchling.tres")
@export var brute: EnemyDefinition = preload("res://data/enemies/alien.tres")
@export var shooter: EnemyDefinition = preload("res://data/enemies/alien_range.tres")

@export_group("Evacuation")
## The area's NPCs run for the portal when the fight starts and vanish through it.
@export var evacuate_npcs := false
@export var npc_speed := 4.5
## Seconds between one NPC setting off and the next.
@export var npc_stagger := 0.8

@export_group("Text")
@export var title_text := "// HOLD THE DOCK //"
@export_multiline var start_toast := "THE NULL IS COMING FOR THE CONVOY\nHold the dock while Hardfault loads."
@export var progress_text := "LOADING THE CONVOY  %d%%"
@export var away_text := "RETURN TO THE DOCK: LOADING STOPPED (%d%%)"
@export var clear_text := "CONVOY LOADED. CLEAR THE DOCK."
@export var count_text := "NULL ON THE DOCK: %d"
@export_multiline var done_toast := "CONVOY LOADED\nBoard now: the portal is open."

const POLL := 0.3
const FONT_PATH := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const ACCENT := Color("#00E5FF")
const COL_WARN := Color(1.0, 0.35, 0.35)
const COL_GOOD := Color(0.25, 1.0, 0.55)
const RUN_CLIP := "player_anims/Jog_F"     # every NPC model shares the player's animations
## The navmesh's clearance from walls: the biggest boarders (a rare's 1.5x body) still fit round
## corners, so a path never runs where a body snags.
const NAV_CLEARANCE := 0.5
const NAV_SOURCE_GROUP := &"dock_nav_source"
## A spawn point this far from the navmesh isn't walkable floor (inside a wall's clearance, a prop).
const SPAWN_OFF_MESH := 1.2
## Stuck watch: checked every STUCK_CHECK seconds. A chasing wave enemy that moved less than
## STUCK_MOVE metres over STUCK_TIME seconds, or stands more than OFF_MESH from the navmesh, is
## moved HOP metres along its path to its target.
const STUCK_CHECK := 0.5
const STUCK_MOVE := 0.35
const STUCK_TIME := 3.0
const OFF_MESH := 1.4
const HOP := 2.5
## After this many hops with no headway in between, it goes back to a spawn point (off screen).
const HOPS_BEFORE_RESPAWN := 3
const VANISH_DISTANCE := 1.2               # metres from the portal where a runner steps through

enum State { WAITING, RUNNING, CLEARING, DONE }
var state := State.WAITING
var progress := 0.0                      # 0..1
var _wave := 0
var _next_wave := 0.0
var _alive: Array[Node3D] = []
var _enemies: Node3D                     # the Null of the fight, for the minimap (set_alert)
var _poll := 0.0
var _restart_wait := 0.0                 # start_anywhere: a breather after dying
var _portal: Node3D                      # what the fight is held at (a Portal here; HullBreach: the route terminal)
var _spawn_points: Array[Vector3] = []
var _baked := false
var _runners: Array[Dictionary] = []     # the fleeing NPCs, see _evacuate()
var _npc_bodies: Array[PhysicsBody3D] = []   # the townsfolk's bodies: wave enemies pass through them
var _watch := 0.0                        # time to the next stuck check
var _stuck := {}                         # enemy instance id -> {"at": Vector3, "still": float, "hops": int}
var _hud: CanvasLayer
var _title: Label
var _status: Label
var _bar: ProgressBar
var _count: Label


func _ready() -> void:
	_build_hud()


func _exit_tree() -> void:
	if is_instance_valid(_hud):
		_hud.queue_free()
	if state == State.RUNNING or state == State.CLEARING:
		_set_alert(false)                        # leaving mid-fight


func _process(delta: float) -> void:
	match state:
		State.WAITING:
			_restart_wait = maxf(_restart_wait - delta, 0.0)
			_poll -= delta
			if _poll <= 0.0:
				_poll = POLL
				if _wants_to_start():
					_start()
		State.RUNNING, State.CLEARING:
			_run(delta)


# ---------- STARTING ----------
func _qm() -> QuestManager:
	var p := _player()
	return p.get("quests") as QuestManager if p != null else null


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


func _find_portal() -> Node3D:
	if is_instance_valid(_portal):
		return _portal
	for p in get_parent().find_children("*", "Portal", true, false):
		if (p as Portal).target_area == dock_target:
			_portal = p
	return _portal


func _wants_to_start() -> bool:
	var qm := _qm()
	if qm == null or not qm.is_active(quest_id) or qm.has_recovered(held_key):
		return false
	if after_key != "" and not qm.has_recovered(after_key):
		return false
	var dialogue := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if dialogue != null and dialogue.is_open():
		return false                      # let Brack finish talking before everyone runs
	var portal := _find_portal()
	var player := _player()
	if portal == null or player == null:
		return false
	var hp := player.get("health") as HealthComponent
	if hp != null and hp.current_health <= 0.0:
		return false
	if start_anywhere:
		return _restart_wait <= 0.0
	return player.global_position.distance_to(portal.global_position) <= trigger_radius


func _start() -> void:
	state = State.RUNNING
	progress = 0.0
	_wave = 0
	_next_wave = 1.5                      # a breath before the first wave
	_collect_spawn_points()
	var player := _player()
	var hp := player.get("health") as HealthComponent
	if hp != null and not hp.died.is_connected(_on_player_died):
		hp.died.connect(_on_player_died)
	_title.text = title_text
	_hud.visible = true
	if not is_instance_valid(_enemies):
		_enemies = Node3D.new()
		_enemies.name = "DockNull"
		get_parent().add_child(_enemies)
	_set_alert(true)
	QuestItems.toast(get_tree(), start_toast, COL_WARN)
	if evacuate_npcs:
		_evacuate()
	_stuck.clear()
	_find_npc_bodies()
	if not _baked:
		await _bake()
	else:
		_keep_reachable_spawns()


## Floor around the portal, spawn_min..spawn_max metres away, for the waves to come from, and
## at least portal_clearance from every other portal: the Null don't appear on top of the way
## you came in (the dock's portal back to Hardfault). If that leaves nowhere, any floor in range.
func _collect_spawn_points() -> void:
	_spawn_points.clear()
	var town := get_parent() as TownArea
	if town == null or town._director == null:
		return
	var centre := _portal.global_position
	var others: Array[Vector3] = []
	for p in town.find_children("*", "Portal", true, false):
		if p != _portal:
			others.append((p as Portal).global_position)
	var near_portals: Array[Vector3] = []
	for c in town._director.grid_map.get_used_cells():
		if c.y != TownArea.FLOOR_LAYER or not town._is_floor(Vector2i(c.x, c.z)):
			continue
		var at := town._cell_to_world(Vector2i(c.x, c.z))
		var d := Vector2(at.x - centre.x, at.z - centre.z).length()
		if d < spawn_min or d > spawn_max:
			continue
		var clear := true
		for o in others:
			if Vector2(at.x - o.x, at.z - o.z).length() < portal_clearance:
				clear = false
		if clear:
			_spawn_points.append(at)
		else:
			near_portals.append(at)
	if _spawn_points.is_empty():
		_spawn_points = near_portals


func _region() -> NavigationRegion3D:
	return get_parent().get_node_or_null("NavigationRegion3D") as NavigationRegion3D


func _bake() -> void:
	var region := _region()
	if region == null:
		return
	if region.navigation_mesh == null:
		region.navigation_mesh = NavigationMesh.new()
	var nm := region.navigation_mesh
	nm.agent_radius = NAV_CLEARANCE
	nm.agent_height = 1.8
	# The tiles and furniture (the region's children, meshes as before) and every NPC and prop
	# standing in the area (their colliders), so paths go round them
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = NAV_SOURCE_GROUP
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_BOTH
	region.add_to_group(NAV_SOURCE_GROUP)
	for body in get_parent().find_children("*", "StaticBody3D", true, false):
		if not region.is_ancestor_of(body):
			body.add_to_group(NAV_SOURCE_GROUP)
	region.bake_navigation_mesh(true)
	await region.bake_finished
	await get_tree().physics_frame                # the new navmesh reaches the navigation map
	await get_tree().physics_frame
	_keep_reachable_spawns()
	_baked = true


## The spawn points the Null can actually walk from: on the navmesh (snapped onto it) and with a
## path to the fight. Floor walled off from it, or a crate top, is dropped. If none are left, the
## old list stands (better a stuck boarder than no wave).
func _keep_reachable_spawns() -> void:
	var region := _region()
	if region == null or _spawn_points.is_empty() or not is_instance_valid(_portal):
		return
	var map := region.get_navigation_map()
	var goal := NavigationServer3D.map_get_closest_point(map, _portal.global_position)
	var kept: Array[Vector3] = []
	for p in _spawn_points:
		var on := NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(on.x - p.x, on.z - p.z).length() > SPAWN_OFF_MESH:
			continue
		var path := NavigationServer3D.map_get_path(map, on, goal, true)
		if path.is_empty() or path[path.size() - 1].distance_to(goal) > 1.5:
			continue
		kept.append(on)
	if not kept.is_empty():
		_spawn_points = kept


## The townsfolk's bodies (DialogueNPC: Brack, Hex, Sudo...), for wave enemies to pass through.
func _find_npc_bodies() -> void:
	_npc_bodies.clear()
	for npc in get_parent().find_children("*", "DialogueNPC", true, false):
		for b in npc.find_children("*", "PhysicsBody3D", true, false):
			_npc_bodies.append(b as PhysicsBody3D)


# ---------- THE FIGHT ----------
func _run(delta: float) -> void:
	_alive.assign(_alive.filter(func(e) -> bool: return is_instance_valid(e) and e.is_in_group("enemies")))
	if _baked:
		_watch -= delta
		if _watch <= 0.0:
			_watch = STUCK_CHECK
			_unstick()
	if _baked:
		for r in _runners:
			_move_runner(r, delta)
	var player := _player()
	if player == null:
		return
	var holding := player.global_position.distance_to(_portal.global_position) <= hold_radius
	if state == State.RUNNING:
		if holding:
			progress = minf(progress + delta / load_time, 1.0)
		if _baked:
			_next_wave -= delta
			if _next_wave <= 0.0 and _wave < wave_sizes.size():
				_spawn_wave()
				_next_wave = wave_every
		if progress >= 1.0:
			state = State.CLEARING
	if state == State.CLEARING and _alive.is_empty():
		_held()
		return
	_update_hud(holding)


func _spawn_wave() -> void:
	if _spawn_points.is_empty():
		return
	var count := wave_sizes[_wave]
	_wave += 1
	var grow := float(_wave)                     # this is wave `grow`, counting from 1
	for i in count:
		# Mostly swarm, a brute every third, shooters from the second wave on
		var def := brute if i % 3 == 2 else swarm
		if _wave >= 2 and i % 4 == 0:
			def = shooter
		var rarity := "magic" if i % 5 == 1 and _wave >= 3 else "normal"
		_spawned(_spawn_one(def, rarity, [], grow), i)
	if bosses_last_wave_only and _wave < wave_sizes.size():
		return
	for boss in mini_bosses:
		_spawned(_spawn_one(boss, mini_boss_rarity, null, grow), -1)   # null: they roll their modifiers


## A wave enemy just arrived: `index` is its place in the wave (-1 for a mini-boss). For
## subclasses (HullBreach picks its saboteurs here). `e` may be null (it failed to spawn).
func _spawned(_e: Node3D, _index: int) -> void:
	pass


func _spawn_one(def: EnemyDefinition, rarity: String, mods: Variant, grow: float) -> Node3D:
	if def == null:
		return null
	var at: Vector3 = _spawn_points[randi() % _spawn_points.size()] + Vector3.UP * 0.1
	var e := EnemySpawner.spawn_enemy(def, rarity, _enemies, at, enemy_level, mods)
	if e == null:
		return null
	EnemySpawner.empower(e, wave_health_growth * grow, wave_armour_growth * grow,
			wave_damage_growth * (grow - 1.0), "wave", wave_health_flat * grow, wave_armour_flat * grow)
	e.ai.aggro_range = spawn_max * 3.0          # they all come for the portal
	for b in _npc_bodies:
		if is_instance_valid(b):
			e.add_collision_exception_with(b)   # the townsfolk never pin a boarder in place
	_alive.append(e)
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers:
		numbers.track(e.health)
	return e


# ---------- KEEPING THEM MOVING ----------
## Every STUCK_CHECK seconds: a chasing wave enemy that made no headway for STUCK_TIME, or stands
## off the navmesh, hops along its path (or, with no path, goes back to a spawn point off screen).
func _unstick() -> void:
	var region := _region()
	if region == null:
		return
	var map := region.get_navigation_map()
	var cam := get_viewport().get_camera_3d()
	var seen := {}
	for e in _alive:
		var id := e.get_instance_id()
		seen[id] = true
		var ai := e.get("ai") as AIComponent
		var w: Dictionary = _stuck.get(id, {"at": e.global_position, "still": 0.0, "hops": 0})
		_stuck[id] = w
		var on := NavigationServer3D.map_get_closest_point(map, e.global_position)
		var off_mesh := Vector2(on.x - e.global_position.x, on.z - e.global_position.z).length() > OFF_MESH
		var moved := Vector2(e.global_position.x - w.at.x, e.global_position.z - w.at.z).length()
		w.at = e.global_position
		if ai == null or ai.target == null or not is_instance_valid(ai.target) or ai.state != AIComponent.State.CHASE \
				or ai._is_busy() or _content(e, ai):
			w.still = 0.0                                # fighting, casting, or where it wants to be
			if moved > STUCK_MOVE:
				w.hops = 0
			if not off_mesh:
				continue
		if moved > STUCK_MOVE and not off_mesh:
			w.still = 0.0
			w.hops = 0
			continue
		w.still += STUCK_CHECK
		if w.still < STUCK_TIME and not off_mesh:
			continue
		w.still = 0.0
		var goal: Vector3 = ai.target.global_position if ai != null and ai.target != null and is_instance_valid(ai.target) \
				else _portal.global_position
		var path := NavigationServer3D.map_get_path(map, on, NavigationServer3D.map_get_closest_point(map, goal), true)
		var reaches := not path.is_empty() and path[path.size() - 1].distance_to(goal) < 3.0
		w.hops += 1
		var visible := cam != null and cam.is_position_in_frustum(e.global_position + Vector3.UP)
		if reaches and w.hops <= HOPS_BEFORE_RESPAWN:
			_hop(e, _along(path, HOP) if path.size() > 1 else on, visible)
		elif not visible and not _spawn_points.is_empty():
			_hop(e, _spawn_points[randi() % _spawn_points.size()], false)   # no way out: back to the edge
			w.hops = 0
		elif off_mesh:
			_hop(e, on, visible)                         # at least back onto the floor
	for id in _stuck.keys():
		if not seen.has(id):
			_stuck.erase(id)


## True when an enemy standing still means to: a shooter at its range, a saboteur at its system.
func _content(e: Node3D, ai: AIComponent) -> bool:
	var d := e.global_position.distance_to(ai.target.global_position)
	if ai.preferred_distance > 0.0 and d <= ai.preferred_distance * 1.3:
		return true
	return d <= ai.attack_range * 1.5


## The point `metres` along a path (or its end).
static func _along(path: PackedVector3Array, metres: float) -> Vector3:
	var left := metres
	for i in range(1, path.size()):
		var seg := path[i] - path[i - 1]
		var l := seg.length()
		if l >= left:
			return path[i - 1] + seg * (left / maxf(l, 0.001))
		left -= l
	return path[path.size() - 1]


## Moves an enemy to `to`. Seen by the camera, it flickers out and back over two short frames
## (the Null skipping a frame); unseen, it just moves.
func _hop(e: Node3D, to: Vector3, seen: bool) -> void:
	var at := to + Vector3.UP * 0.1
	if not seen:
		e.global_position = at
		e.set("velocity", Vector3.ZERO)
		return
	var model := e.get("model") as Node3D
	if model != null:
		model.visible = false
	var tw := create_tween()
	tw.tween_interval(0.07)
	tw.tween_callback(func() -> void:
		if is_instance_valid(e):
			e.global_position = at
			e.set("velocity", Vector3.ZERO))
	tw.tween_interval(0.07)
	tw.tween_callback(func() -> void:
		if is_instance_valid(e) and model != null and is_instance_valid(model):
			model.visible = true)


func _held() -> void:
	state = State.DONE
	_hud.visible = false
	_set_alert(false)
	var qm := _qm()
	if qm != null:
		qm.recover(held_key)                         # opens the portal, completes the step
	QuestItems.toast(get_tree(), done_toast, COL_GOOD)


## Dying calls it off: the Null leave, progress starts over next time, and anyone who fled
## is back at their post.
func _on_player_died() -> void:
	if state != State.RUNNING and state != State.CLEARING:
		return
	for e in _alive:
		if is_instance_valid(e):
			e.queue_free()
	_alive.clear()
	state = State.WAITING
	progress = 0.0
	_restart_wait = restart_delay
	_hud.visible = false
	_set_alert(false)
	_restore_runners()


## The minimap: ATTACK with the Null on it while the fight is on, SAFE ZONE after.
func _set_alert(on: bool) -> void:
	var mm := get_tree().get_first_node_in_group("minimap")
	if mm != null and mm.has_method("set_alert"):
		mm.set_alert(_enemies if on else null)


# ---------- THE EVACUATION ----------
## Every NPC in the area sets off for the portal, a moment apart. They run along the navmesh
## (once it's baked), step through and are gone. Until the area is next loaded: the fight won,
## coming back to Hardfault finds everyone at their post again.
func _evacuate() -> void:
	_runners.clear()
	var npcs: Array = get_parent().find_children("*", "DialogueNPC", true, false)
	# Nearest the portal goes first, so nobody runs through someone still waiting
	npcs.sort_custom(func(a, b) -> bool:
		return a.global_position.distance_to(_portal.global_position) \
				< b.global_position.distance_to(_portal.global_position))
	for i in npcs.size():
		var npc := npcs[i] as DialogueNPC
		var body := npc.get_node_or_null("Body") as CollisionObject3D
		_runners.append({
			"npc": npc, "home": npc.global_transform, "delay": 0.3 + i * npc_stagger,
			"path": PackedVector3Array(), "i": 0, "gone": false, "started": false,
			"body": body, "layer": body.collision_layer if body != null else 0,
		})


func _move_runner(r: Dictionary, delta: float) -> void:
	var npc := r.npc as DialogueNPC
	if r.gone or not is_instance_valid(npc):
		return
	r.delay -= delta
	if r.delay > 0.0:
		return
	if not r.started:
		r.started = true
		_set_out(r)
	var path: PackedVector3Array = r.path
	var at := npc.global_position
	var goal := _portal.global_position
	if Vector2(goal.x - at.x, goal.z - at.z).length() <= VANISH_DISTANCE or r.i >= path.size():
		_vanish(r)
		return
	var next := path[r.i]
	var to := Vector2(next.x - at.x, next.z - at.z)
	var step := npc_speed * delta
	if to.length() <= step:
		r.i += 1
		step = to.length()
	if to.length() > 0.001:
		var dir := to.normalized()
		npc.global_position += Vector3(dir.x, 0.0, dir.y) * step     # keep their own height
		var turner := npc.get_node_or_null("ModelAnchor") as Node3D
		if turner == null:
			turner = npc
		var yaw := atan2(dir.x, dir.y) + deg_to_rad(npc.model_forward_offset_deg)
		turner.global_rotation.y = lerp_angle(turner.global_rotation.y, yaw, 1.0 - exp(-12.0 * delta))


## Off they go: no talking to them, no bumping into them, running.
func _set_out(r: Dictionary) -> void:
	var npc := r.npc as DialogueNPC
	npc.set_deferred("monitoring", false)
	npc.set_process(false)                          # Interactable's turning-to-face
	if r.body != null:
		(r.body as CollisionObject3D).collision_layer = 0
	var goal := _portal.global_position
	var region := _region()
	if region != null:
		r.path = NavigationServer3D.map_get_path(region.get_navigation_map(), npc.global_position, goal, true)
	if (r.path as PackedVector3Array).is_empty():
		r.path = PackedVector3Array([goal])         # no navmesh: straight for it
	r.i = 0
	var ap := npc.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null:
		var clip := RUN_CLIP if ap.has_animation(RUN_CLIP) else ""
		for c in ap.get_animation_list():
			if clip == "" and (String(c).to_lower().contains("jog") or String(c).to_lower().contains("run")):
				clip = c
		if clip != "":
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			ap.play(clip, 0.15)


## Through the portal: a quick shrink, then gone.
func _vanish(r: Dictionary) -> void:
	r.gone = true
	var npc := r.npc as DialogueNPC
	var t := npc.create_tween()
	t.tween_property(npc, "scale", Vector3.ONE * 0.05, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(npc.hide)
	r["tween"] = t


func _restore_runners() -> void:
	for r in _runners:
		var npc := r.npc as DialogueNPC
		if not is_instance_valid(npc):
			continue
		if r.has("tween") and (r.tween as Tween).is_valid():
			(r.tween as Tween).kill()
		npc.global_transform = r.home
		npc.scale = Vector3.ONE
		npc.show()
		npc.set_deferred("monitoring", true)
		if r.body != null:
			(r.body as CollisionObject3D).collision_layer = r.layer
		var anchor := npc.get_node_or_null("ModelAnchor")
		var ap := npc.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap != null:
			var idle = anchor.get("idle_animation") if anchor != null else null
			var clip := String(idle) if idle != null and ap.has_animation(idle) else "player_anims/Idle"
			if ap.has_animation(clip):
				ap.play(clip, 0.15)
	_runners.clear()


# ---------- HUD ----------
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 19                                  # under the HUD's menus (20), like the exam card
	_hud.visible = false
	var font: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.03, 0.06, 0.85)
	box.border_color = ACCENT
	box.set_border_width_all(2)
	box.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.custom_minimum_size.x = 460
	panel.offset_left = -230
	panel.offset_right = 230
	panel.offset_top = 110
	_hud.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	_title = _label(title_text, 20, ACCENT, font)
	v.add_child(_title)
	_status = _label("", 16, Color(0.85, 0.96, 1.0), font)
	v.add_child(_status)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 12
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	var back := StyleBoxFlat.new()
	back.bg_color = Color(ACCENT, 0.15)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	v.add_child(_bar)
	_count = _label("", 15, COL_WARN, font)
	v.add_child(_count)
	# On the game window, not in here: the town lives in the low-resolution 3D view, and UI
	# inside it would be drawn three times too big (like ExamHud). Freed with this node.
	get_tree().root.add_child.call_deferred(_hud)


func _label(text: String, size_px: int, col: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


func _update_hud(holding: bool) -> void:
	_bar.value = progress
	if state == State.CLEARING:
		_status.text = clear_text
		_status.add_theme_color_override("font_color", COL_GOOD)
	elif not holding:
		_status.text = away_text % roundi(progress * 100.0)
		_status.add_theme_color_override("font_color", COL_WARN)
	else:
		_status.text = progress_text % roundi(progress * 100.0)
		_status.add_theme_color_override("font_color", Color(0.85, 0.96, 1.0))
	var wave := "WAVE %d/%d" % [_wave, wave_sizes.size()] if _wave > 0 else ""
	if _alive.is_empty():
		_count.text = wave
	else:
		_count.text = (count_text % _alive.size()) + ("   ·   " + wave if wave != "" else "")
