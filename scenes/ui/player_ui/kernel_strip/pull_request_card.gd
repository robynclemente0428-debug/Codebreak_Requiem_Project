class_name PullRequestCard
extends CanvasLayer
## The Null's PULL REQUEST on an Act V floor (KernelScript): its line, and the three answers,
## which are the three endings in small. KernelDirector opens it the first time you arrive.
##   // PULL REQUEST 1/4 //  THE STACK TRACE
##   The Null wants to run this on the Core:
##       when enemy_spotted: target.armour += 40%
##   [ MERGE ]                       its line runs. It gives you: registry.add(target)
##   [ OVERWRITE: target.defragment() ]   its line never runs: yours does
##   [ OVERWRITE: target.max_hp -= 15% ]
##   [ TERMINATE ]                   neither runs. The process fights back: a champion spawns
## It can't be closed without answering. Single player: the game waits (paused) while it's up.
## Co-op: the game runs on, so it opens where you arrive, before the floor's enemies reach you.
## Styled like the support gem choice (RewardChoice).

signal answered(how: String, pick: String)    # once, then the card frees itself

const FONT_PATH := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_BG := Color(0.02, 0.06, 0.08, 0.96)
const CARD_WIDTH := 760.0

var null_id := ""
var _font: Font
var _paused_it := false


## Opens the card for `id` on the screen (`index` of `count` requests, on `floor_name`).
static func open(tree: SceneTree, id: String, floor_name: String, index: int, count: int, lines: Array) -> PullRequestCard:
	var card := PullRequestCard.new()
	card.null_id = id
	tree.root.add_child(card)
	card._build(floor_name, index, count, lines)
	return card


func _ready() -> void:
	layer = 30                                   # over the HUD (20), like RewardChoice
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	if not Coop.in_game and not get_tree().paused:
		get_tree().paused = true
		_paused_it = true
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	if _paused_it:
		get_tree().paused = false


func _answer(how: String, pick := "") -> void:
	answered.emit(how, pick)
	queue_free()


# ---------- UI ----------
func _build(floor_name: String, index: int, count: int, lines: Array) -> void:
	var d: Dictionary = KernelScript.NULL_LINES[null_id]
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP          # nothing behind it can be clicked
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	card.add_theme_stylebox_override("panel", _box(COL_BG, KernelScript.COL_NULL, 2, 22))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	col.add_child(_label("// PULL REQUEST %d/%d //  %s" % [index, count, floor_name.to_upper()], 24, KernelScript.COL_NULL))
	col.add_child(_wrap(_label("The Null wants to run this on the Core, in every zone from here down. "
		+ "Your answer is a vote: the Last Log reads them all back before the end.", 15, COL_DIM)))
	var code := _label("    " + KernelScript.code_of(null_id), 18, KernelScript.COL_NULL)
	col.add_child(code)
	col.add_child(_wrap(_label("    " + str(d["tip"]), 14, COL_TEXT)))
	col.add_child(HSeparator.new())

	var gift := str(d["gift"])
	col.add_child(_choice("MERGE", KernelScript.COL_NULL,
		"Its line runs. The Null gives you one too: %s%s" % [KernelScript.code_of(gift),
			"  (already yours)" if gift in lines else ""],
		_answer.bind("merge", "")))
	for pick in KernelScript.offers(lines, null_id):
		col.add_child(_choice("OVERWRITE", KernelScript.COL_ROOT,
			"Its line never runs. Yours does: %s%s" % [KernelScript.code_of(pick),
				"  (already yours)" if pick in lines else ""],
			_answer.bind("overwrite", pick)))
	col.add_child(_choice("TERMINATE", KernelScript.COL_TERMINATE,
		"Neither runs. The process fights its shutdown: a champion comes for you here.",
		_answer.bind("terminate", "")))


## One answer: its button, and what it does beside it.
func _choice(word: String, col: Color, what: String, on_press: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var b := Button.new()
	b.text = word
	b.custom_minimum_size = Vector2(170, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(Color(col, 0.10), col, 2, 6))
	b.add_theme_stylebox_override("hover", _box(Color(col, 0.24), col, 2, 6))
	b.add_theme_stylebox_override("pressed", _box(Color(col, 0.32), col, 2, 6))
	b.pressed.connect(on_press)
	row.add_child(b)
	var l := _wrap(_label(what, 15, COL_TEXT))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return row


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1.0
	return l


func _box(bg: Color, border: Color, width: int, margin: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_content_margin_all(margin)
	return sb
