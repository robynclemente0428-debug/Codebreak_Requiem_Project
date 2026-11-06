extends Node
## Checks that Act II's bosses roll modifiers. Run this scene from the editor (F6). Boots main.tscn
## on the convoy with NO character slot loaded (nothing is saved), then visits each boss's area
## `visits` times and writes what spawned to `result_file`.

const MAIN := "res://scenes/map/main.tscn"
const CONVOY := "res://scenes/map/town/act_2_convoy.tscn"
const BOSSES := {
	"act2_scrapline": "loop_hound_alpha",
	"act2_signal": "the_overflow",
	"act2_relay": "hollow_choir",
	"act2_approach": "perimeter_warden",
}

@export var visits := 2
@export var result_file := "res://tools/act2/boss_modifiers_results.txt"

var _lines: PackedStringArray = []
var _fails := 0


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
	await _until(_settled.bind(CONVOY), 30.0)
	var act := Waypoints.act_of_scene(CONVOY)
	for id in BOSSES:
		var w: Waypoint = act.find(id)
		for i in visits:
			_am().go_to(w.scene, w.spawn_id, w.dungeon_level)
			await _until(_settled.bind(Waypoints.normalize(w.scene)), 60.0)
			await get_tree().create_timer(0.5, true).timeout
			_report(BOSSES[id])
			if i + 1 < visits:                       # leave, so the next visit spawns it again
				_am().go_to(CONVOY, &"", 0)
				await _until(_settled.bind(CONVOY), 30.0)
	_log("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)


func _report(boss_id: String) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if str(e.get_meta(&"enemy_id", "")) == boss_id:
			var mods: Array = e.get("modifiers")
			if mods.is_empty():
				_fails += 1
			_log("%s  %s: %s (%d modifiers)" % ["ok  " if not mods.is_empty() else "FAIL", boss_id, e.display_name, mods.size()])
			return
	_fails += 1
	_log("FAIL  %s is not there" % boss_id)


func _log(text: String) -> void:
	print("[ACT2] ", text)
	_lines.append(text)
	var f := FileAccess.open(result_file, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _settled(path: String) -> bool:
	var am := _am()
	return get_tree().get_first_node_in_group("players") != null and am != null \
			and am.current_area != null and am.can_go() \
			and Waypoints.normalize(am.current_scene_path()) == path


func _am() -> AreaManager:
	return get_tree().get_first_node_in_group("area_manager") as AreaManager


func _until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout and not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
