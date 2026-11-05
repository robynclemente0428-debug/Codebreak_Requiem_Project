class_name QuestTracker
extends Control
## Always-visible overlay: active quests and their objectives, plus a toast banner.
## Sits in the top-right corner under the minimap (and moves up when the minimap is hidden).
## Its header has a [-] / [+] button (or the minimize key) that folds it down to one line.
## Only that button takes the mouse; the rest never blocks clicks meant for the game.

@export var font: Font
@export var accent := Color("#00E5FF")
@export var tracker_width: float = 300.0     # matches the minimap
@export var margin_right: float = 32.0       # matches the minimap's margin
@export var margin_top: float = 32.0         # when there's no minimap above it
@export var gap_below_minimap: float = 12.0
@export var minimize_key: Key = KEY_L
@export var max_quests: int = 3
@export_range(0.0, 1.0, 0.01) var bg_opacity: float = 0.55
@export var base_font_size: int = 16

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_DONE := Color(0.35, 1.0, 0.65)
const COL_READY := Color(1.0, 0.82, 0.30)
const COL_HINT := Color(1.0, 0.62, 0.36)      # a boss lock hint under its "Defeat ..." objective

var _font: Font
var _quests: QuestManager
var _panel: PanelContainer
var _box: VBoxContainer
var _count_label: Label
var _min_btn: Button
var _minimized := false
var _minimap: Control
var _toast: Label
var _toast_tween: Tween
var _scan: Scan                   # CRT scanlines and a sweep over the panel, like the minimap's
var _style: StyleBoxFlat          # the panel's, brightened while hovered


func _enter_tree() -> void:
	add_to_group("quest_tracker")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_build_ui()
	_refresh()


# ---------- PUBLIC ----------
func bind(quests: QuestManager) -> void:
	if _quests:
		_quests.quest_started.disconnect(_on_started)
		_quests.quest_updated.disconnect(_on_changed)
		_quests.quest_ready.disconnect(_on_ready)
		_quests.quest_completed.disconnect(_on_completed)
		_quests.item_recovered.disconnect(_on_recovered)
	_quests = quests
	if _quests:
		_quests.quest_started.connect(_on_started)
		_quests.quest_updated.connect(_on_changed)
		_quests.quest_ready.connect(_on_ready)
		_quests.quest_completed.connect(_on_completed)
		_quests.item_recovered.connect(_on_recovered)
	_refresh()


# ---------- SIGNALS ----------
func _on_started(s: QuestState) -> void:
	_refresh()
	_show_toast("NEW QUEST: %s" % s.def.title.to_upper(), accent)


func _on_changed(_s: QuestState) -> void:
	_refresh()


func _on_ready(s: QuestState) -> void:
	_refresh()
	_show_toast("QUEST READY: %s" % s.def.title.to_upper(), COL_READY)


func _on_completed(s: QuestState) -> void:
	_refresh()
	_show_toast("QUEST COMPLETE: %s" % s.def.title.to_upper(), COL_DONE)


# ---------- BUILDING ----------
func _build_ui() -> void:
	_panel = PanelContainer.new()
	# Clicking the tracker opens the quest log (its - / + button still minimizes)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_panel.tooltip_text = "Open the quest log  [ J ]"
	_panel.gui_input.connect(_on_panel_input)
	_panel.mouse_entered.connect(_set_hover.bind(true))
	_panel.mouse_exited.connect(_set_hover.bind(false))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -(margin_right + tracker_width)
	_panel.offset_right = -margin_right
	_panel.offset_top = margin_top
	_panel.offset_bottom = margin_top               # height follows the content
	_panel.grow_vertical = Control.GROW_DIRECTION_END    # grows downward
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.06, 0.09, bg_opacity)
	style.border_color = Color(accent, 0.6)
	style.border_width_left = 2
	style.content_margin_left = 14
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)
	_style = style
	add_child(_panel)
	_scan = Scan.new()
	add_child(_scan)                              # over the panel; _process keeps it on it

	var outer := VBoxContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	# Header: // QUESTS //  2  [-]
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 8)
	outer.add_child(head)
	var title := _label("// QUESTS //", base_font_size - 1, accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	_count_label = _label("", base_font_size - 2, COL_DIM)
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_count_label)
	_min_btn = _make_min_button()
	head.add_child(_min_btn)

	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 3)
	outer.add_child(_box)

	_toast = Label.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.offset_top = TOAST_TOP
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", base_font_size + 10)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	if _font:
		_toast.add_theme_font_override("font", _font)
	_toast.modulate.a = 0.0
	add_child(_toast)


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
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(accent, 0.20 if state != "normal" else 0.06)
		sb.border_color = Color(accent, 0.8 if state != "normal" else 0.45)
		sb.set_border_width_all(1)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(toggle_minimized)
	return b


# ---------- OPENING THE QUEST LOG ----------
func _on_panel_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		var log_panel := get_tree().get_first_node_in_group("quest_log") as QuestLogPanel
		if log_panel != null:
			log_panel.open()
		accept_event()


func _set_hover(on: bool) -> void:
	if _style == null:
		return
	_style.border_color = Color(accent, 1.0 if on else 0.6)
	_style.bg_color = Color(0.02, 0.06, 0.09, minf(bg_opacity + (0.15 if on else 0.0), 1.0))


## The tracker panel, for TutorialHints to outline.
func tutorial_target() -> Array[Control]:
	var out: Array[Control] = []
	if _panel != null and _panel.is_visible_in_tree():
		out.append(_panel)
	return out


# ---------- MINIMIZE ----------
func set_minimized(on: bool) -> void:
	_minimized = on
	_apply_minimized()


func toggle_minimized() -> void:
	set_minimized(not _minimized)


func is_minimized() -> bool:
	return _minimized


func _apply_minimized() -> void:
	if _box == null:
		return
	_box.visible = not _minimized
	_min_btn.text = "+" if _minimized else "-"
	_min_btn.tooltip_text = "%s the quest tracker  [ %s ]" % [
		"Expand" if _minimized else "Minimize", OS.get_keycode_string(minimize_key)]
	_panel.offset_left = -(margin_right + tracker_width)
	_panel.offset_right = -margin_right
	_panel.offset_bottom = _panel.offset_top             # height shrinks to the content


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == minimize_key \
			and _panel != null and _panel.visible:
		toggle_minimized()
		get_viewport().set_input_as_handled()


# ---------- MESSAGES ----------
const TOAST_TOP := 215.0          # under the tutorial banner (TutorialHints.BANNER_Y + its height)
const TOAST_GAP := 14.0           # below the AREA CLEARED band while it's up


## The message line sits under the tutorial banner, or under the AREA CLEARED band while that is
## on screen (it would cover the band's text otherwise: a ward beacon coming online clears the
## area in the same moment).
func _place_toast() -> void:
	if _toast == null:
		return
	var band := AreaClearedBanner.bottom_y(get_tree())
	var top := TOAST_TOP if band < 0.0 else maxf(TOAST_TOP, band - global_position.y + TOAST_GAP)
	if not is_equal_approx(_toast.offset_top, top):
		_toast.offset_top = top


# ---------- FOLLOWING THE MINIMAP ----------
## Stays right under the minimap, and glides up into its place when the minimap is hidden.
## Fades with the minimap's opacity ([ and ], see Minimap.opacity), so the two read as one.
func _process(_delta: float) -> void:
	_place_toast()
	if _scan != null:
		_scan.visible = _panel != null and _panel.visible
	if _panel == null or not _panel.visible:
		return
	if _minimap == null or not is_instance_valid(_minimap):
		_minimap = get_tree().get_first_node_in_group("minimap") as Control
	var top := margin_top
	if _minimap != null and _minimap.has_method("docked_amount"):
		var below: float = _minimap.docked_bottom() + gap_below_minimap
		top = lerpf(margin_top, below, _minimap.docked_amount())
	if not is_equal_approx(_panel.offset_top, top):
		_panel.offset_top = top
		_panel.offset_bottom = top
	var alpha: float = _minimap.get("opacity") if _minimap != null and _minimap.get("opacity") != null else 1.0
	_panel.modulate.a = alpha
	_scan.modulate.a = alpha
	_scan.scanlines = _minimap == null or _minimap.get("scanlines") != false
	_scan.position = _panel.position
	_scan.size = _panel.size


## CRT scanlines and a slow sweep, like the minimap's. The sweep stays inside the panel.
class Scan extends Control:
	var t := 0.0
	var scanlines := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if scanlines and is_visible_in_tree():
			t += delta
			queue_redraw()

	func _draw() -> void:
		if not scanlines:
			return
		var inset := 4.0                          # just inside the 2 px border on the left
		var y := 2.0
		while y < size.y - 2.0:
			draw_line(Vector2(inset, y), Vector2(size.x - 2.0, y), Color(0, 0, 0, 0.13), 1.0)
			y += 3.0
		var top := 2.0 + 3.0                      # half the sweep's 6 px thickness
		var band := maxf(size.y - 4.0 - 6.0, 1.0)
		var sweep_y := top + fposmod(t * 70.0, band)
		draw_line(Vector2(inset, sweep_y), Vector2(size.x - 2.0, sweep_y), Color(1, 1, 1, 0.05), 6.0)


# ---------- REFRESH ----------
func _refresh() -> void:
	if _panel == null:
		return
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()

	if _quests == null or _quests.active.is_empty():
		_panel.visible = false
		return
	_panel.visible = true
	_count_label.text = str(_quests.active.size())
	_apply_minimized()

	# ready quests first, then in the order they were started
	var states: Array[QuestState] = []
	for s: QuestState in _quests.active.values():
		if s.status == QuestState.Status.READY_TO_TURN_IN:
			states.push_front(s)
		else:
			states.append(s)

	var shown := mini(states.size(), max_quests)
	for n in shown:
		if n > 0:
			_box.add_child(_gap(6))
		_add_quest(states[n])
	if states.size() > shown:
		_box.add_child(_label("+%d MORE  [ J ]" % (states.size() - shown), base_font_size - 3, COL_DIM))


func _add_quest(s: QuestState) -> void:
	var ready := s.status == QuestState.Status.READY_TO_TURN_IN
	var title_col := NpcInfoPanel.COL_EXAM if Ranks.is_exam(s.def.id) else accent   # exams stand out
	_box.add_child(_wrapped(s.def.title.to_upper(), base_font_size + 2, COL_READY if ready else title_col))
	if ready:
		_box.add_child(_wrapped("RETURN TO THE QUEST GIVER", base_font_size - 2, COL_READY))
		return
	for i in s.def.objectives.size():
		var o: Objective = s.def.objectives[i]
		var have := s.progress[i]
		var done := have >= o.required
		var text := "???" if (o.hidden and not done) else o.description
		if o.required > 1:
			text += "  %d/%d" % [have, o.required]
		var mark := "[X] " if done else "[ ] "
		_box.add_child(_wrapped(mark + text, base_font_size - 2, COL_DONE if done else COL_TEXT))
		# A boss with a lock: how to hurt it, right under "Defeat ..." (from the lock itself)
		if not done and o.kind == "kill" and not o.hidden:
			var lock: Dictionary = preload("res://scenes/ui/player_ui/lock_banner/lock_banner.gd").hint_for_enemy(o.target)
			if not lock.is_empty() and lock["hint"] != "":
				_box.add_child(_wrapped("    %s: %s" % [lock["name"], lock["hint"]], base_font_size - 3, COL_HINT))


func _on_recovered(id: String) -> void:
	_show_toast("RECOVERED: %s" % QuestItems.name_of(id), COL_READY)


# ---------- TOAST ----------
## For other systems (QuestItems.toast): a sealed portal, a beacon coming back online.
func show_toast(text: String, colour: Color) -> void:
	_show_toast(text, colour)


func _show_toast(text: String, colour: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", colour)
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


# ---------- HELPERS ----------
func _label(text: String, size_px: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", colour)
	if _font:
		l.add_theme_font_override("font", _font)
	return l


func _wrapped(text: String, size_px: int, colour: Color) -> Label:
	var l := _label(text, size_px, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
