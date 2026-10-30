class_name QuestLogPanel
extends Control
## Quest log window (J). Left: quests grouped as READY / ACTIVE / COMPLETED.
## Right: the selected quest's description, objectives and rewards.

@export var panel_width: float = 860.0
@export var panel_height: float = 580.0
@export_range(0.0, 1.0, 0.01) var bg_opacity: float = 0.92
@export var font: Font
@export var accent := Color("#00E5FF")

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const CHAMFER := 24.0

const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_DONE := Color(0.35, 1.0, 0.65)
const COL_READY := Color(1.0, 0.82, 0.30)
const COL_CREDIT := Color(1.0, 0.82, 0.30)

var _font: Font
var _quests: QuestManager
var _built := false
var _open := false
var _dirty := true
var _tween: Tween
var _selected_id := ""

var _list_box: VBoxContainer
var _detail_box: VBoxContainer


func _enter_tree() -> void:
	add_to_group("quest_log")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -panel_width * 0.5
	offset_right = panel_width * 0.5
	offset_top = -panel_height * 0.5
	offset_bottom = panel_height * 0.5
	resized.connect(queue_redraw)
	_build_ui()
	_built = true
	visible = false
	modulate.a = 0.0


# ---------- PUBLIC ----------
func bind(quests: QuestManager) -> void:
	if _quests:
		for sig in [_quests.quest_started, _quests.quest_updated,
				_quests.quest_ready, _quests.quest_completed]:
			if sig.is_connected(_on_quests_changed):
				sig.disconnect(_on_quests_changed)
	_quests = quests
	if _quests:
		_quests.quest_started.connect(_on_quests_changed)
		_quests.quest_updated.connect(_on_quests_changed)
		_quests.quest_ready.connect(_on_quests_changed)
		_quests.quest_completed.connect(_on_quests_changed)
	_dirty = true


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open or not _built:
		return
	_open = true
	_refresh()
	visible = true
	_fade(1.0)


func close() -> void:
	if not _open:
		return
	_open = false
	_fade(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_J:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _open:
		close()
		get_viewport().set_input_as_handled()


func _fade(target: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", target, 0.16)
	if target <= 0.0:
		_tween.finished.connect(func() -> void:
			if not _open:
				visible = false)


func _on_quests_changed(_state = null) -> void:
	_dirty = true
	if _open:
		_refresh()


# ---------- BUILDING THE UI ----------
func _draw() -> void:
	var w := size.x
	var h := size.y
	var c := CHAMFER
	var pts := PackedVector2Array([
		Vector2(c, 0), Vector2(w, 0), Vector2(w, h - c),
		Vector2(w - c, h), Vector2(0, h), Vector2(0, c)])
	draw_colored_polygon(pts, Color(0.02, 0.06, 0.09, bg_opacity))
	var line := pts.duplicate()
	line.append(pts[0])
	draw_polyline(line, accent, 2.0)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var title_row := HBoxContainer.new()
	col.add_child(title_row)
	var title := _label("// QUEST LOG //", 26, accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn := _button("X", 20)
	close_btn.custom_minimum_size = Vector2(44, 36)
	close_btn.pressed.connect(close)
	title_row.add_child(close_btn)

	col.add_child(_rule())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	col.add_child(body)

	# left: quest list
	var left := ScrollContainer.new()
	left.custom_minimum_size.x = 280
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(left)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	left.add_child(_list_box)

	# right: details
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _flat(Color(0, 0, 0, 0.30), Color(accent, 0.35), 1))
	body.add_child(frame)
	var right := ScrollContainer.new()
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(right)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 6)
	right.add_child(_detail_box)

	var hint := _label("[ J ] CLOSE   |   TURN IN COMPLETED QUESTS AT THE QUEST GIVER", 13, COL_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)


# ---------- REFRESHING ----------
func _refresh() -> void:
	if _quests == null or not _dirty:
		return
	_dirty = false

	var ready_ids: Array[String] = []
	var active_ids: Array[String] = []
	for s: QuestState in _quests.active.values():
		if s.status == QuestState.Status.READY_TO_TURN_IN:
			ready_ids.append(s.def.id)
		else:
			active_ids.append(s.def.id)
	var done_ids: Array[String] = _quests.completed_ids.duplicate()

	# keep the selection if it still exists, otherwise pick the most relevant quest
	var all_ids := ready_ids + active_ids + done_ids
	if _selected_id == "" or not all_ids.has(_selected_id):
		_selected_id = all_ids[0] if not all_ids.is_empty() else ""

	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()

	if all_ids.is_empty():
		_list_box.add_child(_label("NO QUESTS YET", 15, COL_DIM))
	_add_section("READY TO TURN IN", ready_ids, COL_READY)
	_add_section("ACTIVE", active_ids, COL_TEXT)
	_add_section("COMPLETED", done_ids, COL_DIM)
	_update_detail()


func _add_section(heading: String, ids: Array[String], colour: Color) -> void:
	if ids.is_empty():
		return
	var head := _label("%s  (%d)" % [heading, ids.size()], 14, COL_DIM)
	head.add_theme_constant_override("outline_size", 0)
	_list_box.add_child(head)
	for id in ids:
		var q := _quests.get_def(id)
		if q == null:
			continue
		var b := _button(q.title.to_upper(), 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 36
		b.clip_text = true
		b.add_theme_color_override("font_color", colour)
		if id == _selected_id:
			b.add_theme_stylebox_override("normal", _flat(Color(accent, 0.18), accent, 1))
		b.pressed.connect(_on_quest_picked.bind(id))
		_list_box.add_child(b)


func _on_quest_picked(id: String) -> void:
	_selected_id = id
	_dirty = true
	_refresh()


func _update_detail() -> void:
	for child in _detail_box.get_children():
		_detail_box.remove_child(child)
		child.queue_free()

	var q := _quests.get_def(_selected_id) if _selected_id != "" else null
	if q == null:
		_detail_box.add_child(_label("SELECT A QUEST", 15, COL_DIM))
		return

	var state: QuestState = _quests.get_state(_selected_id)
	var finished := _quests.is_completed(_selected_id)

	_detail_box.add_child(_wrapped(q.title.to_upper(), 24, accent))
	if finished:
		_detail_box.add_child(_label("[ COMPLETED ]", 15, COL_DONE))
	elif state != null and state.status == QuestState.Status.READY_TO_TURN_IN:
		_detail_box.add_child(_label("[ READY: RETURN TO THE QUEST GIVER ]", 15, COL_READY))
	if q.description != "":
		_detail_box.add_child(_wrapped(q.description, 15, COL_DIM))

	_detail_box.add_child(_rule())
	_detail_box.add_child(_label("OBJECTIVES", 16, COL_DIM))
	for i in q.objectives.size():
		var o: Objective = q.objectives[i]
		var have: int = o.required if finished else (state.progress[i] if state != null else 0)
		var done := have >= o.required
		var text := o.description
		if o.hidden and not done:
			text = "???"
		var mark := "[X] " if done else "[ ] "
		var suffix := "" if o.required <= 1 else "   %d / %d" % [have, o.required]
		_detail_box.add_child(_wrapped(mark + text + suffix, 17, COL_DONE if done else COL_TEXT))

	if q.reward_credits > 0 or not q.reward_items.is_empty():
		_detail_box.add_child(_rule())
		_detail_box.add_child(_label("REWARDS", 16, COL_DIM))
		if q.reward_credits > 0:
			_detail_box.add_child(_label("%d CR" % q.reward_credits, 17, COL_CREDIT))
		for def in q.reward_items:
			var n = def.get("display_name")
			_detail_box.add_child(_label(str(n if n != null else def.id).to_upper(), 17, COL_TEXT))


# ---------- STYLING HELPERS ----------
func _label(text: String, size_px: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
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


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size.y = 1
	r.color = Color(accent, 0.35)
	return r


func _flat(bg: Color, border: Color, border_px: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_px)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _button(text: String, size_px: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size_px)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", accent)
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_stylebox_override("normal", _flat(Color(0, 0, 0, 0.25), Color(accent, 0.35), 1))
	b.add_theme_stylebox_override("hover", _flat(Color(accent, 0.12), accent, 1))
	b.add_theme_stylebox_override("pressed", _flat(Color(accent, 0.25), accent, 1))
	return b
