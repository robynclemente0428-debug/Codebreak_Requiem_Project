class_name KernelStrip
extends PanelContainer
## kernel.gd's card in an Act V zone (KernelDirector builds it and feeds it show_state()). It sits at
## the top centre in the Announcer's strip, like the tutorial banner and the dock defense panel,
## so it never lands on the HUD's corner cards or the FPS counter. Styled like the THREATS and QUESTS cards.
##   // KERNEL.GD //                       LEANS MERGE
##   [MERGE][OVERWRITE][  ][  ]    one cell per floor's pull request: your answer, or not yet
##   2 ROOT LINES                     1 NULL LINE RUNNING
##   SCHEDULED  when enemy_killed: registry.clear()        38s      (the Scheduler only)

const FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
## First in the strip, above the tutorial banner (0) and the dock panel (10): it stays up the
## whole zone, so it keeps the top spot and the passing hints stack under it.
const STRIP_ORDER := -10                 # (Announcer sorts by it: lower sits higher)
const WIDTH := 440.0
const FONT_SIZE := 15
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_TEXT := Color(0.85, 0.96, 1.0)

var _font: Font
var _lean: Label
var _cells: Cells
var _root_info: Label
var _null_info: Label
var _party: HFlowContainer               # co-op: one small row per partner's answers
var _sched_row: HBoxContainer
var _sched_code: Label
var _sched_time: Label
var _shown := ""                         # what show() last put up, so unchanged frames cost nothing


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FONT):
		_font = load(FONT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.06, 0.09, 0.85)
	style.border_color = Color(KernelScript.COL_ROOT, 0.75)
	style.border_width_left = 2
	style.content_margin_left = 14
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)
	custom_minimum_size.x = WIDTH
	anchor_left = 0.5
	anchor_right = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = Announcer.STRIP_TOP
	_build()
	Announcer.add_to_strip(self, STRIP_ORDER)


## answers: your answer to each floor's request, in order ("merge", "overwrite", "terminate", or
## "" not yet); lean: the ending they lean toward; lines: your root lines; running: the Null's
## lines running; scheduled: the Scheduler's line now ("" = none), for `left` s.
## party (co-op): the other players here, [[name, colour, answers], ...] (Coop.party_answers):
## one small row each, "NAME  M O T -".
func show_state(answers: Array, lean: String, lines: int, running: int, scheduled := "", left := 0.0,
		party: Array = []) -> void:
	var key := "%s|%s|%d|%d|%s|%d|%s" % [",".join(answers), lean, lines, running, scheduled, ceili(left), str(party)]
	if key == _shown:
		return
	_shown = key
	for c in _party.get_children():
		c.queue_free()
	_party.visible = not party.is_empty()
	for row in party:
		var letters: Array = (row[2] as Array).map(func(a: String) -> String: return a.substr(0, 1).to_upper() if a != "" else "-")
		_party.add_child(_label("%s  %s" % [str(row[0]).to_upper(), " ".join(letters)], FONT_SIZE - 4, row[1]))
	var any := answers.any(func(a: String) -> bool: return a != "")
	_lean.text = "LEANS %s" % lean.to_upper() if any else "NO ANSWERS YET"
	_lean.add_theme_color_override("font_color", Cells.colour_of(lean) if any else COL_DIM)
	_cells.answers = answers
	_cells.queue_redraw()
	_root_info.text = "%d ROOT LINE%s" % [lines, "" if lines == 1 else "S"]
	_null_info.visible = running > 0
	_null_info.text = "%d NULL LINE%s RUNNING" % [running, "" if running == 1 else "S"]
	_sched_row.visible = scheduled != ""
	_sched_code.text = scheduled
	_sched_time.text = "%ds" % ceili(left)
	reset_size()


# ---------- BUILDING ----------
func _build() -> void:
	var outer := VBoxContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", 5)
	add_child(outer)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(head)
	var title := _label("// %s //" % KernelScript.FILE_NAME.to_upper(), FONT_SIZE - 1, KernelScript.COL_ROOT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_lean = _label("", FONT_SIZE - 1, KernelScript.COL_ROOT)
	head.add_child(_lean)

	_cells = Cells.new()
	_cells.custom_minimum_size.y = 16
	outer.add_child(_cells)

	var info := HBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(info)
	_root_info = _label("", FONT_SIZE - 3, COL_DIM)
	_root_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_root_info)
	_null_info = _label("", FONT_SIZE - 3, KernelScript.COL_NULL)
	info.add_child(_null_info)

	_party = HFlowContainer.new()                  # co-op: each partner's answers
	_party.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party.add_theme_constant_override("h_separation", 14)
	_party.visible = false
	outer.add_child(_party)

	_sched_row = HBoxContainer.new()
	_sched_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sched_row.add_theme_constant_override("separation", 8)
	_sched_row.visible = false
	outer.add_child(_sched_row)
	_sched_row.add_child(_label("SCHEDULED", FONT_SIZE - 3, COL_DIM))
	_sched_code = _label("", FONT_SIZE - 3, KernelScript.COL_NULL)
	_sched_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sched_row.add_child(_sched_code)
	_sched_time = _label("", FONT_SIZE - 3, COL_TEXT)
	_sched_row.add_child(_sched_time)


func _label(text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	if _font:
		l.add_theme_font_override("font", _font)
	return l


## One cell per floor's pull request, in a row, filled with your answer's colour and its first
## letter (M, O, T); an empty outline for one not answered yet.
class Cells extends Control:                 # (also gives KernelStrip its answer colours)
	var answers: Array = []
	const GAP := 4.0

	static func colour_of(answer: String) -> Color:
		match answer:
			"merge":
				return KernelScript.COL_NULL
			"overwrite":
				return KernelScript.COL_ROOT
			"terminate":
				return KernelScript.COL_TERMINATE
		return Color(0.55, 0.78, 0.85, 0.5)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := answers.size()
		if n <= 0:
			return
		var w := (size.x - GAP * (n - 1)) / n
		var font := get_theme_default_font()
		for i in n:
			var r := Rect2(i * (w + GAP), 0.0, w, size.y)
			var a: String = answers[i]
			var col := colour_of(a)
			if a == "":
				draw_rect(r, col, false, 1.0)
				continue
			draw_rect(r, Color(col, 0.85))
			if font != null:
				var letter := a.substr(0, 1).to_upper()
				var at := Vector2(r.position.x + (w - 8.0) * 0.5, r.position.y + size.y - 3.0)
				draw_string(font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.02, 0.06, 0.09))
