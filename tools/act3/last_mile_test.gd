extends Node
## Walks THE LAST MILE (q04c_the_last_mile) end to end. Run this scene from the editor (F6).
## Boots main.tscn onto the convoy with NO character slot loaded (SaveManager.party is empty,
## so nothing is saved), marks the Act II quests done, then:
##   1. starts the quest: the guns breach must start and knock out the IFF Transponder
##   2. wins the breach (skips the waves): "checkpoint_guns_held"
##   3. solves the IFF patch puzzle: "iff_patched", Checkpoint Approach opens on the route
##   4. sails to Checkpoint Approach: the Perimeter Warden must be there
##   5. takes the clearance and walks through the gate: the Quarantine Yard loads
##   6. talks to the Registrar and turns the quest in to Brack: The Leak can start there
## Prints [LAST MILE] lines; "ALL PASSED" at the end, or the first FAIL.
## Set `interactive` to stop after step 1 and play the breach yourself.

const MAIN := "res://scenes/map/main.tscn"
const CONVOY := "res://scenes/map/town/act_2_convoy.tscn"
const YARD := "res://scenes/map/town/act_3_quarantine_yard.tscn"
const APPROACH := "res://scenes/map/dungeon/act_2_checkpoint_approach.tscn"
const QUEST := "q04c_the_last_mile"
const DONE_BEFORE := ["tut_basics", "tutorial_gear", "q00_proximity_trigger", "q01_glitchling_queen",
		"q01b_clear_the_ward", "q02_corrupted_gate_guard", "q02b_the_road_out", "exam_operator",
		"exam_architect", "q03_loop_hound_alpha", "q04_the_overflow", "q04b_hollow_choir"]

@export var interactive := false

var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load(MAIN).instantiate()
	for n in main.find_children("*", "", true, false):
		if n is AreaManager:
			n.start_area = CONVOY
	reparent(get_tree().root)                      # outlive the scene swap
	var old := get_tree().current_scene
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	if old != null and old != self:
		old.queue_free()
	_log("booting the convoy, party=%s (empty = nothing saved)" % [SaveManager.party])
	await _until(func() -> bool: return _player() != null and _area_is(CONVOY), 20.0)
	await _wait(1.5)
	var qm := _qm()
	for id in DONE_BEFORE:
		if not qm.completed_ids.has(id):
			qm.completed_ids.append(id)
	Waypoints.clear_stop("act2_relay")             # the Choir's stop is behind us
	if not interactive:
		# The test character has no gear: a huge barrier keeps it alive through the breach
		_player().get("health").add_barrier(1.0e9, 900.0)
	for b in get_tree().get_nodes_in_group("hull_breach"):
		if b.has_method("is_due") and b.is_due() and not (b is GunsBreach):
			_log("note: %s is due" % b.name)

	# 1. The quest starts the guns breach, and the first salvo knocks the IFF out
	_check("the quest can start on the convoy", qm.can_start(qm.get_def(QUEST)))
	_check("the quest started", qm.start_by_id(QUEST))
	var guns := get_tree().get_first_node_in_group("hull_breach")
	for b in get_tree().get_nodes_in_group("hull_breach"):
		if b is GunsBreach:
			guns = b
	_check("the convoy has a GunsBreach", guns is GunsBreach)
	_check("the route is blocked while the guns breach is due", Waypoints.breach_reason(get_tree()) != "")
	await _until(func() -> bool: return guns.is_running(), 15.0)
	_check("the guns breach started", guns.is_running())
	var iff := DeckSystem.find(get_tree(), "iff")
	_check("the convoy has an IFF Transponder", iff != null)
	await _wait(0.5)
	_check("the IFF went offline", iff != null and iff.is_offline())
	_check("the blackout ignores the IFF", not _blackout())
	if interactive:
		_log("INTERACTIVE: play the breach, patch the IFF, then sail to Checkpoint Approach")
		return
	await _wait(3.0)
	_shot("guns breach")

	# 2. Win it (skip the fight)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	guns.call("_held")
	await _wait(0.5)
	_check("deck held: checkpoint_guns_held", qm.has_recovered("checkpoint_guns_held"))
	_check("the guns still fire until the IFF is patched", guns.call("_guns_firing"))
	_check("the route is clear of the breach", Waypoints.breach_reason(get_tree()) == "")
	var approach := Waypoints.act_of_scene(CONVOY).find("act2_approach")
	_check("Checkpoint Approach is on the route", approach != null)
	_check("Checkpoint Approach is locked until the IFF is patched",
			Waypoints.route_blocked_reason(approach, get_tree()).contains("GUNS"))

	# 3. The IFF puzzle: the bug answers as record 1, the fix as record 2
	var Panel := load("res://scenes/map/town/convoy/patch_panel.gd")
	var puzzle = Panel.Puzzle.make("iff")
	var before: Array = puzzle.run()
	_log("iff.prog as broken: %s" % [before])
	_check("broken: answers as the deleted record", not bool(before[-1][1]) and str(before[-1][0]).contains("record 1"))
	puzzle.step("op", 1)                           # != -> ==
	var after: Array = puzzle.run()
	_log("iff.prog fixed: %s" % [after])
	_check("fixed: every test passes", after.all(func(r: Array) -> bool: return bool(r[1])))
	iff.repair()
	await _wait(0.3)
	_check("iff_patched recovered", qm.has_recovered("iff_patched"))
	_check("the guns hold fire", not guns.call("_guns_firing"))
	_check("Checkpoint Approach is open", Waypoints.route_blocked_reason(approach, get_tree()) == "")

	# 4. Sail there
	_check("sailed", Waypoints.sail(approach, get_tree()))
	await _until(func() -> bool: return _area_is(APPROACH) and _am().can_go(), 30.0)
	_check("arrived at Checkpoint Approach", _area_is(APPROACH))
	await _wait(2.0)
	var warden := _enemy("perimeter_warden")
	_check("the Perimeter Warden is there", warden != null)
	if warden != null:
		_log("warden traits: %s" % [warden.get_meta(&"base_name", "?")])
	_shot("approach")
	var gate: Portal = null
	for p in _am().current_area.find_children("*", "Portal", true, false):
		if (p as Portal).sealed_by_key == "checkpoint_clearance":
			gate = p
	_check("the gate portal is there", gate != null)
	_check("the gate is sealed without the clearance", gate != null and gate.is_sealed())

	# 5. The clearance, then through the gate
	qm.recover("checkpoint_clearance")
	_check("the gate opens with the clearance", gate != null and not gate.is_sealed())
	if gate != null:
		_player().global_position = gate.global_position
	await _until(func() -> bool: return _area_is(YARD) and _am().can_go(), 30.0)
	_check("docked in the Quarantine Yard", _area_is(YARD))
	await _wait(1.5)
	_check("the dock step is done", qm.get_state(QUEST) != null and qm.get_state(QUEST).objective_done(3))
	_check("the yard is on the waypoint map", Waypoints.is_discovered(Waypoints.for_scene(YARD)))
	var reg := _npc("registrar")
	_check("the Registrar is in the yard", reg != null)
	_check("Brack is in the yard", _npc("brack") != null)
	_shot("yard")

	# 6. The Registrar, then Brack
	GameEvents.report("talk", "registrar")
	await _wait(0.2)
	var s := qm.get_state(QUEST)
	_check("ready to turn in", s != null and s.status == QuestState.Status.READY_TO_TURN_IN)
	var err := qm.turn_in(QUEST)
	_check("turned in (%s)" % err, err == "" and qm.is_completed(QUEST))
	_check("The Leak can start in the yard", qm.can_start(qm.get_def("q05_the_leak")))
	_log("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)


# ---------- HELPERS ----------
func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	_log("%s  %s" % ["ok  " if ok else "FAIL", what])


func _log(text: String) -> void:
	print("[LAST MILE] ", text)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


func _qm() -> QuestManager:
	return _player().get("quests") as QuestManager


func _am() -> AreaManager:
	return get_tree().get_first_node_in_group("area_manager") as AreaManager


func _area_is(path: String) -> bool:
	var am := _am()
	return am != null and am.current_area != null and Waypoints.normalize(am.current_scene_path()) == path


func _enemy(id: String) -> Node:
	for e in get_tree().get_nodes_in_group("enemies"):
		if str(e.get_meta(&"enemy_id", "")) == id:
			return e
	return null


func _npc(id: String) -> Node:
	for n in _am().current_area.find_children("*", "DialogueNPC", true, false):
		if n.npc_id == id:
			return n
	return null


func _blackout() -> bool:
	var b := get_tree().get_first_node_in_group("convoy_blackout")
	return b != null and b.call("all_down")


func _shot(label: String) -> void:
	_log("SHOT " + label)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout and not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
