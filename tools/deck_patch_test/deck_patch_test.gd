extends Node
## Try the deck systems' PATCH puzzles. Run this scene from the editor (F6).
## Boots main.tscn straight onto the convoy with NO character slot loaded (SaveManager.party is
## empty, so save_party() writes nothing: no save is touched), and knocks every DeckSystem
## OFFLINE as if a breach had wrecked it. Walk up to one and interact (PATCH CODE) to fix it.
## No breach runs here (no convoy stop is marked cleared).

const MAIN := "res://scenes/map/main.tscn"
const CONVOY := "res://scenes/map/town/act_2_convoy.tscn"

## Which systems to knock out ("power", "cargo", "comms").
@export var knock_out: Array[String] = ["power", "cargo", "comms"]
## Seconds between knocking each one out (0 = all at once), to watch each one go.
@export var stagger := 0.0

## For a look round: nodes in the convoy (paths from its root) to move the player next to, one
## every tour_every seconds, in a loop. Empty = stay put.
@export var tour: Array[String] = []
@export var tour_every := 5.0

var _done := false
var _queue: Array = []
var _wait := 0.0
var _tour_i := -1
var _tour_t := 0.0


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
	print("[PATCH TEST] booting convoy, party=%s (empty = nothing saved)" % [SaveManager.party])


func _process(delta: float) -> void:
	_tour_step(delta)
	if _done:
		return
	if _queue.is_empty():
		if get_tree().get_first_node_in_group("players") == null:
			return
		for id in knock_out:
			var sys := DeckSystem.find(get_tree(), id)
			if sys != null:
				_queue.append(sys)
		if _queue.is_empty():
			return
		_wait = stagger
	_wait -= delta
	if _wait > 0.0 and stagger > 0.0:
		return
	_wait = stagger
	var sys = _queue.pop_front()
	if not sys.is_offline():
		sys._go_offline()
	print("[PATCH TEST] %s offline: %s" % [sys.npc_name, sys.is_offline()])
	if not _queue.is_empty():
		if stagger <= 0.0:
			_process(0.0)                               # all at once
		return
	_done = true
	_toast_done()


func _tour_step(delta: float) -> void:
	if tour.is_empty():
		return
	var player := get_tree().get_first_node_in_group("players") as Node3D
	var area := get_tree().get_first_node_in_group(DeckSystem.GROUP)
	if player == null or area == null:
		return
	_tour_t -= delta
	if _tour_t > 0.0:
		return
	_tour_t = tour_every
	_tour_i = (_tour_i + 1) % tour.size()
	var root := (area as Node).owner if (area as Node).owner != null else area.get_parent().get_parent()
	var spot := root.get_node_or_null(tour[_tour_i]) as Node3D
	if spot != null:
		player.global_position = spot.global_position + Vector3(0.0, 0.2, 2.5)
		print("[PATCH TEST] tour: at %s" % tour[_tour_i])


func _toast_done() -> void:
	QuestItems.toast(get_tree(), "PATCH TEST\nDeck systems OFFLINE: %s. Walk up to one and PATCH CODE." % ", ".join(knock_out), DeckSystem.COL_HIT)
