extends CanvasLayer

const FONT_PATH := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const GROUP := "patch_panel"
const ACCENT := Color("#00E5FF")
const COLS := {
	"kw": Color(0.82, 0.55, 1.0),
	"fn": Color(1.0, 0.80, 0.40),
	"var": Color(0.45, 0.82, 1.0),
	"num": Color(1.0, 0.62, 0.35),
	"op": Color(0.80, 0.86, 0.90),
	"cm": Color(0.42, 0.58, 0.55),
}
const COL_GUTTER := Color(0.35, 0.48, 0.55)
const COL_OK := Color(0.30, 0.95, 0.60)
const COL_BAD := Color(1.0, 0.40, 0.40)
const COL_BG := Color(0.02, 0.04, 0.06, 0.97)
const CODE_SIZE := 18
const WIDTH := 820.0

var system: Node3D
var puzzle: Puzzle
var _player: Node
var _font: Font
var _code: VBoxContainer
var _out: RichTextLabel
var _run: Button
var _done := false
var _handler: Object
var _title := ""
var time_limit := 0.0
var _time_left := 0.0
var _clock: Label


static func open(system_: Node3D, player: Node) -> void:
	var tree := system_.get_tree()
	if tree.get_first_node_in_group(GROUP) != null:
		return
	var p = load("res://scenes/map/town/convoy/patch_panel.gd").new()
	p.system = system_
	p._player = player
	p.puzzle = Puzzle.make(str(system_.get("system_id")))
	tree.root.add_child(p)


static func open_challenge(tree: SceneTree, puzzle_: Puzzle, player: Node, title: String,
		handler: Object, seconds: float) -> bool:
	if tree.get_first_node_in_group(GROUP) != null:
		return false
	var p = load("res://scenes/map/town/convoy/patch_panel.gd").new()
	p.puzzle = puzzle_
	p._player = player
	p._title = title
	p._handler = handler
	p.time_limit = seconds
	tree.root.add_child(p)
	return true


func is_challenge() -> bool:
	return _handler != null


func _ready() -> void:
	layer = 21
	add_to_group(GROUP)
	if is_challenge():
		process_mode = Node.PROCESS_MODE_ALWAYS
		if not Coop.in_game:
			get_tree().paused = true
		_time_left = time_limit
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	_build()
	_lock(true)
	_rebuild()
	_print([["Edit the code, then RUN TESTS.", true]], false)


func _exit_tree() -> void:
	_lock(false)
	if is_challenge():
		get_tree().paused = false


func _process(delta: float) -> void:
	if not is_challenge() or _done or time_limit <= 0.0:
		return
	_time_left -= delta
	if _clock != null:
		_clock.text = "TIME  %ds" % maxi(ceili(_time_left), 0)
		_clock.add_theme_color_override("font_color", COL_BAD if _time_left < 10.0 else COL_GUTTER)
	if _time_left <= 0.0:
		_done = true
		_close_unsolved()


func _lock(on: bool) -> void:
	if _player != null and is_instance_valid(_player) and "input_locked" in _player:
		_player.input_locked = on


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if is_challenge() and not _done:
		_done = true
		_close_unsolved()
		return
	queue_free()


func _close_unsolved() -> void:
	var h := _handler
	queue_free()
	if h != null and is_instance_valid(h) and h.has_method("challenge_abandoned"):
		h.challenge_abandoned()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var frame := PanelContainer.new()
	frame.custom_minimum_size.x = WIDTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG
	sb.border_color = ACCENT
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	frame.add_theme_stylebox_override("panel", sb)
	centre.add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	frame.add_child(v)
	var name_ := str(system.get("npc_name")).to_upper() if system != null else "SYSTEM"
	if is_challenge():
		v.add_child(_label("// CHALLENGE // %s // %s" % [_title.to_upper(), puzzle.file], 20, COL_BAD))
		if time_limit > 0.0:
			_clock = _label("TIME  %ds" % ceili(time_limit), 15, COL_GUTTER)
			v.add_child(_clock)
	else:
		v.add_child(_label("// PATCH // %s // %s" % [name_, puzzle.file], 20, ACCENT))
	var brief := _label(puzzle.brief, 16, Color(0.82, 0.92, 0.96))
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(brief)
	var code_frame := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.0, 0.02, 0.03, 1.0)
	csb.border_color = Color(ACCENT, 0.3)
	csb.set_border_width_all(1)
	csb.set_content_margin_all(10)
	code_frame.add_theme_stylebox_override("panel", csb)
	v.add_child(code_frame)
	_code = VBoxContainer.new()
	_code.add_theme_constant_override("separation", 2)
	code_frame.add_child(_code)
	var hint := _label("click a number or operator: change it   right-click / wheel: the other way   drag a :: line: move it",
			13, COL_GUTTER)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(hint)
	var out_title := _label("OUTPUT", 14, COL_GUTTER)
	out_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(out_title)
	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.fit_content = true
	_out.scroll_active = false
	_out.custom_minimum_size.y = 96
	if _font:
		_out.add_theme_font_override("normal_font", _font)
	_out.add_theme_font_size_override("normal_font_size", 15)
	v.add_child(_out)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	v.add_child(buttons)
	var close_b := _button("WALK AWAY (ESC)" if is_challenge() else "CLOSE (ESC)")
	close_b.pressed.connect(close)
	buttons.add_child(close_b)
	_run = _button("RUN TESTS")
	_run.pressed.connect(_on_run)
	buttons.add_child(_run)


func _rebuild() -> void:
	for c in _code.get_children():
		_code.remove_child(c)
		c.queue_free()
	var lines: Array = puzzle.lines()
	for i in lines.size():
		var line: Dictionary = lines[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slot: int = line.get("move", -1)
		if slot >= 0 and not _done:
			_code.add_child(_drag_holder(row, slot, line))
		else:
			_code.add_child(row)
		var num := _tok(str(i + 1), COL_GUTTER)
		num.custom_minimum_size.x = 30
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(num)
		var grip := _tok(" :: " if slot >= 0 and not _done else "", COLS["num"])
		grip.custom_minimum_size.x = 52
		grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(grip)
		row.add_child(_tok("    ".repeat(int(line.get("indent", 0))), COL_GUTTER))
		for t in line["tokens"]:
			if t is Dictionary:
				row.add_child(_edit_tok(t))
			else:
				row.add_child(_tok(t[0], COLS.get(t[1], Color.WHITE)))


func _edited() -> void:
	_rebuild()
	_print([["Changed. RUN TESTS to check it.", true]], false)


func _drag_holder(row: HBoxContainer, slot: int, line: Dictionary) -> PanelContainer:
	var holder := PanelContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_DRAG
	holder.tooltip_text = "drag to move this line"
	holder.add_theme_stylebox_override("panel", _line_style(false))
	holder.set_meta(&"slot", slot)
	holder.add_child(row)
	holder.set_drag_forwarding(_drag_line.bind(holder, slot, line), _can_drop_line.bind(holder, slot),
			_drop_line.bind(slot))
	holder.mouse_entered.connect(func() -> void:
		if not get_viewport().gui_is_dragging():
			holder.add_theme_stylebox_override("panel", _line_style(false, true)))
	holder.mouse_exited.connect(func() -> void:
		if not get_viewport().gui_is_dragging():
			holder.add_theme_stylebox_override("panel", _line_style(false)))
	return holder


func _line_style(target: bool, hover := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ACCENT, 0.16 if target else (0.06 if hover else 0.0))
	sb.border_color = ACCENT
	sb.border_width_top = 2 if target else 0
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


func _drag_line(_at: Vector2, holder: PanelContainer, slot: int, line: Dictionary) -> Variant:
	var text := ""
	for t in line["tokens"]:
		text += str(t["text"]) if t is Dictionary else str(t[0])
	var preview := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COL_BG, 0.95)
	sb.border_color = ACCENT
	sb.set_border_width_all(1)
	sb.set_content_margin_all(6)
	preview.add_theme_stylebox_override("panel", sb)
	preview.add_child(_tok(text, COLS["fn"]))
	holder.set_drag_preview(preview)
	holder.modulate.a = 0.35
	return {"patch_line": slot}


func _can_drop_line(_at: Vector2, data: Variant, holder: PanelContainer, _slot: int) -> bool:
	var ok := data is Dictionary and (data as Dictionary).has("patch_line") and not _done
	_mark_target(holder if ok else null)
	return ok


func _drop_line(_at: Vector2, data: Variant, slot: int) -> void:
	var from := int((data as Dictionary).get("patch_line", slot))
	_mark_target(null)
	if from == slot:
		_rebuild()
		return
	puzzle.move_to(from, slot)
	_edited()


func _mark_target(target: PanelContainer) -> void:
	if _code == null:
		return
	for c in _code.get_children():
		if c is PanelContainer and c.has_meta(&"slot"):
			c.add_theme_stylebox_override("panel", _line_style(c == target))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _code != null:
		_mark_target(null)
		for c in _code.get_children():
			if c is PanelContainer:
				c.modulate.a = 1.0


func _on_run() -> void:
	if _done:
		return
	var results: Array = puzzle.run()
	var all_ok := true
	for r in results:
		all_ok = all_ok and bool(r[1])
	_print(results, true)
	if all_ok:
		_done = true
		_run.disabled = true
		_out.append_text("\n[color=#%s]ALL TESTS PASS // %s[/color]" % [COL_OK.to_html(false),
				"RESPONSE ACCEPTED..." if is_challenge() else "DEPLOYING PATCH..."])
		_rebuild()
		await get_tree().create_timer(1.2).timeout
		if is_challenge():
			var h := _handler
			queue_free()
			if h != null and is_instance_valid(h) and h.has_method("challenge_solved"):
				h.challenge_solved()
			return
		if system != null and is_instance_valid(system) and system.has_method("repair"):
			system.repair()
		close()
	elif is_challenge() and _handler != null and is_instance_valid(_handler):
		_out.append_text("\n[color=#%s]WRONG RESPONSE // THE WARDEN PUNISHES IT[/color]" % COL_BAD.to_html(false))
		if _handler.challenge_failed():
			_done = true
			queue_free()


func _print(lines: Array, verdicts: bool) -> void:
	_out.clear()
	var text := ""
	for r in lines:
		var col := COL_OK if bool(r[1]) else COL_BAD
		if not verdicts:
			col = Color(0.75, 0.85, 0.9)
		var tag := ("[OK]   " if bool(r[1]) else "[FAIL] ") if verdicts else "> "
		text += "[color=#%s]%s%s[/color]\n" % [col.to_html(false), tag, r[0]]
	_out.append_text(text.strip_edges(false, true))


func _tok(text: String, col: Color) -> Label:
	return _label(text, CODE_SIZE, col, false)


func _edit_tok(t: Dictionary) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COLS["num"], 0.10)
	sb.border_color = Color(COLS["num"], 0.6)
	sb.border_width_bottom = 1
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	box.add_theme_stylebox_override("panel", sb)
	box.add_child(_tok(str(t["text"]), COLS["num"]))
	if _done:
		return box
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.tooltip_text = "click: next   right-click: back   wheel: both"
	var id := str(t["edit"])
	box.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton) or not ev.pressed:
			return
		var step := 0
		match ev.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP:
				step = 1
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_DOWN:
				step = -1
		if step != 0:
			box.accept_event()
			puzzle.step(id, step)
			_edited.call_deferred())
	return box


func _label(text: String, size_px: int, col: Color, centred := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	if _font:
		l.add_theme_font_override("font", _font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centred:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 36)
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 16)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(ACCENT, 0.12)
	n.border_color = ACCENT
	n.set_border_width_all(1)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(ACCENT, 0.28)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_color", ACCENT)
	return b


class Puzzle extends RefCounted:
	var file := ""
	var brief := ""

	func lines() -> Array:
		return []

	func step(_id: String, _dir: int) -> void:
		pass

	func move(_slot: int, _dir: int) -> void:
		pass

	func move_to(from: int, to: int) -> void:
		while from < to:
			move(from, 1)
			from += 1
		while from > to:
			move(from, -1)
			from -= 1

	func run() -> Array:
		return []

	static func make(id: String) -> Puzzle:
		match id:
			"cargo":
				return CargoPuzzle.new()
			"comms":
				return CommsPuzzle.new()
			"iff":
				return IffPuzzle.new()
		return PowerPuzzle.new()


class PowerPuzzle extends Puzzle:
	const OPS := ["<", ">", "<=", ">=", "==", "!="]
	const LIMITS := [0, 40, 80, 120, 160, 200]
	var op := 0
	var limit := 3

	func _init() -> void:
		file = "breaker.prog"
		brief = "The Null flipped a check in the breaker: it cuts the market row's power on a normal day " \
				+ "and keeps it on through an overload. Fix it so both tests pass."

	func lines() -> Array:
		return [
			{"tokens": [["# keeps the market row lit; trips on an overload (max safe draw: 120)", "cm"]]},
			{"tokens": [["always", "kw"], [":", "op"]]},
			{"indent": 1, "tokens": [["power_on", "fn"], ["()", "op"]]},
			{"tokens": [["when ", "kw"], ["load", "fn"], ["() ", "op"], {"edit": "op", "text": OPS[op]},
					[" ", "op"], {"edit": "limit", "text": str(LIMITS[limit])}, [":", "op"]]},
			{"indent": 1, "tokens": [["cut_power", "fn"], ["()", "op"], ["      # trip the breaker", "cm"]]},
		]

	func step(id: String, dir: int) -> void:
		if id == "op":
			op = posmod(op + dir, OPS.size())
		else:
			limit = posmod(limit + dir, LIMITS.size())

	func run() -> Array:
		var out := []
		for case in [["a normal day", 40, false], ["an overload", 160, true]]:
			var cut := _compare(int(case[1]), OPS[op], LIMITS[limit])
			out.append(["%s: load %d -> power %s (should be %s)" % [case[0], case[1],
					"CUT" if cut else "ON", "CUT" if case[2] else "ON"], cut == case[2]])
		return out

	static func _compare(a: int, o: String, b: int) -> bool:
		match o:
			"<": return a < b
			">": return a > b
			"<=": return a <= b
			">=": return a >= b
			"==": return a == b
		return a != b


class CargoPuzzle extends Puzzle:
	const BOLTS := 3
	var count := 5

	func _init() -> void:
		file = "seal.prog"
		brief = "The Null changed the seal's loop: it tries to drive bolts the hold door doesn't have, " \
				+ "and the bolt drive jams. Make it drive every bolt, and only those."

	func lines() -> Array:
		return [
			{"tokens": [["# the hold door has 3 bolts: bolt 0, 1 and 2", "cm"]]},
			{"tokens": [["when ", "kw"], ["door_closed", "fn"], ["():", "op"]]},
			{"indent": 1, "tokens": [["for ", "kw"], ["i", "var"], [" in ", "kw"], ["range", "fn"], ["(", "op"],
					{"edit": "count", "text": str(count)}, ["):", "op"]]},
			{"indent": 2, "tokens": [["drive_bolt", "fn"], ["(", "op"], ["i", "var"], [")", "op"]]},
			{"indent": 1, "tokens": [["lock", "fn"], ["()", "op"]]},
		]

	func step(_id: String, dir: int) -> void:
		count = clampi(count + dir, 1, 6)

	func run() -> Array:
		var driven := mini(count, BOLTS)
		var out := [["drive_bolt(0..%d): %d of %d bolts home" % [driven - 1, driven, BOLTS], driven == BOLTS]]
		if count > BOLTS:
			out.append(["drive_bolt(%d): NO SUCH BOLT, the drive jams" % BOLTS, false])
		else:
			out.append(["no stray bolts driven", true])
		out.append(["lock(): the seal %s" % ("holds" if count == BOLTS else "won't hold"), count == BOLTS])
		return out


class CommsPuzzle extends Puzzle:
	const TEXT := {"power_on": [["power_on", "fn"], ["()", "op"]],
			"tune": [["tune", "fn"], ["(", "op"], ["band", "var"], ["=", "op"], ["7", "num"], [")", "op"]],
			"transmit": [["transmit", "fn"], ["(", "op"], ["convoy_id", "var"], [")", "op"]]}
	var order := ["transmit", "tune", "power_on"]

	func _init() -> void:
		file = "relay.prog"
		brief = "The Null shuffled the relay's start-up: it transmits before it's switched on, so the " \
				+ "signal never goes out. Put the steps in the order that works."

	func lines() -> Array:
		var out := [
			{"tokens": [["# start-up: the convoy's signal on band 7", "cm"]]},
			{"tokens": [["always", "kw"], [":", "op"]]},
		]
		for i in order.size():
			out.append({"indent": 1, "move": i, "tokens": TEXT[order[i]]})
		return out

	func move(slot: int, dir: int) -> void:
		var to := slot + dir
		if to < 0 or to >= order.size():
			return
		var a = order[slot]
		order[slot] = order[to]
		order[to] = a

	func run() -> Array:
		var on := false
		var tuned := false
		var out := []
		for s in order:
			match s:
				"power_on":
					on = true
					out.append(["power_on(): relay on", true])
				"tune":
					if on:
						tuned = true
						out.append(["tune(band=7): locked on", true])
					else:
						out.append(["tune(band=7): no power, nothing to tune", false])
				"transmit":
					if not on:
						out.append(["transmit(): the relay is off", false])
					elif not tuned:
						out.append(["transmit(): untuned, the signal is noise", false])
					else:
						out.append(["transmit(): signal out, the convoy is back on the net", true])
		return out


class IffPuzzle extends Puzzle:
	const OPS := ["==", "!="]
	const STATUSES := ["INBOUND", "DELETED", "DOCKED"]
	const RECORDS := [
		{"n": 1, "status": "DELETED", "note": "arrived 11 days ago, flagged NULL, deleted"},
		{"n": 2, "status": "INBOUND", "note": "the convoy on approach"},
	]
	var op := 1
	var status := 0

	func _init() -> void:
		file = "iff.prog"
		brief = "Checkpoint's guns challenged us and the transponder answered with the wrong record, " \
				+ "so they read us as Null. Its registry has two Hardfaults. Make it answer as ours."

	func lines() -> Array:
		return [
			{"tokens": [["# Checkpoint's registry, sent with the challenge:", "cm"]]},
			{"tokens": [["#   record 1  HARDFAULT  DELETED   arrived 11 days ago, flagged NULL", "cm"]]},
			{"tokens": [["#   record 2  HARDFAULT  INBOUND", "cm"]]},
			{"tokens": [["when ", "kw"], ["challenged", "fn"], ["():", "op"]]},
			{"indent": 1, "tokens": [["rec", "var"], [" = ", "op"], ["registry", "var"], [".", "op"],
					["find", "fn"], ["(", "op"], ["name", "var"], [" == ", "op"], ["\"HARDFAULT\"", "num"],
					[", ", "op"], ["status", "var"], [" ", "op"], {"edit": "op", "text": OPS[op]},
					[" ", "op"], {"edit": "status", "text": STATUSES[status]}, [")", "op"]]},
			{"indent": 1, "tokens": [["answer", "fn"], ["(", "op"], ["rec", "var"], [")", "op"],
					["      # the guns hold fire for a live record", "cm"]]},
		]

	func step(id: String, dir: int) -> void:
		if id == "op":
			op = posmod(op + dir, OPS.size())
		else:
			status = posmod(status + dir, STATUSES.size())

	func run() -> Array:
		var found := []
		for r in RECORDS:
			var same: bool = r["status"] == STATUSES[status]
			if same == (OPS[op] == "=="):
				found.append(r)
		var out := [["registry.find(): %d record%s match%s" % [found.size(),
				"" if found.size() == 1 else "s", "es" if found.size() == 1 else ""], found.size() == 1]]
		if found.is_empty():
			out.append(["answer(nothing): no answer, the guns read silence as Null -> FIRE", false])
		elif found.size() > 1:
			out.append(["answer(records 1 and 2): two of us at once, the guns read a copy -> FIRE", false])
		elif int(found[0]["n"]) == 1:
			out.append(["answer(record 1): HARDFAULT, %s -> FIRE" % found[0]["note"], false])
		else:
			out.append(["answer(record 2): HARDFAULT, INBOUND -> HOLD FIRE", true])
		return out


const WARDEN_PUZZLES := ["w_crowd", "w_ping", "w_vitals", "w_handshake", "w_identify"]


static func warden_puzzle(id: String) -> Puzzle:
	match id:
		"w_crowd":
			return WardenCrowdPuzzle.new()
		"w_ping":
			return WardenPingPuzzle.new()
		"w_vitals":
			return WardenVitalsPuzzle.new()
		"w_handshake":
			return WardenHandshakePuzzle.new()
	return WardenIdentifyPuzzle.new()


class WardenCrowdPuzzle extends Puzzle:
	const OPS := ["<", ">", "<=", ">=", "==", "!="]
	var op := 0
	var count := 3

	func _init() -> void:
		file = "crowd.prog"
		brief = "CHALLENGE: prove you read a crowd. Answer when 3 or more enemies are close, " \
				+ "and stay silent when fewer are."

	func lines() -> Array:
		return [
			{"tokens": [["# the Warden sends 2, then 3, then 5 drones at you", "cm"]]},
			{"tokens": [["when ", "kw"], ["enemies_nearby", "fn"], ["() ", "op"], {"edit": "op", "text": OPS[op]},
					[" ", "op"], {"edit": "count", "text": str(count)}, [":", "op"]]},
			{"indent": 1, "tokens": [["answer", "fn"], ["()", "op"]]},
		]

	func step(id: String, dir: int) -> void:
		if id == "op":
			op = posmod(op + dir, OPS.size())
		else:
			count = clampi(count + dir, 1, 6)

	func run() -> Array:
		var out := []
		for n in [2, 3, 5]:
			var fired := _cmp(n, OPS[op], count)
			var want: bool = n >= 3
			out.append(["%d drones close: %s (should %s)" % [n, "ANSWER" if fired else "silent",
					"answer" if want else "stay silent"], fired == want])
		return out

	static func _cmp(a: int, o: String, b: int) -> bool:
		match o:
			"<": return a < b
			">": return a > b
			"<=": return a <= b
			">=": return a >= b
			"==": return a == b
		return a != b


class WardenPingPuzzle extends Puzzle:
	const PINGS := 4
	var count := 2

	func _init() -> void:
		file = "ping.prog"
		brief = "CHALLENGE: the Warden sends 4 pings and waits for a reply to each one. " \
				+ "Reply to every ping, and to nothing that wasn't sent."

	func lines() -> Array:
		return [
			{"tokens": [["# pings 0, 1, 2 and 3 are waiting", "cm"]]},
			{"tokens": [["when ", "kw"], ["challenged", "fn"], ["():", "op"]]},
			{"indent": 1, "tokens": [["for ", "kw"], ["i", "var"], [" in ", "kw"], ["range", "fn"], ["(", "op"],
					{"edit": "count", "text": str(count)}, ["):", "op"]]},
			{"indent": 2, "tokens": [["reply", "fn"], ["(", "op"], ["ping", "var"], ["[", "op"], ["i", "var"], ["])", "op"]]},
		]

	func step(_id: String, dir: int) -> void:
		count = clampi(count + dir, 1, 7)

	func run() -> Array:
		var answered := mini(count, PINGS)
		var out := [["reply(ping[0..%d]): %d of %d pings answered" % [answered - 1, answered, PINGS],
				answered == PINGS]]
		if count > PINGS:
			out.append(["reply(ping[%d]): NO SUCH PING, the Warden reads a forged reply" % PINGS, false])
		else:
			out.append(["no replies to pings that weren't sent", true])
		return out


class WardenVitalsPuzzle extends Puzzle:
	const OPS := ["<", ">", "<=", ">=", "==", "!="]
	const LIMITS := [25, 40, 50, 65, 80]
	var op := 1
	var limit := 2

	func _init() -> void:
		file = "vitals.prog"
		brief = "CHALLENGE: show you know when you're hurt. Raise a guard below half life, " \
				+ "and only then."

	func lines() -> Array:
		return [
			{"tokens": [["# half life is 50%", "cm"]]},
			{"tokens": [["when ", "kw"], ["my_life", "fn"], ["() ", "op"], {"edit": "op", "text": OPS[op]},
					[" ", "op"], {"edit": "limit", "text": str(LIMITS[limit])}, ["%:", "op"]]},
			{"indent": 1, "tokens": [["guard", "fn"], ["()", "op"]]},
		]

	func step(id: String, dir: int) -> void:
		if id == "op":
			op = posmod(op + dir, OPS.size())
		else:
			limit = posmod(limit + dir, LIMITS.size())

	func run() -> Array:
		var out := []
		for life in [30, 60, 90]:
			var fired := _cmp(life, OPS[op], LIMITS[limit])
			var want: bool = life < 50
			out.append(["life %d%%: %s (should %s)" % [life, "GUARD" if fired else "no guard",
					"guard" if want else "not guard"], fired == want])
		return out

	static func _cmp(a: int, o: String, b: int) -> bool:
		match o:
			"<": return a < b
			">": return a > b
			"<=": return a <= b
			">=": return a >= b
			"==": return a == b
		return a != b


class WardenHandshakePuzzle extends Puzzle:
	const TEXT := {"receive": [["receive", "fn"], ["(", "op"], ["challenge", "var"], [")", "op"]],
			"sign": [["sign", "fn"], ["(", "op"], ["challenge", "var"], [", ", "op"], ["our_key", "var"], [")", "op"]],
			"reply": [["reply", "fn"], ["(", "op"], ["signature", "var"], [")", "op"]]}
	var order := ["reply", "sign", "receive"]

	func _init() -> void:
		file = "handshake.prog"
		brief = "CHALLENGE: a handshake has an order. Take the challenge in, sign it with our key, " \
				+ "then send the signature back."

	func lines() -> Array:
		var out := [{"tokens": [["when ", "kw"], ["challenged", "fn"], ["():", "op"]]}]
		for i in order.size():
			out.append({"indent": 1, "move": i, "tokens": TEXT[order[i]]})
		return out

	func move(slot: int, dir: int) -> void:
		var to := slot + dir
		if to < 0 or to >= order.size():
			return
		var a = order[slot]
		order[slot] = order[to]
		order[to] = a

	func run() -> Array:
		var got := false
		var signed := false
		var out := []
		for s in order:
			match s:
				"receive":
					got = true
					out.append(["receive(): challenge in", true])
				"sign":
					if got:
						signed = true
						out.append(["sign(): signed with our key", true])
					else:
						out.append(["sign(): nothing to sign yet", false])
				"reply":
					if signed:
						out.append(["reply(): signature sent, the Warden checks it", true])
					else:
						out.append(["reply(): an unsigned reply, read as forged", false])
		return out


class WardenIdentifyPuzzle extends Puzzle:
	const OPS := ["==", "!="]
	const STATUSES := ["DELETED", "INBOUND", "DOCKED"]
	var op := 0
	var status := 0

	func _init() -> void:
		file = "identify.prog"
		brief = "CHALLENGE: identify yourself. The registry still holds both Hardfaults. " \
				+ "Name the one that is you."

	func lines() -> Array:
		return [
			{"tokens": [["#   record 1  HARDFAULT  DELETED   flagged NULL", "cm"]]},
			{"tokens": [["#   record 2  HARDFAULT  INBOUND", "cm"]]},
			{"tokens": [["when ", "kw"], ["challenged", "fn"], ["():", "op"]]},
			{"indent": 1, "tokens": [["identify", "fn"], ["(", "op"], ["status", "var"], [" ", "op"],
					{"edit": "op", "text": OPS[op]}, [" ", "op"], {"edit": "status", "text": STATUSES[status]}, [")", "op"]]},
		]

	func step(id: String, dir: int) -> void:
		if id == "op":
			op = posmod(op + dir, OPS.size())
		else:
			status = posmod(status + dir, STATUSES.size())

	func run() -> Array:
		var records := [[1, "DELETED"], [2, "INBOUND"]]
		var found := []
		for r in records:
			if (r[1] == STATUSES[status]) == (OPS[op] == "=="):
				found.append(r[0])
		if found.size() == 1 and found[0] == 2:
			return [["identify(): record 2, HARDFAULT, INBOUND", true]]
		if found.is_empty():
			return [["identify(): no record. The Warden reads silence as Null", false]]
		if found.size() > 1:
			return [["identify(): both records at once. The Warden reads a copy", false]]
		return [["identify(): record 1, HARDFAULT, DELETED. The Warden reads Null", false]]
