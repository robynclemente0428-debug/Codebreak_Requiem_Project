extends Node
## Playtest harness for a convoy HullBreach. Run this scene from the editor (F6).
## Boots main.tscn straight onto the convoy with NO character slot loaded (SaveManager.party is
## empty, so save_party() writes nothing: no save is touched). Marks STOP cleared in memory only,
## parks an unkillable, idle player at the route terminal, and prints the deck systems' integrity
## every LOG_EVERY seconds until the breach ends. Read the numbers from the Output panel.

const MAIN := "res://scenes/map/main.tscn"
const CONVOY := "res://scenes/map/town/act_2_convoy.tscn"
## The breach to run: its after_stop.
@export var stop := "act2_scrapline"
@export var log_every := 2.0
@export var time_limit := 180.0

var _breach: Node
var _player: Node3D
var _t := 0.0
var _log_t := 0.0
var _started_at := -1.0
var _down_at: Dictionary = {}        # system name -> seconds into the breach


func _ready() -> void:
	_boot.call_deferred()


func _boot() -> void:
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
	print("[BREACH TEST] booting convoy, party=%s (empty = nothing saved)" % [SaveManager.party])


func _process(delta: float) -> void:
	_t += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("players") as Node3D
		if _player == null:
			return
		Waypoints.is_cleared(null)                 # load (empty, no slot) before we add to it
		Waypoints._cleared[stop] = true
		var qm := _player.get("quests") as QuestManager
		var key := "%s:%s" % [Waypoints.FINISH_DEED, stop]
		qm.deeds[key] = qm.deed_count(HullBreach.DEED, stop) + 1     # one finished run owed a breach
		print("[BREACH TEST] player in, a run through %s marked finished (memory only)" % stop)
	if _breach == null:
		for b in get_tree().get_nodes_in_group("hull_breach"):
			if b.after_stop == stop:
				_breach = b
		if _breach == null:
			return
		print("[BREACH TEST] breach %s: saboteur_every=%d" % [_breach.name, _breach.saboteur_every])
	# Unkillable, parked at the route terminal (so the hold runs, and nobody defends the systems)
	var hp = _player.get("health")
	if hp != null:
		hp.current_health = 1e9
	var term = _breach._find_portal()
	if term != null and _player.global_position.distance_to(term.global_position) > 3.0:
		_player.global_position = term.global_position + Vector3(0, 0.2, 2.0)
	var running: bool = _breach.is_running()
	if running and _started_at < 0.0:
		_started_at = _t
		print("[BREACH TEST] breach started at %.1fs" % _t)
	if _started_at < 0.0:
		if _t > 30.0 and fmod(_t, 5.0) < delta:
			print("[BREACH TEST] still waiting to start (state %d)" % _breach.state)
		return
	var since := _t - _started_at
	for sys in _breach._systems:
		if is_instance_valid(sys) and sys.is_offline() and not _down_at.has(sys.npc_name):
			_down_at[sys.npc_name] = since
			print("[BREACH TEST] %s OFFLINE at %.1fs" % [sys.npc_name, since])
	_log_t -= delta
	if _log_t <= 0.0:
		_log_t = log_every
		var parts: Array[String] = []
		for sys in _breach._systems:
			if is_instance_valid(sys):
				parts.append("%s %d (%d at it)" % [sys.system_id, ceili(sys.integrity), sys.attackers(_breach._alive)])
		print("[BREACH TEST] t=%5.1f wave=%d state=%d hold=%3d%% alive=%d saboteurs=%d | %s" % [
			since, _breach._wave, _breach.state, int(_breach.progress * 100.0), _breach._alive.size(),
			_breach._saboteurs.size(), ", ".join(parts)])
	if _breach.state == 3 or since > time_limit:
		print("[BREACH TEST] END state=%d at %.1fs, offline: %s" % [_breach.state, since, _down_at])
		set_process(false)
