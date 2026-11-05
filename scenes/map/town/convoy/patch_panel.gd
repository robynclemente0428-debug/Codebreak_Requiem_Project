extends CanvasLayer
## PATCH: how a DeckSystem the Null knocked offline is repaired. Not with credits: the Null
## corrupted the system's code, and you fix the bug. The panel shows its program in the
## scripting tab's style (same colours, line numbers, numbers you click), with tests to run:
##   power   breaker.prog   a condition the Null flipped: it cuts the power on a normal day
##   cargo   seal.prog      a loop with the wrong count: it drives bolts the door doesn't have
##   comms   relay.prog     its steps in the wrong order: it transmits before it's switched on
## Click a number or operator to change it (right-click / wheel: the other way); move lines
## with the arrows. RUN TESTS runs the program against the system's test cases and prints what
## happened in OUTPUT. When every test passes the patch deploys and the system is back online.
## Nothing is kept between attempts: closing (ESC) leaves the system offline.
## Open with PatchPanel.open(system, player). By path (preload), like DeckSystem.

const FONT_PATH := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const GROUP := "patch_panel"
const ACCENT := Color("#00E5FF")
# The scripting tab's syntax colours (SkillScriptTab)
const COLS := {
	"kw": Color(0.82, 0.55, 1.0),       # always / when / for
	"fn": Color(1.0, 0.80, 0.40),       # calls
	"var": Color(0.45, 0.82, 1.0),
	"num": Color(1.0, 0.62, 0.35),      # editable
	"op": Color(0.80, 0.86, 0.90),
	"cm": Color(0.42, 0.58, 0.55),      # comments
}
const COL_GUTTER := Color(0.35, 0.48, 0.55)
const COL_OK := Color(0.30, 0.95, 0.60)
const COL_BAD := Color(1.0, 0.40, 0.40)
const COL_BG := Color(0.02, 0.04, 0.06, 0.97)
const CODE_SIZE := 18
const WIDTH := 820.0

var system: Node3D                   # the DeckSystem being patched
var puzzle: Puzzle
var _player: Node
var _font: Font
var _code: VBoxContainer
var _out: RichTextLabel
var _run: Button
var _done := false


## Opens the patch for `system` (one at a time).
static func open(system_: Node3D, player: Node) -> void:
	var tree := system_.get_tree()
	if tree.get_first_node_in_group(GROUP) != null:
		return
	var p = load("res://scenes/map/town/convoy/patch_panel.gd").new()
	p.system = system_
	p._player = player
	p.puzzle = Puzzle.make(str(system_.get("system_id")))
	# On the game window, not in the low-resolution 3D view (like the breach HUD)
	tree.root.add_child(p)


func _ready() -> void:
	layer = 21
	add_to_group(GROUP)
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	_build()
	_lock(true)
	_rebuild()
	_print([["Edit the code, then RUN TESTS.", true]], false)


func _exit_tree() -> void:
	_lock(false)


func _lock(on: bool) -> void:
	if _player != null and is_instance_valid(_player) and "input_locked" in _player:
		_player.input_locked = on


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	queue_free()


# ---------- LAYOUT ----------
func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP           # clicks don't reach the world
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
	var hint := _label("click a number or operator: change it   right-click / wheel: the other way   arrows: move a line",
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
	var close_b := _button("CLOSE (ESC)")
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
		_code.add_child(row)
		var num := _tok(str(i + 1), COL_GUTTER)
		num.custom_minimum_size.x = 30
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(num)
		# The move arrows (lines that can be reordered), or a gap the same width
		var mover := HBoxContainer.new()
		mover.custom_minimum_size.x = 52
		mover.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(mover)
		var slot: int = line.get("move", -1)
		if slot >= 0 and not _done:
			for dir in [-1, 1]:
				var b := _arrow("^" if dir < 0 else "v")
				b.pressed.connect(func() -> void:
					puzzle.move(slot, dir)
					_edited())
				mover.add_child(b)
		row.add_child(_tok("    ".repeat(int(line.get("indent", 0))), COL_GUTTER))
		for t in line["tokens"]:
			if t is Dictionary:
				row.add_child(_edit_tok(t))
			else:
				row.add_child(_tok(t[0], COLS.get(t[1], Color.WHITE)))


func _edited() -> void:
	_rebuild()
	_print([["Changed. RUN TESTS to check it.", true]], false)


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
		_out.append_text("\n[color=#%s]ALL TESTS PASS // DEPLOYING PATCH...[/color]" % COL_OK.to_html(false))
		_rebuild()
		await get_tree().create_timer(1.2).timeout
		if system != null and is_instance_valid(system) and system.has_method("repair"):
			system.repair()
		close()


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


# ---------- TOKENS ----------
func _tok(text: String, col: Color) -> Label:
	return _label(text, CODE_SIZE, col, false)


## An editable token: click = next value, right-click / wheel down = previous.
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


func _arrow(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.custom_minimum_size = Vector2(22, 22)
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", COLS["num"])
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	return b


# ---------- THE PUZZLES ----------
## A system's corrupted program. lines(): what to show, each {"tokens": [...], "indent": n,
## "move": slot or -1}; a token is [text, colour key] or {"edit": id, "text": shown} (editable).
## step(id, dir) changes an editable token, move(slot, dir) moves a line, run() runs the tests:
## [[what happened, passed], ...]. Every test passing = fixed.
class Puzzle extends RefCounted:
	var file := ""
	var brief := ""

	func lines() -> Array:
		return []

	func step(_id: String, _dir: int) -> void:
		pass

	func move(_slot: int, _dir: int) -> void:
		pass

	func run() -> Array:
		return []

	static func make(id: String) -> Puzzle:
		match id:
			"cargo":
				return CargoPuzzle.new()
			"comms":
				return CommsPuzzle.new()
		return PowerPuzzle.new()


## POWER: the breaker trips on a normal load. The Null flipped the comparison.
class PowerPuzzle extends Puzzle:
	const OPS := ["<", ">", "<=", ">=", "==", "!="]
	const LIMITS := [0, 40, 80, 120, 160, 200]
	var op := 0                          # "<": flipped (should be ">")
	var limit := 3                       # 120, the row's max safe draw

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


## CARGO: the hold door has 3 bolts; the Null's loop drives 5.
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


## COMMS: the relay's steps are in the wrong order: it transmits before it's on or tuned.
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
