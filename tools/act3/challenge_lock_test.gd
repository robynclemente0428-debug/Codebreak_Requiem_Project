extends Node
## Tests the Perimeter Warden's CHALLENGE lock (ChallengeLock + PatchPanel's CHALLENGE mode).
## Run this scene from the editor (F6). Boots main.tscn onto the convoy with NO character slot
## loaded (nothing is saved), goes to Checkpoint Approach and stands the player by the Warden:
##   1. every Warden puzzle starts broken, and its fix makes every test pass
##   2. the Warden opens a challenge once the player is close, and the fight pauses
##   3. a wrong RUN hurts, a solve opens the port and unpauses
##   4. the next challenge is a different puzzle; walking away hurts and closes it
## Prints [CHALLENGE] lines; "ALL PASSED" at the end, or the first FAIL.
## Set `stop_at_panel` to leave the first challenge open for you to try.

const MAIN := "res://scenes/map/main.tscn"
const CONVOY := "res://scenes/map/town/act_2_convoy.tscn"
const APPROACH := "res://scenes/map/dungeon/act_2_checkpoint_approach.tscn"
const PatchPanelScript := preload("res://scenes/map/town/convoy/patch_panel.gd")

@export var stop_at_panel := false

var _fails := 0
var _keep_alive := false
var _warden: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS              # keeps testing while a challenge pauses the game
	_run.call_deferred()


func _run() -> void:
	# 1. The puzzles on their own
	for id in PatchPanelScript.WARDEN_PUZZLES:
		var pz = PatchPanelScript.warden_puzzle(id)
		_check("%s starts broken" % pz.file, not _passes(pz.run()))
		_fix(pz, id)
		_check("%s fixed passes: %s" % [pz.file, pz.run()], _passes(pz.run()))

	# 2. The Warden in its arena
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
	await _until(_settled.bind(CONVOY), 20.0)
	_am().go_to(APPROACH, &"approach_in", 21)
	await _until(_settled.bind(APPROACH), 30.0)
	await _wait(1.5)
	var warden: Node3D = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if str(e.get_meta(&"enemy_id", "")) == "perimeter_warden":
			warden = e
	_check("the Perimeter Warden is there", warden != null)
	if warden == null:
		return _done()
	var lock: ChallengeLock = null
	for t in warden.get("traits"):
		if t is ChallengeLock:
			lock = t
	_check("it has the CHALLENGE lock", lock != null)
	var model := warden.get("model") as Node
	var meshes := model.find_children("*", "MeshInstance3D", true, false) if model != null else []
	_check("its model is the gladiator with the Warden's materials", meshes.any(func(m) -> bool:
		return m.material_override is ShaderMaterial and m.material_override.shader.resource_path.ends_with("orb_void.gdshader")))
	if lock == null:
		return _done()
	# Only the Warden fights, and the bare test character is topped up every frame (_process),
	# so the "it hurts" checks below read the damage before the next heal
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != warden:
			e.process_mode = Node.PROCESS_MODE_DISABLED
	# The Warden's own AI too (a champion can one-shot the bare test character): its lock still runs
	var ai := warden.get("ai") as Node
	if ai != null:
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	_warden = warden
	_keep_alive = true
	_player().global_position = warden.global_position + warden.global_basis * Vector3(0, 0, 4)
	await _until(func() -> bool: return _panel() != null, 8.0)
	var panel = _panel()
	_check("a challenge opens once the player is close (%s)" % lock.challenge, panel != null)
	_check("the fight pauses while it's open", get_tree().paused)
	if panel == null:
		return _done()
	await _wait(0.3)
	_log("SHOT challenge panel")
	if stop_at_panel:
		_log("STOPPED: try the challenge yourself")
		return

	# 3. Wrong, then right
	_heal()
	var hp: HealthComponent = _player().get("health")
	var before := hp.current_health
	panel._on_run()
	_check("a wrong answer hurts (%.0f -> %.0f)" % [before, hp.current_health], hp.current_health < before)
	_check("the challenge stays open after a wrong answer", _panel() != null)
	var first: String = lock.challenge
	_fix(panel.puzzle, first)
	panel._on_run()
	await _until(func() -> bool: return _panel() == null, 4.0)
	_check("solved: the panel closes and the game unpauses", _panel() == null and not get_tree().paused)
	_check("solved: the port opens", lock.is_open())
	var w_hp: float = warden.get("health").current_health
	await _wait(0.2)

	# 4. The next challenge, then walk away from it
	_heal()
	await _until(func() -> bool: return _panel() != null, lock.open_time + lock.next_delay + 4.0)
	_check("after the port closes, another challenge comes", _panel() != null)
	_check("it's a different puzzle (%s, then %s)" % [first, lock.challenge], lock.challenge != first)
	if _panel() != null:
		before = hp.current_health
		_panel().close()
		var after := hp.current_health                 # read before the next frame's top-up
		_check("walking away hurts (%.0f -> %.0f)" % [before, after], after < before)
		await _wait(0.2)
		_check("walking away closes it and unpauses", _panel() == null and not get_tree().paused)
		_check("walking away leaves the port shut", not lock.is_open())
	_log("warden life %.0f" % w_hp)

	# 5. Killing it counts as an act boss: +1 step on every knob, the first time only
	var qm := _player().get("quests") as QuestManager
	var steps_before: int = ScriptBudget.breakdown(qm)["steps"]
	warden.get("health").take_damage(warden.get("health").current_health + 1.0, true)
	await _wait(0.5)
	_check("the kill is recorded as an act boss", ScriptBudget.is_boss_killed(qm, "perimeter_warden"))
	var steps_after: int = ScriptBudget.breakdown(qm)["steps"]
	_check("knobs gain a step (%d -> %d)" % [steps_before, steps_after], steps_after == steps_before + ScriptBudget.STEPS_PER_ACT_BOSS)
	_done()


# ---------- HELPERS ----------
## The fix for each Warden puzzle, as a player would click it.
func _fix(pz, id: String) -> void:
	match id:
		"w_crowd":
			pz.step("op", 3)                 # "<" -> ">="
		"w_ping":
			pz.step("count", 2)              # 2 -> 4
		"w_vitals":
			pz.step("op", -1)                # ">" -> "<"
		"w_handshake":
			pz.move(0, 1)                    # reply, sign, receive -> receive, sign, reply
			pz.move(1, 1)
			pz.move(0, 1)
		"w_identify":
			pz.step("status", 1)             # DELETED -> INBOUND


func _passes(results: Array) -> bool:
	return results.all(func(r: Array) -> bool: return bool(r[1]))


func _panel():
	return get_tree().get_first_node_in_group(PatchPanelScript.GROUP)


func _heal() -> void:
	var p := _player()
	if p != null:
		p.get("health").heal(100000.0)


func _process(_delta: float) -> void:
	if _keep_alive:
		_heal()
		# Stay at the Warden's side, as a player fighting it would (a Skirmisher one backs off)
		var p := _player()
		if p != null and is_instance_valid(_warden) and p.global_position.distance_to(_warden.global_position) > 4.0:
			p.global_position = _warden.global_position + _warden.global_basis * Vector3(0, 0, 3)
			_log("moved back to the Warden")


func _settled(path: String) -> bool:
	var am := _am()
	return _player() != null and am != null and am.current_area != null and am.can_go() \
			and Waypoints.normalize(am.current_scene_path()) == path


func _done() -> void:
	_log("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	_log("%s  %s" % ["ok  " if ok else "FAIL", what])


func _log(text: String) -> void:
	print("[CHALLENGE] ", text)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


func _am() -> AreaManager:
	return get_tree().get_first_node_in_group("area_manager") as AreaManager


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout and not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
