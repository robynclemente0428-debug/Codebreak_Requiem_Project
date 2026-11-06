extends Node
## Checks "every finished run sets off a breach": boots main.tscn inside a convoy stop with NO
## character slot loaded (nothing is saved), pretends this stop was already finished
## `prior_runs` times with a breach after each (so it isn't the first run), walks the player
## into the stop's exit portal, and reports whether that stop's breach starts back aboard.

const MAIN := "res://scenes/map/main.tscn"
@export var dungeon := "res://scenes/map/dungeon/act_2_road_gate.tscn"
@export var stop := "act2_gate"
@export var prior_runs := 1

var _phase := 0          # 0 boot, 1 in the dungeon, 2 walked out, 3 done
var _t := 0.0


func _ready() -> void:
	_boot.call_deferred()


func _boot() -> void:
	var main: Node = load(MAIN).instantiate()
	for n in main.find_children("*", "", true, false):
		if n is AreaManager:
			n.start_area = dungeon
	reparent(get_tree().root)
	var old := get_tree().current_scene
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	if old != null and old != self:
		old.queue_free()
	print("[RUN TEST] booting %s, party=%s (empty = nothing saved)" % [dungeon, SaveManager.party])


func _process(delta: float) -> void:
	_t += delta
	var player := get_tree().get_first_node_in_group("players") as Node3D
	var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
	if player == null or am == null or am.is_busy():
		return
	var qm := player.get("quests") as QuestManager
	match _phase:
		0:
			if am.current_scene_path() != dungeon or not am.can_go():
				return
			var exit := _exit_portal(am)
			if exit == null:
				return
			qm.deeds["%s:%s" % [Waypoints.FINISH_DEED, stop]] = prior_runs
			qm.deeds["%s:%s" % [HullBreach.DEED, stop]] = prior_runs
			print("[RUN TEST] in %s; finished %d, breaches %d. Walking out the exit." % [
				stop, prior_runs, prior_runs])
			player.global_position = exit.global_position + Vector3.UP * 0.1
			print("[RUN TEST] exit portal: visible=%s sealed=%s (key '%s') target=%s" % [
				exit.visible, exit.is_sealed(), exit.sealed_by_key, exit.target_area])
			if exit.is_sealed():
				# The stop's boss lock: pretend the player has the key, like killing the boss would
				qm.recover(exit.sealed_by_key)
				print("[RUN TEST] recovered '%s' to open it" % exit.sealed_by_key)
			exit._on_body_entered(player)               # what walking into it calls
			_phase = 1
			_t = 0.0
		1:
			if am.current_scene_path() == dungeon:
				if _t > 3.0:
					print("[RUN TEST] FAIL: still in the dungeon after walking into the exit")
					_phase = 3
				return
			print("[RUN TEST] arrived at %s; finished now %d, breaches %d" % [am.current_scene_path(),
				qm.deed_count(Waypoints.FINISH_DEED, stop), qm.deed_count(HullBreach.DEED, stop)])
			_phase = 2
			_t = 0.0
		2:
			for b in get_tree().get_nodes_in_group("hull_breach"):
				if b.is_running():
					print("[RUN TEST] PASS: %s started (%s), %.1fs after arriving" % [b.name, b.after_stop, _t])
					_phase = 3
					return
			if _t > 15.0:
				var due: Array[String] = []
				for b in get_tree().get_nodes_in_group("hull_breach"):
					if b.is_due():
						due.append(b.name)
				print("[RUN TEST] FAIL: no breach 15s after arriving (due: %s)" % [due])
				_phase = 3


func _exit_portal(am: AreaManager) -> Node3D:
	if am.current_area == null:
		return null
	for p in am.current_area.find_children("*", "Portal", true, false):
		if (p as Portal).clears_stop == stop:
			return p
	return null
