class_name ScriptTooltip
extends PanelContainer
## The SCRIPTING tab's hints. Every control in the tab keeps writing plain `tooltip_text`; this
## takes it over while the mouse is on the control (so Godot's plain tooltip never shows) and
## draws it here instead, formatted (format()):
##   the first line           a bold title
##   "ERROR: / FIX: / COST: / TIP: / NOTE: / LOOP: / HIT: / HOW:" a coloured tag, then its text
##   lines indented 4 spaces  code, in the editor's syntax colours on a dark band
##   "Drag / Drop / Click / Right-click / Double-click / click: ..."  mouse controls, dimmed, last
##   inline                   numbers (x0.60, 20%, 3.5 points), calls (apply(), registry.add(target)),
##                            buff / drawback in their gutter colours
## At most MAX_WIDTH wide; long lines wrap, so it only grows taller.

const DELAY := 0.35                        # seconds on a control before its hint shows
const MAX_WIDTH := 400.0                   # px, at the base font size
const OFFSET := Vector2(18, 20)            # from the mouse pointer
const TIP_META := &"_script_tip"           # the text taken from a control's tooltip_text
const CUT_META := &"_cut_tip"              # a Label that shows its whole text while it's cut with "..."

# The editor's syntax colours (SkillScriptTab's, repeated: this file can't preload that one)
const COL_KEYWORD := Color(0.82, 0.55, 1.0)
const COL_FN := Color(1.0, 0.80, 0.40)
const COL_VAR := Color(0.45, 0.82, 1.0)
const COL_NUM := Color(1.0, 0.62, 0.35)
const COL_OP := Color(0.80, 0.86, 0.90)
const COL_COMMENT := Color(0.42, 0.58, 0.55)
const COL_BUFF := Color(0.30, 0.95, 0.60)
const COL_DRAW := Color(1.0, 0.45, 0.45)

## tag -> colour (the chip before the line's text)
const TAGS := {
	"ERROR": Color(1.0, 0.30, 0.37),
	"NOTE": Color(1.0, 0.85, 0.35),
	"FIX": Color(0.30, 0.95, 0.60),
	"COST": Color(1.0, 0.62, 0.35),
	"TIP": Color(0.30, 0.95, 0.60),
	"LOOP": Color(0.82, 0.55, 1.0),
	"HIT": Color(0.45, 0.82, 1.0),
	"LIMIT": Color(1.0, 0.85, 0.35),
	"HOW": Color(0.55, 0.70, 0.78),
}
const HOW_STARTS := ["drag ", "drop ", "click", "right-click", "double-click", "hover a tab"]
const KEYWORDS := ["when", "if", "and", "not", "in", "while", "for", "break", "always", "pass",
	"except", "def", "call", "is", "range"]

var tab: Control
var _label: RichTextLabel
var _for: Control                          # the control whose hint is showing (or waiting)
var _wait := 0.0
var _font: Font
var _size := 13


func setup(p_tab: Control, font: Font, size: int, accent: Color) -> void:
	tab = p_tab
	_font = font
	_size = size
	top_level = true
	z_index = 100
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.09, 0.97)
	sb.border_color = Color(accent, 0.8)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_content_margin_all(10)
	sb.content_margin_left = 12
	add_theme_stylebox_override("panel", sb)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("default_color", SkillPanel.COL_TEXT)
	_label.add_theme_constant_override("line_separation", 3)
	if font != null:
		for f in ["normal_font", "bold_font", "italics_font", "mono_font"]:
			_label.add_theme_font_override(f, font)
	for f in ["normal_font_size", "bold_font_size", "italics_font_size", "mono_font_size"]:
		_label.add_theme_font_size_override(f, size)
	add_child(_label)


func _process(delta: float) -> void:
	if tab == null or not tab.is_visible_in_tree():
		_hide()
		return
	var c := _hovered()
	if c != _for:
		_for = c
		_wait = 0.0
		_hide()
	if _for == null:
		return
	if get_viewport().gui_is_dragging():
		_hide()
		_wait = 0.0
		return
	_wait += delta
	if _wait >= DELAY:
		var text: String = _for.get_meta(TIP_META, "")
		if text == "":
			_hide()
			return
		if not visible or _label.get_meta(&"src", "") != text:
			_show(text)
		_place()


## The control under the mouse that has a hint (itself, or the first parent it passes the mouse
## to), inside the tab. Its tooltip_text moves to TIP_META, so Godot's own tooltip stays away.
func _hovered() -> Control:
	var c := get_viewport().gui_get_hovered_control()
	while c != null and (c == tab or tab.is_ancestor_of(c)):
		if c.tooltip_text != "":
			c.set_meta(TIP_META, c.tooltip_text)
			c.tooltip_text = ""
		if c.has_meta(CUT_META):
			c.set_meta(TIP_META, _cut_text(c as Label))   # "" while it fits: the line's own hint shows
		if c.get_meta(TIP_META, "") != "":
			return c
		if c.mouse_filter != Control.MOUSE_FILTER_PASS:
			return null
		c = c.get_parent() as Control
	return null


## A cut label's whole text (as a comment: "# ..."), or "" when it isn't cut.
static func _cut_text(l: Label) -> String:
	if l == null or l.text.strip_edges() == "":
		return ""
	var font := l.get_theme_font(&"font")
	var fs := l.get_theme_font_size(&"font_size")
	if font == null or font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= l.size.x + 0.5:
		return ""
	return l.text.strip_edges().trim_prefix("#").strip_edges()


func _show(text: String) -> void:
	_label.set_meta(&"src", text)
	var w := _width_for(text)
	_label.custom_minimum_size.x = w
	_label.size.x = w
	_label.text = format(text)
	visible = true
	reset_size()


func _hide() -> void:
	visible = false


func _place() -> void:
	reset_size()
	var screen := get_viewport_rect().size
	var m := get_global_mouse_position()
	var pos := m + OFFSET
	if pos.x + size.x > screen.x - 8.0:
		pos.x = m.x - OFFSET.x - size.x
	if pos.y + size.y > screen.y - 8.0:
		pos.y = m.y - OFFSET.y - size.y
	global_position = Vector2(maxf(pos.x, 8.0), maxf(pos.y, 8.0)).round()


## As wide as its longest line, up to MAX_WIDTH (scaled with the font).
func _width_for(text: String) -> float:
	var cap := MAX_WIDTH * _size / 13.0
	if _font == null:
		return cap
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, _font.get_string_size(line + "    ", HORIZONTAL_ALIGNMENT_LEFT, -1, _size).x)
	return clampf(widest, 120.0, cap)


# ---------- FORMATTING ----------
## Plain hint text -> BBCode (see the class notes for the rules).
static func format(text: String) -> String:
	var lines := text.strip_edges().split("\n")
	var body: PackedStringArray = []
	var how: PackedStringArray = []
	var title_done := false
	for raw in lines:
		var line: String = raw
		if line.strip_edges() == "":
			if not body.is_empty():
				body.append("")
			title_done = false                   # a new section (an error above the line's own hint)
			continue
		if line.begins_with("    "):
			body.append(_code(line))
			title_done = true
			continue
		var tag := _tag_of(line)
		if tag != "":
			var rest := line.substr(line.find(":") + 1).strip_edges()
			if tag == "HOW":
				how.append(_inline(rest))
			else:
				body.append(_chip(tag) + " " + _inline(rest))
			title_done = true
			continue
		if _is_how(line):
			how.append(_inline(line.strip_edges()))
			continue
		if not title_done:
			body.append("[b][color=#ffffff]%s[/color][/b]" % _inline(line))
			title_done = true
			continue
		body.append(_inline(line))
	if not how.is_empty():
		body.append(_chip("HOW") + " " + _c(" · ".join(how), TAGS["HOW"]))
	return "\n".join(body)


static func _tag_of(line: String) -> String:
	var at := line.find(":")
	if at <= 0 or at > 6:
		return ""
	var t := line.substr(0, at).strip_edges().to_upper()
	return t if TAGS.has(t) and line.substr(0, at) == line.substr(0, at).strip_edges() else ""


static func _is_how(line: String) -> bool:
	var l := line.strip_edges().to_lower()
	for s in HOW_STARTS:
		if l.begins_with(s):
			return true
	return false


static func _chip(tag: String) -> String:
	var col: Color = TAGS[tag]
	return "[bgcolor=#%s][color=#%s] %s [/color][/bgcolor]" % [Color(col, 0.22).to_html(true), col.to_html(false), tag]


static func _c(text: String, col: Color) -> String:
	return "[color=#%s]%s[/color]" % [col.to_html(false), text]


static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


static var _inline_re: RegEx
static var _code_re: RegEx


## Numbers, calls and buff / drawback words picked out in a line of prose.
static func _inline(text: String) -> String:
	if _inline_re == null:
		_inline_re = RegEx.new()
		_inline_re.compile("(?<call>[a-z_][a-z_0-9.]*\\([^()\\n]{0,24}\\))|(?<num>(?<![A-Za-z_])x\\d+(?:\\.\\d+)?|[+-]?\\d+(?:\\.\\d+)?(?:%| ?m\\b| points?\\b| blocks?\\b| repeats?\\b| s\\b)?)|(?<buff>\\b[Bb]uffs?\\b)|(?<draw>\\b[Dd]rawbacks?\\b)")
	var out := ""
	var at := 0
	for m in _inline_re.search_all(text):
		out += _esc(text.substr(at, m.get_start() - at))
		var s := _esc(m.get_string())
		if m.get_string("call") != "":
			out += _c(s, COL_FN)
		elif m.get_string("num") != "":
			out += _c(s, COL_NUM)
		elif m.get_string("buff") != "":
			out += _c(s, COL_BUFF)
		else:
			out += _c(s, COL_DRAW)
		at = m.get_end()
	return out + _esc(text.substr(at))


## A code example line, in the editor's colours, on a dark band.
static func _code(line: String) -> String:
	if _code_re == null:
		_code_re = RegEx.new()
		_code_re.compile("(?<cm>#.*$)|(?<num>\\d+(?:\\.\\d+)?(?:%|m)?)|(?<word>[A-Za-z_][A-Za-z_0-9.]*)|(?<op>[+\\-*/=<>!:(),\\[\\]]+)")
	var body := line.substr(4)
	var out := ""
	var at := 0
	for m in _code_re.search_all(body):
		out += _esc(body.substr(at, m.get_start() - at))
		var s := m.get_string()
		var col: Color
		if m.get_string("cm") != "":
			col = COL_COMMENT
		elif m.get_string("num") != "":
			col = COL_NUM
		elif m.get_string("word") != "":
			var nxt := body.substr(m.get_end(), 1)
			col = COL_KEYWORD if s in KEYWORDS else (COL_FN if nxt == "(" else COL_VAR)
		else:
			col = COL_OP
		out += _c(_esc(s), col)
		at = m.get_end()
	out += _esc(body.substr(at))
	return "[bgcolor=#00000099]  %s  [/bgcolor]" % out
