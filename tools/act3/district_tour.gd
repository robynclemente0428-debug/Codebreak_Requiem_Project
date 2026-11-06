extends Node
## A look round Act III's districts. Run this scene from the editor (F6). Boots main.tscn with NO
## character slot loaded (nothing is saved), then goes to each district in `tour` and stands the
## player `boss_distance` metres from its boss (or at its entrance), `every` seconds each. The
## enemies are switched off and the player is kept alive, so you can look.

const MAIN := "res://scenes/map/main.tscn"
const YARD := "res://scenes/map/town/act_3_quarantine_yard.tscn"

@export var tour: Array[String] = ["act3_sweep", "act3_mirror_dock", "act3_heap", "act3_registry",
		"act3_dangling_quarter", "act3_mark_yards"]
@export var every := 14.0
@export var boss_distance := 2.0

var _i := -1


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
	await _settle(YARD)
	var act := Waypoints.act_of_scene(YARD)
	while true:
		_i = (_i + 1) % tour.size()
		var w: Waypoint = act.find(tour[_i])
		_am().go_to(w.scene, w.spawn_id, w.dungeon_level)
		await _settle(w.scene)
		var boss: Node3D = null
		for e in get_tree().get_nodes_in_group("enemies"):
			if (e.get_meta(&"act_boss", false)):
				boss = e
			else:
				e.process_mode = Node.PROCESS_MODE_DISABLED
		if boss != null:
			(boss.get("ai") as Node).process_mode = Node.PROCESS_MODE_DISABLED
			_player().global_position = boss.global_position + Vector3(0, 0, boss_distance)
		print("[TOUR] %s %s" % [w.display_name, boss.name if boss != null else "(no boss)"])
		await get_tree().create_timer(every, true).timeout


func _process(_delta: float) -> void:
	if _player() != null:
		_player().get("health").heal(100000.0)


func _settle(path: String) -> void:
	while not (_player() != null and _am() != null and _am().current_area != null and _am().can_go() \
			and Waypoints.normalize(_am().current_scene_path()) == path):
		await get_tree().process_frame
	await get_tree().create_timer(0.5, true).timeout


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


func _am() -> AreaManager:
	return get_tree().get_first_node_in_group("area_manager") as AreaManager
