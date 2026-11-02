class_name ThreatPanel
extends Control
## Top-left HUD card: what the current dungeon's fights favour (DungeonThreats), so players
## know which script set to run. Hidden in towns and in dungeons without threats.
##   // THREATS //  RELAY TRENCH            [-]
##   SWARM      Twice the enemies, half the health each. Area and splash scripts shine.
##   REFLECTOR  Every hit you land zaps you back. Fewer, bigger hits.
##   [X] SWAPS SCRIPT SET  (NOW: A)
## The hints need rank OPERATOR (Ranks.PERKS); below it only the threats' names show.
## Opens with the hints on arrival, then folds to the tags alone after `expanded_time`.
## The [-] / [+] button keeps it the way the player chose until the next dungeon.
## AreaManager adds it (StimLayer), outside the low-res game viewport like the rest of the HUD.

@export var font: Font
@export var accent := Color("#00E5FF")
@export var panel_width: float = 330.0
@export var margin := Vector2(32.0, 32.0)
@export var expanded_time: float = 10.0
@export var base_font_size: int = 15

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_TEXT := Color(0.85, 0.96, 1.0)
const POLL := 0.5

var _font: Font
var _panel: PanelContainer
var _title: Label
var _tags: HBoxContainer          # collapsed: the tags in one row
var _rows: VBoxContainer          # expanded: one row per threat with its hint
var _set_line: Label
var _min_btn: Button
var _path := "?"
var _threats := PackedStringArray()
var _expanded := true
var _poll := 0.0
var _hints := false              # the player's rank shows how to counter each threat (Ranks.PERKS)
var _fold_at := -1.0              # seconds left until it folds itself (-1 = never)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_build()
	visible = false


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL
		var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
		var key := _path
		var inst: DungeonInstance = null
		if am != null and not am.is_busy() and am.current_area != null:
			inst = am.current_area.get("instance") as DungeonInstance
			key = "%s#%d" % [am.current_scene_path(), inst.id if inst != null else 0]
		if key != _path:
			_path = key
			_enter_area(am.current_scene_path(), inst)
		elif visible:
			_update_set_line()
	if _fold_at > 0.0:
		_fold_at -= delta
		if _fold_at <= 0.0:
			_set_expanded(false)


## A new area (or a new instance of one): show its threats (expanded for a while), or hide.
## A dungeon's threats are its instance's roll; towns have no instance and no threats.
func _enter_area(path: String, inst: DungeonInstance) -> void:
	_threats = inst.threats if inst != null else PackedStringArray()
	visible = not _threats.is_empty()
	if not visible:
		return
	var w := Waypoints.for_scene(path)
	_title.text = "// THREATS //  %s" % (w.display_name.to_upper() if w != null else "")
	_fill()
	_set_expanded(true)
	_fold_at = expanded_time


func _fill() -> void:
	for c in _tags.get_children() + _rows.get_children():
		c.queue_free()
	_hints = Ranks.perk(Ranks.of_player(get_tree()), "hints")
	var hints := _hints
	for i in _threats.size():
		var id := _threats[i]
		if i > 0:
			_tags.add_child(_label("·", base_font_size - 2, COL_DIM))
		_tags.add_child(_label(DungeonThreats.label(id), base_font_size - 1, DungeonThreats.color(id)))
		var row := VBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 0)
		row.add_child(_label(DungeonThreats.label(id), base_font_size - 1, DungeonThreats.color(id)))
		if hints:                         # below the rank: just the threat's name
			var hint := _label(DungeonThreats.hint(id), base_font_size - 2, COL_TEXT)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.custom_minimum_size.x = panel_width - 30.0
			row.add_child(hint)
		_rows.add_child(row)
	_update_set_line()


func _update_set_line() -> void:
	var player := get_tree().get_first_node_in_group("players")
	var skills: SkillComponent = player.get("skills") if player != null else null
	if _hints != Ranks.perk(Ranks.of_player(get_tree()), "hints"):
		_fill()                           # ranked up here: the hints arrive
		return
	if skills == null or not skills.uses_scripts():
		_set_line.text = "Write scripts for these in the skills menu [K]."
	elif skills.sets_unlocked() <= 1:
		_set_line.text = "Tune your script for these in the skills menu [K]."
	else:
		_set_line.text = "[%s] SWAPS SCRIPT SET  (NOW: %s)" % [GemText.key_label(&"script_set"),
				skills.set_label(skills.script_set)]


func _set_expanded(on: bool) -> void:
	_expanded = on
	_rows.visible = on
	_set_line.visible = on
	_tags.visible = not on
	_min_btn.text = "-" if on else "+"
	_min_btn.tooltip_text = "Hide the hints" if on else "Show what these threats mean"
	_panel.reset_size()


func _toggle() -> void:
	_fold_at = -1.0                       # the player chose: leave it alone
	_set_expanded(not _expanded)


# ---------- BUILDING ----------
func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = margin
	_panel.custom_minimum_size.x = panel_width
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.06, 0.09, 0.85)
	style.border_color = Color(1.0, 0.45, 0.35, 0.7)    # warm: a warning, not a quest
	style.border_width_left = 2
	style.content_margin_left = 14
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", 5)
	_panel.add_child(outer)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 8)
	outer.add_child(head)
	_title = _label("", base_font_size - 1, Color(1.0, 0.55, 0.45))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_title)
	_min_btn = _make_min_button()
	head.add_child(_min_btn)

	_tags = HBoxContainer.new()
	_tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tags.add_theme_constant_override("separation", 8)
	outer.add_child(_tags)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 6)
	outer.add_child(_rows)
	_set_line = _label("", base_font_size - 3, COL_DIM)
	outer.add_child(_set_line)


func _make_min_button() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP          # the one part that takes clicks
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(26, 22)
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", base_font_size - 1)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(accent, 0.20 if state != "normal" else 0.06)
		sb.border_color = Color(accent, 0.8 if state != "normal" else 0.45)
		sb.set_border_width_all(1)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(_toggle)
	return b


func _label(text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	if _font:
		l.add_theme_font_override("font", _font)
	return l
