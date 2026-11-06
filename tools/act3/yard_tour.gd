extends Node
## A look round the Quarantine Yard (Act III hub). Run this scene from the editor (F6).
## Boots main.tscn in the yard with NO character slot loaded (nothing is saved), then moves the
## player to each spot in `tour`, one every `every` seconds, in a loop.

const MAIN := "res://scenes/map/main.tscn"
const YARD := "res://scenes/map/town/act_3_quarantine_yard.tscn"

@export var tour: Array[Vector3] = [Vector3(28.5, 1.2, 30), Vector3(36, 1.2, 34), Vector3(42, 1.2, 29),
		Vector3(36, 1.2, 25.5), Vector3(32, 1.2, 40)]
@export var every := 6.0

var _i := -1
var _t := 0.0


func _ready() -> void:
	_boot.call_deferred()


func _boot() -> void:
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


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("players") as Node3D
	var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
	if player == null or am == null or am.is_busy() or am.current_area == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = every
	_i = (_i + 1) % tour.size()
	player.global_position = am.current_area.to_global(tour[_i])   # the Map node is rotated
	print("[YARD TOUR] spot %d %s" % [_i, tour[_i]])
