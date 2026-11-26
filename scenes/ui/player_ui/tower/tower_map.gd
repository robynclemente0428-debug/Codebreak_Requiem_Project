class_name TowerMap
extends Control
## The Recursion's map (Tower): the floors stacked bottom to top, opened from the Core's tower
## terminal (TowerTerminal). Like an atlas, every floor you can reach shows its roll before you go
## in: its level, its look (which act's tiles and enemies) and its threats. Floors above the
## revealed one show only their number.
##
## Click a floor to read it, ENTER (or double-click) to go: always a fresh run of its roll.
## Built in code like WaypointPanel, and added next to it (open() makes it on first use).

const ACCENT := WaypointPanel.ACCENT
const COL_TEXT := WaypointPanel.COL_TEXT
const COL_DIM := WaypointPanel.COL_DIM
const COL_LOCKED := WaypointPanel.COL_LOCKED
const COL_CLEARED := Color(0.35, 0.95, 0.6)
const COL_WARN := WaypointPanel.COL_WARN
const FRAME_SIZE := Vector2(1240, 760)
const ROW_H := 44.0
## The info side's width: the floor list takes the rest, and clips a row too long for it.
const INFO_W := 430.0

var _open := false
var _font: Font
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _info_name: Label
var _info_line: Label
var _info_threats: VBoxContainer
var _info_status: Label
var _enter: Button
var _progress: Label
var _selected := 0
var _staked := PackedStringArray()              # threats added to the selected floor's next run
var _stakes_title: Label
var _stakes_box: HFlowContainer
var _pays: Label
var _patch_title: Label
var _patch_box: HFlowContainer
const COL_NULL := Color(0.72, 0.42, 1.0)


## The map, made next to the waypoint map the first time it's needed.
static func get_or_make(tree: SceneTree) -> TowerMap:
	var found := tree.get_first_node_in_group("tower_map") as TowerMap
	if found != null:
		return found
	var wp := tree.get_first_node_in_group("waypoint_panel") as Control
	if wp == null or wp.get_parent() == null:
		return null
	var map := TowerMap.new()
	map.name = "TowerMap"
	wp.get_parent().add_child(map)
	return map


func _enter_tree() -> void:
	add_to_group("tower_map")                   # PauseMenu: Esc closes it first


func _ready() -> void:
	_font = load(WaypointPanel.DEFAULT_FONT) if ResourceLoader.exists(WaypointPanel.DEFAULT_FONT) else null
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	_fill()
	_select(Tower.revealed())
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	_scroll_to.call_deferred(Tower.revealed())


func close() -> void:
	_open = false
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ---------- THE FLOORS ----------
func _fill() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var top := Tower.revealed()
	for n in range(Tower.FLOORS, 0, -1):                # the top of the tower at the top
		var b := _row_button(n, top)
		b.pressed.connect(_select.bind(n))
		b.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
				_select(n)
				_go())
		_rows.add_child(b)
	_progress.text = "CLEARED %d OF %d" % [Tower.cleared_top(), Tower.FLOORS]


func _row_button(n: int, top: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.set_meta(&"floor", n)
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 19)
	b.clip_text = true                           # a long row is cut, not widening the list
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var col := COL_LOCKED
	if n > top:
		b.text = "  FLOOR %2d    ???" % n
	else:
		var s := Tower.seed_of(n)
		var look := Tower.look_of_seed(s)
		var tags := PackedStringArray()
		for id in Tower.threats_of_seed(s):
			tags.append(DungeonThreats.label(id))
		var state := "CLEARED" if Tower.is_cleared(n) else ">> NEXT"
		var null_floor := Tower.is_null_floor(s)
		b.text = "  FLOOR %2d    LV %d    %-24s %-8s  %s" % [n, Tower.level_of(n),
				("NULL: " if null_floor else "") + str(look["name"]).to_upper(), state, "  ·  ".join(tags)]
		col = COL_NULL if null_floor else COL_CLEARED if Tower.is_cleared(n) else ACCENT
		b.tooltip_text = b.text.strip_edges()     # the whole row, if it was cut
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		var lit: bool = state.contains("pressed")
		var hover: bool = state.contains("hover")
		sb.bg_color = Color(col, 0.22 if lit else 0.1 if hover else 0.04)
		sb.border_color = Color(col, 0.9 if lit else 0.35 if n == top else 0.12)
		sb.set_border_width_all(2 if lit or n == top else 1)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", col.lightened(0.3))
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	return b


func _select(n: int) -> void:
	if clampi(n, 1, Tower.FLOORS) != _selected:
		_staked = PackedStringArray()           # stakes are for one floor's next run
	_selected = clampi(n, 1, Tower.FLOORS)
	for b in _rows.get_children():
		(b as Button).set_pressed_no_signal(int(b.get_meta(&"floor", 0)) == _selected)
	for c in _info_threats.get_children() + _stakes_box.get_children() + _patch_box.get_children():
		c.queue_free()
	var top := Tower.revealed()
	_info_name.text = "FLOOR %d" % _selected
	_stakes_title.visible = _selected <= top
	_pays.visible = _selected <= top
	var player := get_tree().get_first_node_in_group("players")
	var overwrite := Tower.can_patch(player.get("quests") as QuestManager if player != null else null)
	_patch_title.visible = overwrite and _selected <= top
	_patch_title.text = "PATCHES  %d / %d   (Overwrite: +1 every %d floors climbed)" % [Tower.patches(),
			Tower.MAX_PATCHES, Tower.PATCH_EVERY]
	if _selected > top:
		_info_name.add_theme_color_override("font_color", COL_LOCKED)
		_info_line.text = "Level %d. Its roll shows once floor %d is cleared." % [Tower.level_of(_selected), _selected - 1]
	else:
		var s := Tower.seed_of(_selected)
		var look := Tower.look_of_seed(s)
		var null_floor := Tower.is_null_floor(s)
		_info_name.add_theme_color_override("font_color", COL_NULL if null_floor
				else COL_CLEARED if Tower.is_cleared(_selected) else ACCENT)
		if null_floor:
			_info_name.text += "   //  NULL FLOOR"
		_info_line.text = "Level %d   ·   %s (Act %s's tiles and enemies)%s%s" % [Tower.level_of(_selected),
				look["name"], look["act"], "   ·   CLEARED: a new run each time" if Tower.is_cleared(_selected) else "",
				"\nThe Null built this one (Merge): one more threat, +%d%% items, %d%% more raised a rarity." % [
					roundi(Tower.NULL_QUANTITY * 100.0), roundi(Tower.NULL_RARITY * 100.0)] if null_floor else ""]
		var rolled := Tower.floor_threats_of_seed(s)
		var pinned := Tower.pinned_of(s)
		var extra := Tower.null_extra(s) if null_floor else ""
		for id in rolled:
			_info_threats.add_child(_threat_line(id, false,
					"pinned from the floor below" if id in pinned else "the Null's" if id == extra else ""))
		for id in Tower.removed_of(s):
			var gone := _label("%s   patched out" % DungeonThreats.label(id), 15, COL_LOCKED)
			_info_threats.add_child(gone)
		for id in _staked:
			_info_threats.add_child(_threat_line(id, true))
		if overwrite:
			_fill_patches(s, rolled)
		# Raise the stakes: the threats it didn't roll, each with what it pays
		for id in Tower.stakeable(_selected):
			var on := id in _staked
			var b := _stake_button(id, on)
			b.disabled = not on and _staked.size() >= Tower.MAX_STAKES
			b.pressed.connect(_toggle_stake.bind(id))
			_stakes_box.add_child(b)
		var all := rolled.duplicate()
		all.append_array(_staked)
		_pays.text = "PAYS:  %s" % Tower.rewards_line(all, null_floor)
	var why := Tower.blocked_reason(_selected, get_tree())
	_info_status.text = why if why != "" else "ENTER: A FRESH RUN OF THIS ROLL"
	_info_status.add_theme_color_override("font_color", COL_WARN if why != "" else ACCENT)
	_enter.disabled = why != ""


## Overwrite's patches for the selected floor: remove a threat, pin one up a floor, or reroll.
func _fill_patches(s: int, own: PackedStringArray) -> void:
	var none := Tower.patches() <= 0
	for id in own:
		var rm := _small_button("REMOVE " + DungeonThreats.label(id), DungeonThreats.color(id))
		rm.tooltip_text = "Take %s out of this floor, and its reward: %s." % [DungeonThreats.label(id), Tower.reward_text(id)]
		rm.disabled = none
		rm.pressed.connect(_patch.bind("remove", id))
		_patch_box.add_child(rm)
		if _selected < Tower.FLOORS:
			var up := _small_button("PIN %s UP" % DungeonThreats.label(id), DungeonThreats.color(id))
			up.tooltip_text = "Floor %d gets %s too, and its reward: %s." % [_selected + 1, DungeonThreats.label(id), Tower.reward_text(id)]
			up.disabled = none or id in Tower.floor_threats_of_seed(Tower.seed_of(_selected + 1))
			up.pressed.connect(_patch.bind("pin", id))
			_patch_box.add_child(up)
	var rr := _small_button("REROLL FLOOR", ACCENT)
	rr.tooltip_text = "A new roll for this floor: its look and threats."
	rr.disabled = none
	rr.pressed.connect(_patch.bind("reroll", ""))
	_patch_box.add_child(rr)


func _patch(what: String, id: String) -> void:
	var done := false
	match what:
		"remove":
			done = Tower.patch_remove(_selected, id)
		"pin":
			done = Tower.patch_pin(_selected, id)
		"reroll":
			done = Tower.patch_reroll(_selected)
	_staked = PackedStringArray()
	var keep := _selected
	_fill()
	_select(keep)
	if done:
		_info_status.text = "PATCHED. %d LEFT." % Tower.patches()


func _small_button(text: String, c: Color) -> Button:
	var b := _button(text)
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_color_override("font_color", c)
	return b


## A threat and what it pays, for the info side. Staked ones are marked; `why` says where it came from.
func _threat_line(id: String, staked := false, why := "") -> Label:
	var l := _label("%s%s%s   %s\n      pays: %s" % ["+ " if staked else "", DungeonThreats.label(id),
			("  (" + why + ")") if why != "" else "",
			DungeonThreats.hint(id), Tower.reward_text(id)], 16, DungeonThreats.color(id))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1.0
	return l


func _stake_button(id: String, on: bool) -> Button:
	var b := _button(("- " if on else "+ ") + DungeonThreats.label(id))
	b.tooltip_text = "%s\nPays: %s" % [DungeonThreats.hint(id), Tower.reward_text(id)]
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 34)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_color_override("font_color", DungeonThreats.color(id) if not on else Color.WHITE)
	return b


func _toggle_stake(id: String) -> void:
	if id in _staked:
		_staked.remove_at(_staked.find(id))
	elif _staked.size() < Tower.MAX_STAKES:
		_staked.append(id)
	_select(_selected)


func _go() -> void:
	Tower.set_stakes(_staked)                   # spent by the run's seed (Tower.run_seed)
	if Tower.enter(_selected, get_tree()):
		_staked = PackedStringArray()
		close()
	else:
		Tower.set_stakes(PackedStringArray())
		_select(_selected)                      # shows why not


func _scroll_to(n: int) -> void:
	for b in _rows.get_children():
		if int(b.get_meta(&"floor", 0)) == n:
			_scroll.ensure_control_visible(b)
			return


# ---------- BUILDING THE UI ----------
func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var frame := WaypointPanel._Frame.new()
	add_child(frame)
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -FRAME_SIZE.x * 0.5
	frame.offset_right = FRAME_SIZE.x * 0.5
	frame.offset_top = -FRAME_SIZE.y * 0.5
	frame.offset_bottom = FRAME_SIZE.y * 0.5
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	frame.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	titles.add_child(_label("THE RECURSION", 34, ACCENT))
	titles.add_child(_label("Fifty floors up from the Core. Each one is rolled once: read it, then climb.", 18, COL_DIM))
	_progress = _label("", 20, COL_CLEARED)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_progress)
	var close_btn := _button("X")
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var line := ColorRect.new()
	line.color = Color(ACCENT, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	col.add_child(line)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size.x = 1.0
	body.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	_scroll.add_child(_rows)

	# The info side: the floor's details scroll when they run long (threats, stakes, patches),
	# and the status line and ENTER stay at the bottom.
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = INFO_W
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	var info_scroll := ScrollContainer.new()
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(info_scroll)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	info_scroll.add_child(info)
	_info_name = _label("", 30, COL_TEXT)
	info.add_child(_info_name)
	_info_line = _label("", 18, COL_DIM)
	_info_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_line.custom_minimum_size.x = 1.0
	info.add_child(_info_line)
	info.add_child(_label("THREATS", 16, Color(COL_DIM, 0.8)))
	_info_threats = VBoxContainer.new()
	_info_threats.add_theme_constant_override("separation", 6)
	info.add_child(_info_threats)
	_stakes_title = _label("RAISE THE STAKES  (up to %d more threats, for their rewards)" % Tower.MAX_STAKES,
			16, Color(COL_DIM, 0.8))
	_stakes_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stakes_title.custom_minimum_size.x = 1.0
	info.add_child(_stakes_title)
	_stakes_box = HFlowContainer.new()
	_stakes_box.add_theme_constant_override("h_separation", 6)
	_stakes_box.add_theme_constant_override("v_separation", 6)
	info.add_child(_stakes_box)
	_pays = _label("", 17, COL_CLEARED)
	_pays.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pays.custom_minimum_size.x = 1.0
	info.add_child(_pays)
	_patch_title = _label("", 16, Color(1.0, 0.85, 0.5))
	_patch_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_patch_title.custom_minimum_size.x = 1.0
	info.add_child(_patch_title)
	_patch_box = HFlowContainer.new()
	_patch_box.add_theme_constant_override("h_separation", 6)
	_patch_box.add_theme_constant_override("v_separation", 6)
	info.add_child(_patch_box)
	_info_status = _label("", 18, ACCENT)
	_info_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_status.custom_minimum_size.x = 1.0
	side.add_child(_info_status)
	_enter = _button("ENTER")
	_enter.custom_minimum_size = Vector2(0, 56)
	_enter.pressed.connect(_go)
	side.add_child(_enter)

	var hint := _label("ESC  CLOSE", 15, Color(COL_DIM, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(hint)


func _label(text: String, fsize: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(52, 52)
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 26)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.08, 0.12, 0.9) if state != "hover" else Color(0.0, 0.25, 0.32, 0.95)
		sb.border_color = Color(ACCENT, 0.25 if state == "disabled" else 0.8)
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", ACCENT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(ACCENT, 0.25))
	return b
