extends Node
## Opens the Warden's handshake.prog on its own (no world, no save), to drag its lines.
## Run this scene from the editor (F6).
##   auto_check on:  checks the drop logic (what letting go of a dragged line does), then puts the
##                   lines back as they were and leaves the panel open
##   then:           drag "receive" to the top and "sign" under it with the mouse, and RUN TESTS
## Prints [DRAG] lines: the order after every change, and SOLVED when the tests pass.

const PatchPanelScript := preload("res://scenes/map/town/convoy/patch_panel.gd")

@export var auto_check := true

var _panel
var _last := ""
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open.call_deferred()


func _open() -> void:
	var puzzle = PatchPanelScript.warden_puzzle("w_handshake")
	PatchPanelScript.open_challenge(get_tree(), puzzle, null, "Drag Test", self, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_panel = get_tree().get_first_node_in_group(PatchPanelScript.GROUP)
	_check("its three lines can be dragged", _holders() == 3)
	if not auto_check:
		return
	var start: Array = _panel.puzzle.order.duplicate()
	_drop(2, 0)
	_check("receive dropped on the top line -> %s" % [_panel.puzzle.order], _panel.puzzle.order == ["receive", "reply", "sign"])
	_drop(2, 1)
	_check("sign dropped on the middle line -> %s" % [_panel.puzzle.order], _panel.puzzle.order == ["receive", "sign", "reply"])
	_drop(0, 0)
	_check("a line dropped on itself stays put", _panel.puzzle.order == ["receive", "sign", "reply"])
	_drop(0, 2)
	_check("the top line dropped on the bottom one -> %s" % [_panel.puzzle.order], _panel.puzzle.order == ["sign", "reply", "receive"])
	_check("the lines can still be dragged after a drop", _holders() == 3)
	_check("dragging something else doesn't drop", not _panel._can_drop_line(Vector2.ZERO, {"other": 1}, null, 0))
	_panel.puzzle.order = start
	_panel._rebuild()
	_log("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	_log("now drag them yourself: receive to the top, sign under it, then RUN TESTS")


## What letting go of a dragged line does (PatchPanel._drop_line), from slot `from` onto `to`.
func _drop(from: int, to: int) -> void:
	_panel._drop_line(Vector2.ZERO, {"patch_line": from}, to)


func _holders() -> int:
	var n := 0
	for c in _panel._code.get_children():
		if c is PanelContainer and c.has_meta(&"slot") and not c.is_queued_for_deletion():
			n += 1
	return n


func _process(_delta: float) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var order := str(_panel.puzzle.order)
	if order != _last:
		_last = order
		_log("order: " + order)


func challenge_solved() -> void:
	_log("SOLVED")


func challenge_failed() -> bool:
	_log("wrong answer")
	return false


func challenge_abandoned() -> void:
	_log("closed")


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	_log("%s  %s" % ["ok  " if ok else "FAIL", what])


func _log(text: String) -> void:
	print("[DRAG] ", text)
