class_name QuestTracker
extends Control
## Always-visible overlay: active quests and their objectives, plus the message feed (short
## lines stacked at the top centre, placed by Announcer).
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
var _feed: VBoxContainer          # the messages on screen, oldest at the top
var _scan: Scan                   # CRT scanlines and a sweep over the panel, like the minimap's
var _style: StyleBoxFlat          # the panel's, brightened while hovered


func _enter_tree() -> void:
	add_to_group("quest_tracker")


func _ready() -> void:
	process_priority = Announcer.FEED_AFTER        # places itself after Announcer and the headlines
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

	_feed = VBoxContainer.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.anchor_left = 0.0
	_feed.anchor_right = 1.0
	_feed.offset_top = Announcer.FEED_MIN
	_feed.add_theme_constant_override("separation", FEED_SEPARATION)
	_feed.modulate.a = Announcer.OPACITY          # every line under it, a little see-through
	add_child(_feed)


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
## At most this many lines at once: a new one past it pushes the oldest out.
const FEED_MAX := 3
const FEED_SEPARATION := 6                # px between lines (also in _fit_feed's sums)
## Seconds a line holds before fading, plus this much for each line after its first.
const FEED_HOLD := 2.4
const FEED_HOLD_PER_LINE := 0.8
const FEED_FADE := 0.6
## A line wider than this wraps, in a column centred on the screen. It leaves room for the HUD's
## corner cards (the threats on the left, the minimap and this tracker on the right), so it never
## runs under them or off the screen's edges.
const FEED_WRAP_MAX := 760.0
const FEED_WRAP_MIN := 420.0
const FEED_CORNER_ROOM := 400.0           # px kept clear on each side of the column


## The feed sits where Announcer says (under the tutorial banner, or under a headline such as
## AREA CLEARED while one is up). It drops out of the way at once and glides back up.
func _place_feed(delta: float) -> void:
	if _feed == null:
		return
	var want := Announcer.feed_top() - global_position.y
	var top := want
	if _feed.get_child_count() > 0 and want < _feed.offset_top:
		top = lerpf(_feed.offset_top, want, minf(1.0, delta * 12.0))
	if not is_equal_approx(_feed.offset_top, top):
		_feed.offset_top = top
		_feed.offset_bottom = top
	_fit_feed(Announcer.column_bottom() - (global_position.y + top))


## Shows the lines that fit in `room` px, oldest first. The rest wait, hidden with their clocks
## stopped, until a headline or the strip makes room (on a small screen or a big UI size).
func _fit_feed(room: float) -> void:
	var used := 0.0
	var full := false
	for line in _feed.get_children():
		var l := line as Label
		if l == null or l.is_queued_for_deletion():
			continue
		var h := l.get_combined_minimum_size().y
		full = full or used + h > room
		_set_waiting(l, full)
		if not full:
			used += h + FEED_SEPARATION


## A line waits hidden, its hold-and-fade clock paused, or comes back and carries on.
func _set_waiting(l: Label, waiting: bool) -> void:
	if l.visible != waiting:
		return
	l.visible = not waiting
	var t: Tween = l.get_meta(&"tween") if l.has_meta(&"tween") else null
	if t != null and t.is_valid():
		if waiting:
			t.pause()
		else:
			t.play()


# ---------- FOLLOWING THE MINIMAP ----------
## Stays right under the minimap, and glides up into its place when the minimap is hidden.
## Fades with the minimap's opacity ([ and ], see Minimap.opacity), so the two read as one.
func _process(delta: float) -> void:
	_place_feed(delta)
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
		# A boss with a lock: how to hurt it, right under "Defeat ..." (from the lock itself), or under
		# "Take ... from" when the boss carries the item and the quest has no "Defeat" for it
		if not done and not o.hidden:
			var boss := _lock_boss(s.def, o)
			if boss != "":
				var lock: Dictionary = preload("res://scenes/ui/player_ui/lock_banner/lock_banner.gd").hint_for_enemy(boss)
				if not lock.is_empty() and lock["hint"] != "":
					_box.add_child(_wrapped("    %s: %s" % [lock["name"], lock["hint"]], base_font_size - 3, COL_HINT))


## The enemy whose lock hint belongs under this objective, or "".
func _lock_boss(def: QuestDefinition, o: Objective) -> String:
	if o.kind == "kill":
		return o.target
	if o.kind != "recover":
		return ""
	var carrier := QuestItems.carrier_of(o.target)
	if carrier == "":
		return ""
	for other: Objective in def.objectives:
		if other.kind == "kill" and other.target == carrier:
			return ""                                # its "Defeat ..." already shows the hint
	return carrier


func _on_recovered(id: String) -> void:
	_show_toast("RECOVERED: %s" % QuestItems.name_of(id), COL_READY)


# ---------- TOAST ----------
## For other systems (QuestItems.toast): a sealed portal, a beacon coming back online.
func show_toast(text: String, colour: Color) -> void:
	_show_toast(text, colour)


## A new line at the bottom of the feed. The same text again while it's still up counts up
## (x2, x3) instead of adding a line.
func _show_toast(text: String, colour: Color) -> void:
	for line in _feed.get_children():
		if line.get_meta(&"text", "") == text and not line.is_queued_for_deletion() \
				and line.get_meta(&"fading", false) == false:
			var n: int = line.get_meta(&"count", 1) + 1
			line.set_meta(&"count", n)
			(line as Label).text = "%s  x%d" % [text, n]
			_hold(line as Label)
			return
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	l.set_meta(&"text", text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", base_font_size + 10)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	if _font:
		l.add_theme_font_override("font", _font)
	_wrap_if_wide(l)
	_feed.add_child(l)
	_hold(l)
	# Past FEED_MAX the oldest leave at once (the rest move up into their place)
	var live := _feed.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
	for i in range(live.size() - FEED_MAX):
		live[i].queue_free()
	# Fitted now, not next frame: a toast sent after this frame's _process (a timer, a signal)
	# would otherwise show for a frame where there's no room for it
	_fit_feed(Announcer.column_bottom() - (global_position.y + _feed.offset_top))


## A line too wide for the centre column wraps there instead of running off the screen: it keeps
## to a fixed width, centred (the feed itself spans the screen, so a plain line would stretch
## past the corner cards).
func _wrap_if_wide(l: Label) -> void:
	var screen := Announcer.screen_size()
	var width := clampf(screen.x - FEED_CORNER_ROOM * 2.0, FEED_WRAP_MIN, FEED_WRAP_MAX)
	var font := l.get_theme_font("font")
	var size_px := l.get_theme_font_size("font_size")
	var widest := 0.0
	for part in l.text.split("\n"):
		widest = maxf(widest, font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x if font else 0.0)
	if widest <= width:
		return
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	l.size.x = width                              # its height is known now, for _fit_feed's room
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


## Shows `l` fully, holds it (again, if it was already up), fades it out and frees it.
func _hold(l: Label) -> void:
	var old: Tween = l.get_meta(&"tween") if l.has_meta(&"tween") else null
	if old != null and old.is_valid():
		old.kill()
	l.modulate.a = 1.0
	l.set_meta(&"fading", false)
	var t := l.create_tween()
	t.tween_interval(FEED_HOLD + FEED_HOLD_PER_LINE * l.text.count("\n"))
	t.tween_callback(func() -> void: l.set_meta(&"fading", true))
	t.tween_property(l, "modulate:a", 0.0, FEED_FADE)
	t.tween_callback(l.queue_free)
	l.set_meta(&"tween", t)
	if not l.visible:
		t.pause()                                   # still waiting for room (_fit_feed)


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
