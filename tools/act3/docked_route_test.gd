extends Node
## The docked terminal, with NO character slot loaded (nothing is saved): after The Last Mile it
## still deploys to every Act II stop, those runs owe no breach or Sweep, and Checkpoint Approach
## doesn't replay the quest. Writes docked_route_test_results.txt.

const MAIN := "res://scenes/map/main.tscn"
const CONVOY := "res://scenes/map/town/act_2_convoy.tscn"
const YARD := "res://scenes/map/town/act_3_quarantine_yard.tscn"
const APPROACH := "res://scenes/map/dungeon/act_2_checkpoint_approach.tscn"
const RESULTS := "res://tools/act3/docked_route_test_results.txt"
const LAST_MILE := "q04c_the_last_mile"

var _lines := PackedStringArray()
var _failed := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var main: Node = load(MAIN).instantiate()
	for n in main.find_children("*", "", true, false):
		if n is AreaManager:
			n.start_area = CONVOY
	reparent(get_tree().root)
	var old := get_tree().current_scene
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	if old != null and old != self:
		old.queue_free()
	while not (_player() != null and _am() != null and _am().current_area != null and _am().can_go()):
		await get_tree().process_frame
	await _wait(1.0)
	var qm: QuestManager = _player().get("quests")
	var tough: Dictionary = (_player().get("stats") as StatComponent).base_stats.duplicate()
	tough[StatTypes.Stat.MAX_HEALTH] = 1000000.0
	(_player().get("stats") as StatComponent).base_stats = tough
	(_player().get("health") as HealthComponent).heal(1000000.0)

	# --- Before docking, it's the ordinary terminal ---
	var terminal := _am().current_area.get_node("RouteTerminal") as RouteTerminal
	_check("not docked yet: SET COURSE (%s)" % terminal.prompt_text, terminal.prompt_text == "SET COURSE")

	# --- Docked, with the whole route behind us and no quest open ---
	var act := Waypoints.act_of_scene(CONVOY)
	var stops: Array[Waypoint] = []
	for w in act.waypoints:
		if Waypoints.is_convoy_stop(w):
			stops.append(w)
			Waypoints.clear_stop(w.id)
	_check("Act II has seven stops (%d)" % stops.size(), stops.size() == 7)
	qm.completed_ids.append("exam_architect")
	qm.completed_ids.append(LAST_MILE)
	qm.recover("iff_patched")
	qm.recover("checkpoint_clearance")
	_check("docked, with no Act II quest open", Waypoints.is_docked(qm) and qm.active.is_empty())
	terminal._show_docked()
	_check("the terminal says DEPLOY (%s)" % terminal.prompt_text, terminal.prompt_text == "DEPLOY")
	_check("and its plate says DOCKED", terminal.info_title == "DOCKED AT CHECKPOINT")

	terminal.set_signal(false)
	_check("no signal still reads NO SIGNAL (%s)" % terminal.prompt_text, terminal.prompt_text == "NO SIGNAL")
	terminal.set_signal(true)
	_check("and comes back to DEPLOY (%s)" % terminal.prompt_text, terminal.prompt_text == "DEPLOY")

	var panel := get_tree().get_first_node_in_group("waypoint_panel") as WaypointPanel
	terminal.interact(_player())
	_check("using it opens the route map", panel.is_route_open())
	_check("the map says Hardfault stays (%s)" % panel._subtitle.text, panel._subtitle.text.contains("moored"))
	panel.close()

	# --- Every stop, there and back ---
	for w in stops:
		var why := Waypoints.route_blocked_reason(w, get_tree())
		_check("%s is open (%s)" % [w.display_name, why], why == "")
		var sailed := Waypoints.sail(w, get_tree())
		await _arrive(w.scene)
		_check("deploys to %s" % w.display_name, sailed and _am().current_area.scene_file_path == w.scene)
		await _wait(1.5)
		_check("  lands on the floor (%s)" % _player().global_position, _on_floor())
		_check("  the quest stays finished", qm.is_completed(LAST_MILE) and not qm.is_active(LAST_MILE))
		if w.scene == APPROACH:
			_check_approach(qm)
		var back: Portal = _portal_to(_am().current_area.find_children("*", "Portal", true, false), CONVOY)
		_check("  a portal leads back to the convoy", back != null)
		GameEvents.report(Waypoints.FINISH_DEED, w.id)
		_am().go_to(CONVOY, back.target_spawn if back != null else &"from_route", 0)
		await _arrive(CONVOY)
		await _wait(2.0)
		var reason := Waypoints.breach_reason(get_tree())
		_check("  back on the deck, nothing due (%s)" % reason, reason == "")
		var running := false
		for b in get_tree().get_nodes_in_group("hull_breach"):
			running = running or b.is_running()
		_check("  no breach running", not running)

	# --- The yard owes nothing for them ---
	_am().go_to(YARD, &"from_approach", 0)
	await _arrive(YARD)
	await _wait(1.0)
	var sweep := _am().current_area.get_node("YardSweep") as YardSweep
	_check("Act II runs owe no Sweep", not sweep.is_due())

	_lines.append("ALL PASSED" if _failed == 0 else "%d FAILED" % _failed)
	var f := FileAccess.open(RESULTS, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\nDONE\n")


func _check_approach(qm: QuestManager) -> void:
	var portals := _am().current_area.find_children("*", "Portal", true, false)
	var gate: Portal = _portal_to(portals, YARD)
	_check("  Approach: the gate to the yard is open", gate != null and not gate.is_sealed())
	var pickups := _am().current_area.find_children("*", "QuestKeyPickup", true, false).size()
	_check("  Approach: no second clearance to pick up (%d)" % pickups, pickups == 0)
	_check("  Approach: the Last Mile's steps aren't back", not qm.is_active(LAST_MILE))


func _portal_to(portals: Array, area: String) -> Portal:
	for p in portals:
		if (p as Portal).target_area == area:
			return p
	return null


func _arrive(area: String) -> void:
	await _wait(0.5)
	var left := 40.0
	while left > 0.0 and not (_am().current_area != null and _am().current_area.scene_file_path == area and _am().can_go()):
		await get_tree().process_frame
		left -= get_process_delta_time()


func _on_floor() -> bool:
	var p := _player()
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP, p.global_position + Vector3.DOWN * 2.0)
	q.exclude = [(p as CollisionObject3D).get_rid()]
	return not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _process(_delta: float) -> void:
	if _player() != null:
		(_player().get("health") as HealthComponent).heal(100000.0)


func _check(what: String, ok: bool) -> void:
	_lines.append("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


func _am() -> AreaManager:
	return get_tree().get_first_node_in_group("area_manager") as AreaManager
