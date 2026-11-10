extends Node
## Walks Act IV's prototype with NO character slot loaded (nothing is saved): the Inward Gate, The
## Threshold, The Fray and The Weaver's Loom, then back. Writes act4_test_results.txt, and holds on
## each area for `linger` seconds so it can be looked at.

const MAIN := "res://scenes/map/main.tscn"
const YARD := "res://scenes/map/town/act_3_quarantine_yard.tscn"
const SWEEP := "res://scenes/map/dungeon/act_3_sweep.tscn"
const FAR_SIDE := "res://scenes/map/dungeon/act_3_far_side.tscn"
const HUB := "res://scenes/map/town/act_4_threshold.tscn"
const FRAY := "res://scenes/map/dungeon/act_4_the_fray.tscn"
const LOOM := "res://scenes/map/dungeon/act_4_weavers_loom.tscn"
const RESULTS := "res://tools/act4/act4_test_results.txt"

@export var linger := 5.0

var _lines := PackedStringArray()
var _failed := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var main: Node = load(MAIN).instantiate()
	for n in main.find_children("*", "", true, false):
		if n is AreaManager:
			n.start_area = YARD
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
	# No gear on a level 33 boss: enough health to survive being looked at
	var tough: Dictionary = (_player().get("stats") as StatComponent).base_stats.duplicate()
	tough[StatTypes.Stat.MAX_HEALTH] = 1000000.0
	(_player().get("stats") as StatComponent).base_stats = tough
	(_player().get("health") as HealthComponent).heal(1000000.0)

	# --- The gate: the Sweep's exit ---
	await _go(SWEEP, &"sweep_in", 29)
	var gate := _portal_to_any(_am().current_area.find_children("*", "Portal", true, false), [YARD, FAR_SIDE])
	qm.recover("root_key")
	await _wait(0.8)
	_check("before Root Access the Sweep's exit goes home", gate != null and gate.target_area == YARD)
	qm.completed_ids.append("q06b_the_collector")
	qm.completed_ids.append("q06c_root_access")
	await _wait(0.8)
	_check("after Root Access it goes to Checkpoint's far side (level %d)" % gate.dungeon_level,
		gate.target_area == FAR_SIDE and gate.dungeon_level == 30 and not gate.is_sealed())
	await _go(YARD, &"from_district", 0)

	qm.completed_ids.append("q07a_learn_the_language")
	var q07 := qm.get_def("q07_null_weaver_prime")
	_check("Vesper's quest can't start in the yard", not qm.can_start(q07))

	# --- The hub ---
	await _go(FAR_SIDE, &"far_in", 30)
	_check("the gate arrives on the far side", _am().current_area.scene_file_path == FAR_SIDE)
	_check("the player lands on the floor (%s)" % _player().global_position, _on_floor())
	var far_portals := _am().current_area.find_children("*", "Portal", true, false)
	var far_exit := _portal_to(far_portals, HUB)
	_check("portals back to the Sweep and on to Act IV", far_exit != null and _portal_to(far_portals, SWEEP) != null)
	await _go(far_exit.target_area, far_exit.target_spawn, 0)
	var hub := _am().current_area
	_check("the far side arrives in The Threshold", hub != null and hub.scene_file_path == HUB)
	_check("it's a town of Act IV", hub is TownArea and (hub as TownArea).act == "IV")
	_check("the player lands on the floor (%s)" % _player().global_position, _on_floor())
	_check("Vesper's quest can start here", qm.can_start(q07))
	var vesper := hub.get_node("Vesper") as Node3D
	_check("Vesper is here", vesper != null and vesper.visible)
	var hex := hub.get_node("TinkerHex") as ShopNPC
	_check("Hex is here, selling (%d items, level %d)" % [hex.stock.size(), hex.stock_level], not hex.stock.is_empty() and hex.stock_level == 35)
	var hub_portals := hub.find_children("*", "Portal", true, false)
	_check("the hub has its five portals (%d)" % hub_portals.size(), hub_portals.size() == 5)
	var to_fray := _portal_to(hub_portals, FRAY)
	var to_yard := _portal_to(hub_portals, FAR_SIDE)
	_check("one back to the far side, one on to The Fray", to_fray != null and to_yard != null)
	_check("the act is on the map", Waypoints.act_of_scene(HUB) != null and Waypoints.act_of_scene(HUB).act_number == 4)
	await _wait(linger)

	# --- The Fray ---
	await _go(to_fray.target_area, to_fray.target_spawn, to_fray.dungeon_level)
	var fray := _am().current_area
	_check("The Fray loads", fray != null and fray.scene_file_path == FRAY)
	await _wait(2.0)
	_check("the player lands on the floor (%s)" % _player().global_position, _on_floor())
	var enemies := get_tree().get_nodes_in_group("enemies")
	_check("enemies spawn (%d)" % enemies.size(), enemies.size() > 0)
	if not enemies.is_empty():
		var e: Node = enemies[0]
		var scaled := false
		for m in (e.get("stats") as StatComponent)._modifiers:
			if m.source_id == "act_scaling" and m.stat == StatTypes.Stat.MAX_HEALTH and is_equal_approx(m.value, 1.5):
				scaled = true
		_check("at level %d with Act IV's +150%% (%.0f health)" % [int(e.get("level")), e.get("stats").get_stat(StatTypes.Stat.MAX_HEALTH)],
			int(e.get("level")) == 30 and scaled)
	var fray_portals := fray.find_children("*", "Portal", true, false)
	var to_loom := _portal_to(fray_portals, LOOM)
	var back_hub := _portal_to(fray_portals, HUB)
	_check("portals back and on", to_loom != null and back_hub != null)
	await _wait(linger)

	# --- The Loom ---
	await _go(to_loom.target_area, to_loom.target_spawn, to_loom.dungeon_level)
	var loom := _am().current_area
	_check("The Weaver's Loom loads", loom != null and loom.scene_file_path == LOOM)
	await _wait(2.0)
	var boss: Node3D = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get("display_name") != null and String(e.get("display_name")).contains("Null Weaver Prime"):
			boss = e
	_check("Null Weaver Prime is there", boss != null)
	qm.start_by_id("q07_null_weaver_prime")
	GameEvents.report("program_nested")
	var state := qm.get_state("q07_null_weaver_prime")
	_check("the quest starts", state != null)
	if boss != null:
		_player().global_position = boss.global_position + Vector3(9, 0.5, 0)
		await _wait(3.0)
		_check("it fights: the player was shot at (%.0f / %.0f)" % [
			(_player().get("health") as HealthComponent).current_health, (_player().get("stats") as StatComponent).get_stat(StatTypes.Stat.MAX_HEALTH)], _shot)
		(boss.get("health") as HealthComponent).take_damage(100000000.0, true)
		await _wait(1.5)
		_check("killing it finishes the quest", state != null and state.status == QuestState.Status.READY_TO_TURN_IN)
		_check("and counts as an act boss", ScriptBudget.is_boss_killed(qm, "null_weaver_prime"))
	var loom_portals := loom.find_children("*", "Portal", true, false)
	var out := _portal_to(loom_portals, HUB)
	_check("the way out isn't sealed", out != null and not out.is_sealed())

	# --- And back ---
	await _go(out.target_area, out.target_spawn, 0)
	_check("back in The Threshold", _am().current_area.scene_file_path == HUB)
	_check("the player lands on the floor (%s)" % _player().global_position, _on_floor())
	var return_gate := _portal_to(_am().current_area.find_children("*", "Portal", true, false), YARD)
	await _go(return_gate.target_area, return_gate.target_spawn, 0)
	_check("back through the gate to the yard", _am().current_area.scene_file_path == YARD)
	_check("the player lands on the floor (%s)" % _player().global_position, _on_floor())

	_lines.append("ALL PASSED" if _failed == 0 else "%d FAILED" % _failed)
	var f := FileAccess.open(RESULTS, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\nDONE\n")


var _shot := false
var _hp_before := -1.0


func _process(_delta: float) -> void:
	var p := _player()
	if p == null:
		return
	var hp := p.get("health") as HealthComponent
	if _hp_before >= 0.0 and hp.current_health < _hp_before:
		_shot = true
	hp.heal(100000.0)
	_hp_before = hp.current_health


func _portal_to(portals: Array, area: String) -> Portal:
	for p in portals:
		if (p as Portal).target_area == area:
			return p
	return null


func _portal_to_any(portals: Array, areas: Array) -> Portal:
	for p in portals:
		if (p as Portal).target_area in areas and (p as Portal).route_after_quest != "":
			return p
	return null


func _go(area: String, spawn: StringName, level: int) -> void:
	_am().go_to(area, spawn, level)
	await _wait(0.5)
	var left := 40.0
	while left > 0.0 and not (_am().current_area != null and _am().current_area.scene_file_path == area and _am().can_go()):
		await get_tree().process_frame
		left -= get_process_delta_time()
	await _wait(1.0)


## A floor to stand on: something solid just under the player's feet.
func _on_floor() -> bool:
	var p := _player()
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP, p.global_position + Vector3.DOWN * 2.0)
	q.exclude = [(p as CollisionObject3D).get_rid()]
	return not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


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
