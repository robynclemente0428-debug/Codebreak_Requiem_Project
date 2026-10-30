class_name AreaManager
extends Node
## Owns area switching. The player lives OUTSIDE the area container, so it
## survives transitions and never inherits an area's (or the map node's)
## rotation/offset.
##
## main.tscn layout:
##   SubViewport
##   |- Map            <- area_container (rotate it here if you like)
##   |- Player         <- player (NOT inside Map; keep it at (0,0,0) in the scene)
##   |- AreaManager    <- this script
##   FadeRect          <- optional black ColorRect (alpha 0, mouse_filter = Ignore)

## Holds only the current area.
@export var area_container: Node3D
## The persistent player.
@export var player: Player
@export_file("*.tscn") var start_area: String
@export var start_spawn: StringName = &"default"
## Optional full-screen black ColorRect used for the fade.
@export var fade_rect: ColorRect
@export var fade_time: float = 0.25
## Ignore portal triggers for a moment after arriving (prevents ping-pong).
@export var arrival_cooldown_ms: int = 600

var current_area: GameArea
var _current_path := ""     # <- add this
var _busy := false
var _ignore_until_ms := 0


## The waypoint map (U). Created here so every game scene with an AreaManager has one.
const WAYPOINT_PANEL := preload("res://scenes/ui/player_ui/waypoints/waypoint_panel.gd")
## Click an NPC for their info card. Created here too.
const NPC_INFO_PANEL := preload("res://scenes/ui/player_ui/npc_info/npc_info_panel.gd")
## Stim hotkeys (1 / 2), charges and their HUD.
const STIM_HUD := preload("res://scenes/ui/player_ui/stims/stim_hud.gd")


func _ready() -> void:
	add_to_group("area_manager")
	_add_waypoint_panel()
	await get_tree().process_frame  # let the rest of main.tscn finish _ready
	var town := SaveManager.last_town()
	if town.is_empty():
		await _change_area(start_area, start_spawn, false)
	else:
		await _change_area(town, &"default", false)     # back in the last town visited


func is_busy() -> bool:
	return _busy


## The scene file of the area the party is in ("" before the first area loads).
func current_scene_path() -> String:
	return _current_path


## Teleport used by the waypoint map. Same as going through a portal, minus the arrival
## cooldown (that only exists to stop portals bouncing you straight back).
## new_instance: open a fresh instance instead of rejoining (Ctrl + click on the waypoint map).
func travel(scene_path: String, spawn_id: StringName, dungeon_level: int = 0, new_instance := false) -> void:
	_ignore_until_ms = 0
	await go_to(scene_path, spawn_id, dungeon_level,
			WorldState.ALWAYS_NEW if new_instance else WorldState.REJOIN_OR_NEW)


func _add_waypoint_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WaypointLayer"
	layer.layer = 21                      # just above the HUD (20)
	var info := NPC_INFO_PANEL.new()
	info.name = "NpcInfoPanel"
	layer.add_child(info)
	var panel := WAYPOINT_PANEL.new()
	panel.name = "WaypointPanel"
	layer.add_child(panel)                # added last, so the map draws over an open info card
	# This node sits inside the game's SubViewport (the low-res 3D view). The map must be drawn
	# in the window itself like the HUD, so attach it outside every SubViewport.
	var host: Node = self
	var vp := get_viewport()
	while vp is SubViewport and vp.get_parent() != null:
		host = vp.get_parent()
		vp = host.get_viewport()
	host.add_child.call_deferred(layer)
	var stim_layer := CanvasLayer.new()
	stim_layer.name = "StimLayer"
	stim_layer.layer = 19                 # under the HUD panels, so open menus cover it
	var stims := STIM_HUD.new()
	stims.name = "StimHud"
	stim_layer.add_child(stims)
	host.add_child.call_deferred(stim_layer)


## Called by portals. Safe to call from anywhere.
## dungeon_level > 0 marks the trip as going into a dungeon instance (see WorldState):
## instance_id 0 rejoins that dungeon's open instance or opens one, -1 always opens a new one.
func go_to(scene_path: String, spawn_id: StringName = &"default",
		dungeon_level: int = 0, instance_id: int = 0) -> void:
	if _busy or scene_path.is_empty():
		return
	if Time.get_ticks_msec() < _ignore_until_ms:
		return
	if dungeon_level > 0:
		WorldState.prepare_dungeon(scene_path, dungeon_level, instance_id)   # only once the trip is certain
	await _change_area(scene_path, spawn_id, true)


func _change_area(scene_path: String, spawn_id: StringName, use_fade: bool, revive := false) -> void:
	_busy = true
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO

	if use_fade:
		await _fade_to(1.0)
	get_tree().call_group("blast_swarms", "clear")    # <- add here
	# Remove the old area completely before building the new one.
	if current_area:
		current_area.queue_free()
		await current_area.tree_exited
		current_area = null

	var packed := load(scene_path) as PackedScene
	var area := packed.instantiate() as GameArea if packed else null
	if area == null:
		push_error("AreaManager: '%s' is missing or its root doesn't extend GameArea" % scene_path)
		await _finish(use_fade)
		return

	# _ready() runs here, so a procedural area has generated itself by now.
	area_container.add_child(area)
	current_area = area
	_current_path = scene_path

	# GridMap / StaticBody collision is created deferred. Wait for it, or the
	# player drops into a world with no floor yet.
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.global_position = area.get_spawn_position(spawn_id) + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	if revive:
		player.revive()

	# Areas that care about the player arriving (towns heal and save here)
	if area.has_method("on_player_arrived"):
		area.on_player_arrived(player)
	Waypoints.arrived(scene_path)         # first visit unlocks the area on the waypoint map (U)

	await _finish(use_fade)


func _finish(use_fade: bool) -> void:
	await get_tree().physics_frame  # let the camera rig snap to the new position
	if use_fade:
		await _fade_to(0.0)
	player.set_physics_process(true)
	_ignore_until_ms = Time.get_ticks_msec() + arrival_cooldown_ms
	_busy = false


func _fade_to(alpha: float) -> void:
	if fade_rect == null or fade_time <= 0.0:
		return
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", alpha, fade_time)
	await tween.finished

## Called by the death menu. Puts the player back at the current area's respawn marker.
## reload_area = true rebuilds the dungeon, false keeps it as it is.
func respawn(reload_area := false) -> void:
	if _busy or current_area == null:
		return
	var id: StringName = &"default"
	var v = current_area.get("respawn_spawn_id")      # null if the area has no such property
	if v != null and v != &"":
		id = v

	if reload_area:
		# Rebuild the same dungeon instance: same layout, and enemies you killed stay dead
		var inst = current_area.get("instance")
		if inst is DungeonInstance:
			WorldState.prepare_rejoin(inst)
		await _change_area(_current_path, id, true, true)
		return

	_busy = true
	player.set_physics_process(false)
	await _fade_to(1.0)
	get_tree().call_group("blast_swarms", "clear")    # <- add here
	player.global_position = current_area.get_spawn_position(id) + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player.revive()                                   # revived while the screen is black
	await _finish(true)
