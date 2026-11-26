class_name AreaManager
extends Node

@export var area_container: Node3D
@export var player: Player
@export_file("*.tscn") var start_area: String
@export var start_spawn: StringName = &"default"
@export var fade_rect: ColorRect
@export var fade_time: float = 0.25
@export var arrival_cooldown_ms: int = 600

var current_area: GameArea
var _current_path := ""
var _busy := false
var _ignore_until_ms := 0
var _remember_spot := false


const WAYPOINT_PANEL := preload("res://scenes/ui/player_ui/waypoints/waypoint_panel.gd")
const NPC_INFO_PANEL := preload("res://scenes/ui/player_ui/npc_info/npc_info_panel.gd")
const STIM_HUD := preload("res://scenes/ui/player_ui/stims/stim_hud.gd")


func _ready() -> void:
	add_to_group("area_manager")
	_add_waypoint_panel()
	await get_tree().process_frame
	Coop.game_ready(self)
	var town := Coop.start_town if Coop.in_game else SaveManager.last_town()
	if town.is_empty():
		await _change_area(start_area, start_spawn, false)
	else:
		await _change_area(town, &"default", false)


func is_busy() -> bool:
	return _busy


func current_scene_path() -> String:
	return _current_path


func travel(scene_path: String, spawn_id: StringName, dungeon_level: int = 0, new_instance := false) -> void:
	_ignore_until_ms = 0
	_remember_spot = true
	await go_to(scene_path, spawn_id, dungeon_level,
			WorldState.ALWAYS_NEW if new_instance else WorldState.REJOIN_OR_NEW)
	_remember_spot = false


func _add_waypoint_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WaypointLayer"
	layer.layer = 21
	var info := NPC_INFO_PANEL.new()
	info.name = "NpcInfoPanel"
	layer.add_child(info)
	var party: Control = preload("res://scenes/ui/player_ui/coop/party_menu.gd").new()
	party.name = "PartyMenu"
	layer.add_child(party)
	var panel := WAYPOINT_PANEL.new()
	panel.name = "WaypointPanel"
	layer.add_child(panel)
	var host: Node = self
	var vp := get_viewport()
	while vp is SubViewport and vp.get_parent() != null:
		host = vp.get_parent()
		vp = host.get_viewport()
	host.add_child.call_deferred(layer)
	var stim_layer := CanvasLayer.new()
	stim_layer.name = "StimLayer"
	stim_layer.layer = 19
	var lock_tags: Control = preload("res://scenes/ui/player_ui/lock_tags/lock_tags.gd").new()
	lock_tags.name = "LockTags"
	stim_layer.add_child(lock_tags)
	var stims := STIM_HUD.new()
	stims.name = "StimHud"
	stim_layer.add_child(stims)
	var threats := ThreatPanel.new()
	threats.name = "ThreatPanel"
	stim_layer.add_child(threats)
	var lock_banner: Control = preload("res://scenes/ui/player_ui/lock_banner/lock_banner.gd").new()
	lock_banner.name = "LockBanner"
	stim_layer.add_child(lock_banner)
	host.add_child.call_deferred(stim_layer)


func can_go() -> bool:
	return not _busy and Time.get_ticks_msec() >= _ignore_until_ms


func go_to(scene_path: String, spawn_id: StringName = &"default",
		dungeon_level: int = 0, instance_id: int = 0) -> void:
	if _busy or scene_path.is_empty():
		return
	if Time.get_ticks_msec() < _ignore_until_ms:
		return
	if Coop.in_game:
		Coop.request_travel(scene_path, spawn_id, dungeon_level, instance_id)
		return
	if dungeon_level > 0:
		WorldState.prepare_dungeon(scene_path, dungeon_level, instance_id)
	await _change_area(scene_path, spawn_id, true)


func travel_now(scene_path: String, spawn_id: StringName) -> void:
	if _busy or scene_path.is_empty():
		return
	await _change_area(scene_path, spawn_id, true)


func _change_area(scene_path: String, spawn_id: StringName, use_fade: bool, revive := false) -> void:
	_busy = true
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO

	if use_fade:
		await _fade_to(1.0)
	get_tree().call_group("blast_swarms", "clear")
	var leaving = current_area.get("instance") if current_area else null
	if leaving is DungeonInstance:
		leaving.has_return_spot = _remember_spot and not revive
		if leaving.has_return_spot:
			leaving.return_spot = player.global_position
	Coop.area_changing()
	if current_area:
		current_area.queue_free()
		await current_area.tree_exited
		current_area = null

	var packed := load(scene_path) as PackedScene
	var area := packed.instantiate() as GameArea if packed else null
	if area == null:
		push_error("AreaManager: '%s' is missing or its root doesn't extend GameArea" % scene_path)
		if Coop.in_game:
			Coop.note("AREA FAILED TO LOAD: %s (exists %s)" % [scene_path, ResourceLoader.exists(scene_path)])
		await _finish(use_fade)
		return

	area_container.add_child(area)
	current_area = area
	_current_path = scene_path
	GraphicsQuality.apply(get_tree())

	await get_tree().physics_frame
	await get_tree().physics_frame

	var spot := area.get_spawn_position(spawn_id)
	var inst = area.get("instance")
	if inst is DungeonInstance and inst.has_return_spot and not revive:
		spot = inst.return_spot
		inst.has_return_spot = false
	player.global_position = spot + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	if revive:
		player.revive()

	if area.has_method("on_player_arrived"):
		area.on_player_arrived(player)
	if not area is TownArea:
		GameEvents.report("enter_area", area.scene_file_path.get_file().get_basename())
	Waypoints.arrived(scene_path)
	GlitchDeath.prewarm(area, spot)
	EffectWarmup.run(area, spot)
	Coop.area_loaded(scene_path)

	await _wait_for_navigation(area, use_fade)
	await _finish(use_fade)


const NAV_WAIT_MAX := 10.0
const LOADING_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
var _loading_label: Label


func _wait_for_navigation(area: GameArea, use_fade: bool) -> void:
	if area.get("navigation_is_ready") != false:
		return
	if use_fade:
		_show_loading(true)
	var waited := 0.0
	while is_instance_valid(area) and area.get("navigation_is_ready") == false and waited < NAV_WAIT_MAX:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if waited >= NAV_WAIT_MAX:
		push_warning("AreaManager: navmesh not ready after %.0f s, showing the area anyway" % NAV_WAIT_MAX)
	_show_loading(false)


func _show_loading(on: bool) -> void:
	if fade_rect == null:
		return
	if _loading_label == null:
		_loading_label = Label.new()
		_loading_label.text = "LOADING"
		_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_loading_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_loading_label.add_theme_font_size_override("font_size", 28)
		_loading_label.add_theme_color_override("font_color", Color("#00E5FF"))
		if ResourceLoader.exists(LOADING_FONT):
			_loading_label.add_theme_font_override("font", load(LOADING_FONT))
		fade_rect.add_child(_loading_label)
	_loading_label.visible = on
	if on:
		_loading_label.modulate.a = 1.0
		var tween := _loading_label.create_tween().set_loops()
		tween.tween_property(_loading_label, "modulate:a", 0.35, 0.6)
		tween.tween_property(_loading_label, "modulate:a", 1.0, 0.6)
		_loading_label.set_meta("tween", tween)
	elif _loading_label.has_meta("tween"):
		(_loading_label.get_meta("tween") as Tween).kill()
		_loading_label.remove_meta("tween")


func _finish(use_fade: bool) -> void:
	await get_tree().physics_frame
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

func respawn(reload_area := false) -> void:
	if _busy or current_area == null:
		return
	if Coop.in_game:
		reload_area = false
	var id: StringName = &"default"
	var v = current_area.get("respawn_spawn_id")
	if v != null and v != &"":
		id = v

	if reload_area:
		var inst = current_area.get("instance")
		if inst is DungeonInstance:
			WorldState.prepare_rejoin(inst)
		await _change_area(_current_path, id, true, true)
		return

	_busy = true
	player.set_physics_process(false)
	await _fade_to(1.0)
	get_tree().call_group("blast_swarms", "clear")
	player.global_position = current_area.get_spawn_position(id) + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player.revive()
	await _finish(true)
