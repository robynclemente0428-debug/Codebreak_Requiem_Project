class_name WaypointPanel
extends Control
## The waypoint map. Press U to open it: the current act's towns and dungeons, drawn as a
## network. Areas you have been to light up; click one to teleport there.
## Undiscovered areas show as "???" so the player can see there's more to find.
##
## Built entirely in code (like CharacterPanel). AreaManager adds it, so there is nothing to
## place in main.tscn. The places come from data/waypoints/act_*.tres (see Waypoints).
##
## The convoy's route terminal (RouteTerminal) opens the same map in route mode (open_route):
## only that act, its stops lit once the route has reached them (Waypoints.route_open), and a
## click sails the party to the stop's entrance. On the U map a convoy act shows only the
## convoy itself: its stops are reached from the terminal, not travelled to.
##
## The act tabs under the title (or the < > buttons) switch between acts.

const ACTION := &"waypoints"                    # Input Map action, created with U if missing
const DEFAULT_KEY := KEY_U
const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const FRAME_SIZE := Vector2(1240, 760)
const CHAMFER := 28.0

const ACCENT := Color("#00E5FF")
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_LOCKED := Color(0.30, 0.36, 0.42)
const COL_TOWN := Color(0.25, 1.0, 0.55)
const COL_DUNGEON := Color("#00E5FF")
const COL_BOSS := Color(1.0, 0.25, 0.32)
const COL_WARN := Color(1.0, 0.45, 0.35)

var _open := false
var _font: Font
var _act_index := 0
var _frame: Control
var _map: _MapView
var _title: Label
var _subtitle: Label
var _info_name: Label
var _info_line: Label
var _info_status: Label
var _info_ctrl: Label                 # second line under the status: the Ctrl + click hint
var _prev: Button
var _next: Button
var _hint: Label
var _tabs: HBoxContainer              # one button per act
var _route_act: WaypointAct           # set while open as the convoy's route terminal


func _enter_tree() -> void:
	add_to_group("waypoint_panel")              # so the pause menu's Esc closes the map first


func _ready() -> void:
	_ensure_action()
	_font = load(DEFAULT_FONT) if ResourceLoader.exists(DEFAULT_FONT) else null
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP          # the world can't be clicked through the map
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


## Adds the "waypoints" action bound to U, unless the project already defines it.
func _ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var ev := InputEventKey.new()
	ev.physical_keycode = DEFAULT_KEY
	InputMap.action_add_event(ACTION, ev)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _open:
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


## Open as the convoy's route terminal (open_route).
func is_route_open() -> bool:
	return _open and _route_act != null


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## The route terminal's map: only `act`, and clicking a stop sails there.
func open_route(act: WaypointAct) -> void:
	if act == null:
		return
	_route_act = act
	open()


func open() -> void:
	var acts := Waypoints.acts()
	if acts.is_empty():
		push_warning("WaypointPanel: no WaypointAct in %s" % Waypoints.ACT_FOLDER)
		return
	_open = true
	var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
	var here := Waypoints.act_of_scene(am.current_scene_path()) if am else null
	_act_index = maxi(acts.find(here), 0) if here else clampi(_act_index, 0, acts.size() - 1)
	_show_act()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func close() -> void:
	_open = false
	visible = false
	_map.hovered = null
	_route_act = null


func _show_act() -> void:
	var acts := Waypoints.acts()
	var act := _route_act if _route_act != null else acts[_act_index]
	var route := _route_act != null
	_title.text = ("CONVOY ROUTE  //  %s" if route else "WAYPOINTS  //  %s") % act.title
	_subtitle.text = "Pick a stop. The convoy drops you at its entrance." if route else act.subtitle
	_prev.visible = acts.size() > 1 and not route
	_next.visible = acts.size() > 1 and not route
	_prev.disabled = _act_index == 0
	_next.disabled = _act_index == acts.size() - 1
	_hint.text = "ESC  CLOSE" if route else "U / ESC  CLOSE"
	_tabs.visible = acts.size() > 1 and not route
	_refresh_tabs()
	_map.route = route
	var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
	_map.show_act(act, am.current_scene_path() if am else "")
	_on_hover(null)


func _on_hover(w: Waypoint) -> void:
	var route := _route_act != null
	if w == null:
		_info_name.text = "SELECT A STOP" if route else "SELECT A DESTINATION"
		_info_name.add_theme_color_override("font_color", COL_DIM)
		_info_line.text = "Reach a stop's exit to open the next one on the route." if route 				else "Areas you have visited are unlocked. Click one to travel there."
		_info_status.text = ""
		_info_ctrl.text = ""
		return
	if not _map.known(w):
		_info_name.text = "???"
		_info_name.add_theme_color_override("font_color", COL_LOCKED)
		_info_line.text = "Not on the route yet." if route else "Undiscovered. Reach it on foot to unlock it."
		_info_status.text = Waypoints.route_blocked_reason(w, get_tree()) 				if route and Waypoints.is_convoy_stop(w) else ""
		_info_status.add_theme_color_override("font_color", COL_WARN)
		_info_ctrl.text = ""
		return
	_info_name.text = w.display_name.to_upper()
	_info_name.add_theme_color_override("font_color", _MapView.kind_color(w))
	var kind := "TOWN" if w.kind == Waypoint.Kind.TOWN else "DUNGEON  ·  LEVEL %d" % w.dungeon_level
	var note := _note_of(w)
	_info_line.text = kind + ("   " + note if note != "" else "")
	var threats := DungeonThreats.preview(w.scene, w.dungeon_level)
	if not threats.is_empty():
		var tags := PackedStringArray()
		for id in threats:
			tags.append(DungeonThreats.label(id))
		_info_line.text += "   [%s]" % "  ·  ".join(tags)
	if route:
		if Waypoints.is_cleared(w):
			_info_line.text += "   CLEARED"
		var reason := "YOU ARE HERE" if w.kind == Waypoint.Kind.TOWN 				else Waypoints.route_blocked_reason(w, get_tree())
		_info_status.text = "CLICK TO SET COURSE" if reason == "" else reason
		_info_status.add_theme_color_override("font_color", ACCENT if reason == "" else COL_WARN)
		_info_ctrl.text = "CTRL+CLICK: NEW INSTANCE" if reason == "" and Waypoints.is_instanced(w) else ""
		return
	var why := Waypoints.blocked_reason(w, get_tree())
	_info_status.text = "CLICK TO TRAVEL" if why == "" else why
	_info_status.add_theme_color_override("font_color", ACCENT if why == "" else COL_WARN)
	_info_ctrl.text = ""
	if Waypoints.is_instanced(w) and Waypoints.blocked_reason(w, get_tree(), true) == "":
		_info_ctrl.text = "CTRL+CLICK: NEW INSTANCE"


func _on_pick(w: Waypoint, new_instance := false) -> void:
	var went := false
	if _route_act != null:
		went = Waypoints.is_convoy_stop(w) and Waypoints.sail(w, get_tree(), new_instance)
	else:
		went = Waypoints.travel(w, get_tree(), new_instance)
	if went:
		close()
	else:
		_on_hover(w)                                  # shows why not


## Controls the tutorial hints (autoload/tutorial_hints.gd) can outline. Empty while closed.
func tutorial_target(id: String) -> Array[Control]:
	var out: Array[Control] = []
	if not _open:
		return out
	match id:
		"map":
			out.append(_map)
	return out


func _change_act(step: int) -> void:
	_pick_act(_act_index + step)


func _pick_act(index: int) -> void:
	_act_index = clampi(index, 0, Waypoints.acts().size() - 1)
	_show_act()


## One tab per act, the shown one lit. Built again only when the number of acts changes.
func _refresh_tabs() -> void:
	var acts := Waypoints.acts()
	if _tabs.get_child_count() != acts.size():
		for c in _tabs.get_children():
			c.queue_free()
		for i in acts.size():
			var b := _tab_button(acts[i].title)
			b.pressed.connect(_pick_act.bind(i))
			_tabs.add_child(b)
	for i in _tabs.get_child_count():
		(_tabs.get_child(i) as Button).set_pressed_no_signal(i == _act_index)


# ---------- BUILDING THE UI ----------
func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_frame = _Frame.new()
	add_child(_frame)
	# Anchored to the centre with fixed offsets, so it stays centred at any window size
	_frame.anchor_left = 0.5
	_frame.anchor_right = 0.5
	_frame.anchor_top = 0.5
	_frame.anchor_bottom = 0.5
	_frame.offset_left = -FRAME_SIZE.x * 0.5
	_frame.offset_right = FRAME_SIZE.x * 0.5
	_frame.offset_top = -FRAME_SIZE.y * 0.5
	_frame.offset_bottom = FRAME_SIZE.y * 0.5
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	_frame.add_child(margin)
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
	_prev = _button("<")
	_prev.pressed.connect(_change_act.bind(-1))
	head.add_child(_prev)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	_title = _label("WAYPOINTS", 34, ACCENT)
	titles.add_child(_title)
	_subtitle = _label("", 18, COL_DIM)
	titles.add_child(_subtitle)
	_next = _button(">")
	_next.pressed.connect(_change_act.bind(1))
	head.add_child(_next)
	var close_btn := _button("X")
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	col.add_child(_tabs)

	var line := ColorRect.new()
	line.color = Color(ACCENT, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	col.add_child(line)

	_map = _MapView.new()
	_map.font = _font
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.hover_changed.connect(_on_hover)
	_map.picked.connect(_on_pick)
	col.add_child(_map)

	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 20)
	col.add_child(info)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	info.add_child(texts)
	_info_name = _label("", 26, COL_TEXT)
	texts.add_child(_info_name)
	_info_line = _label("", 18, COL_DIM)
	_info_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # a long note wraps instead of
	_info_line.custom_minimum_size.x = 1.0                     # pushing past CLICK TO SET COURSE
	_info_name.clip_text = true
	_info_name.custom_minimum_size.x = 1.0
	texts.add_child(_info_line)
	var actions := VBoxContainer.new()             # what a click does, and what Ctrl + click does
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("separation", 2)
	info.add_child(actions)
	_info_status = _label("", 22, ACCENT)
	_info_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions.add_child(_info_status)
	_info_ctrl = _label("", 15, Color(ACCENT, 0.75))
	_info_ctrl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions.add_child(_info_ctrl)

	_hint = _label("U / ESC  CLOSE", 15, Color(COL_DIM, 0.7))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_hint)


## A stop's note without the "Level 10  -  " it starts with: the line already says LEVEL 10.
static func _note_of(w: Waypoint) -> String:
	var note := w.note.strip_edges()
	var prefix := "Level %d" % w.dungeon_level
	if w.dungeon_level > 0 and note.begins_with(prefix):
		note = note.substr(prefix.length()).strip_edges()
		note = note.trim_prefix("-").strip_edges()
	return note


func _label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
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


## An act tab: dim, lit while its act is shown.
func _tab_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(130, 38)
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var lit: bool = state.contains("pressed")
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ACCENT, 0.22) if lit else (Color(0.0, 0.25, 0.32, 0.95) if state == "hover" 				else Color(0.02, 0.08, 0.12, 0.9))
		sb.border_color = Color(ACCENT, 0.9 if lit else 0.35)
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color(ACCENT, 0.6))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	return b


## The chamfered frame, same look as the other panels.
class _Frame extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := WaypointPanel.CHAMFER
		var poly := PackedVector2Array([
			Vector2(c, 0), Vector2(w, 0), Vector2(w, h - c),
			Vector2(w - c, h), Vector2(0, h), Vector2(0, c)])
		draw_colored_polygon(poly, Color(0.02, 0.05, 0.09, 0.94))
		var outline := PackedVector2Array(poly)
		outline.append(poly[0])
		draw_polyline(outline, Color(WaypointPanel.ACCENT, 0.18), 7.0, true)
		draw_polyline(outline, WaypointPanel.ACCENT, 2.0, true)


## The map itself: links, nodes, hover and click.
class _MapView extends Control:
	signal hover_changed(w: Waypoint)
	signal picked(w: Waypoint, new_instance: bool)

	const NODE_R := 30.0
	var font: Font
	var hovered: Waypoint
	var route := false                  # the route terminal's map: stops light up as the route opens
	var _act: WaypointAct
	var _here := ""
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func show_act(act: WaypointAct, current_scene: String) -> void:
		_act = act
		_here = Waypoints.normalize(current_scene)
		hovered = null
		queue_redraw()

	## Lit and clickable: discovered on the waypoint map; on the route map, open on the route
	## (the convoy itself once visited).
	## The U map leaves out a convoy act's stops (the route terminal lists them).
	func shown(w: Waypoint) -> bool:
		return route or not Waypoints.is_convoy_stop(w)

	func _shown_list() -> Array[Waypoint]:
		var out: Array[Waypoint] = []
		if _act != null:
			for w in _act.waypoints:
				if shown(w):
					out.append(w)
		return out

	func known(w: Waypoint) -> bool:
		if route and Waypoints.is_convoy_stop(w):
			return Waypoints.route_open(w)
		return Waypoints.is_discovered(w)

	static func kind_color(w: Waypoint) -> Color:
		match w.kind:
			Waypoint.Kind.TOWN: return WaypointPanel.COL_TOWN
			Waypoint.Kind.BOSS: return WaypointPanel.COL_BOSS
		return WaypointPanel.COL_DUNGEON

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()                                  # pulsing "you are here" ring

	func _pos(w: Waypoint) -> Vector2:
		if _shown_list().size() == 1:
			return size * 0.5                          # alone (a convoy act): in the middle
		var pad := Vector2(90, 70)
		return pad + w.map_position * (size - pad * 2.0)

	func _at(p: Vector2) -> Waypoint:
		if _act == null:
			return null
		for w in _shown_list():
			if _pos(w).distance_to(p) <= NODE_R + 8.0:
				return w
		return null

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var w := _at(event.position)
			if w != hovered:
				hovered = w
				hover_changed.emit(w)
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND \
						if w != null and known(w) else Control.CURSOR_ARROW
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var w := _at(event.position)
			if w != null:
				# Ctrl + click (Cmd on macOS): a fresh instance of the dungeon
				picked.emit(w, (event as InputEventMouseButton).is_command_or_control_pressed())
			accept_event()

	func _draw() -> void:
		# faint grid
		var grid_col := Color(WaypointPanel.ACCENT, 0.05)
		for x in range(0, int(size.x), 40):
			draw_line(Vector2(x, 0), Vector2(x, size.y), grid_col, 1.0)
		for y in range(0, int(size.y), 40):
			draw_line(Vector2(0, y), Vector2(size.x, y), grid_col, 1.0)
		if _act == null:
			return
		# links (each pair once)
		var drawn := {}
		for w in _shown_list():
			for other_id in w.links:
				var o := _act.find(other_id)
				if o == null or not shown(o):
					continue
				var key := [w.id, o.id]
				key.sort()
				if drawn.has(str(key)):
					continue
				drawn[str(key)] = true
				var both := known(w) and known(o)
				_link(_pos(w), _pos(o), both)
		# nodes, with their name below (or above, when that would overlap another name)
		var sides := _label_sides()
		for w in _shown_list():
			_node(w, sides.get(w, 0))

	func _link(a: Vector2, b: Vector2, lit: bool) -> void:
		var dir := (b - a).normalized()
		a += dir * NODE_R
		b -= dir * NODE_R
		if lit:
			draw_line(a, b, Color(WaypointPanel.ACCENT, 0.18), 8.0, true)
			draw_line(a, b, Color(WaypointPanel.ACCENT, 0.75), 2.5, true)
			return
		var length := a.distance_to(b)          # dashed: not walked yet
		var d := 0.0
		while d < length:
			draw_line(a + dir * d, a + dir * minf(d + 10.0, length), Color(WaypointPanel.COL_LOCKED, 0.8), 2.0)
			d += 18.0

	const NAME_SIZE := 18
	const HERE_SIZE := 14
	const ABOVE := 1
	const LOWER := 2
	const LINE_DROP := 22.0

	## Baseline of a name drawn above its node (above "YOU ARE HERE" on the current area).
	func _above_y(w: Waypoint) -> float:
		return -NODE_R - (40.0 if _is_here(w) else 14.0)

	## Where each node's name goes (missing = below, ABOVE, or LOWER: a line further down), so
	## neighbours' names never overlap.
	func _label_sides() -> Dictionary:
		var out := {}
		if font == null:
			return out
		var placed: Array[Rect2] = []
		for w in _shown_list():                      # "YOU ARE HERE" tags take their space first
			if known(w) and Waypoints.normalize(w.scene) == _here:
				placed.append(_text_rect(_pos(w), "YOU ARE HERE", HERE_SIZE, -NODE_R - 16))
		for w in _shown_list():
			var p := _pos(w)
			var name := _name_of(w)
			var below := _text_rect(p, name, NAME_SIZE, NODE_R + 30)
			var rect := below
			if _hits(below, placed):
				var up := _text_rect(p, name, NAME_SIZE, _above_y(w))
				var lower := _text_rect(p, name, NAME_SIZE, NODE_R + 30 + LINE_DROP)
				if not _hits(up, placed):
					out[w] = ABOVE
					rect = up
				elif not _hits(lower, placed):
					out[w] = LOWER                       # one line further down
					rect = lower
			placed.append(rect)
		return out

	func _text_rect(p: Vector2, text: String, fsize: int, baseline_y: float) -> Rect2:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		return Rect2(p.x - w * 0.5 - 3.0, p.y + baseline_y - fsize, w + 6.0, fsize + 4.0)

	static func _hits(r: Rect2, others: Array[Rect2]) -> bool:
		for o in others:
			if r.intersects(o):
				return true
		return false

	func _name_of(w: Waypoint) -> String:
		return w.display_name.to_upper() if known(w) else "???"

	func _is_here(w: Waypoint) -> bool:
		return known(w) and Waypoints.normalize(w.scene) == _here

	func _node(w: Waypoint, side := 0) -> void:
		var p := _pos(w)
		var lit := known(w)
		var col := kind_color(w) if lit else WaypointPanel.COL_LOCKED
		var hot := w == hovered and lit
		var r := NODE_R * (1.12 if hot else 1.0)
		var shape := _shape(w.kind, p, r)
		draw_colored_polygon(shape, Color(col, 0.22 if lit else 0.10))
		var outline := PackedVector2Array(shape)
		outline.append(shape[0])
		if lit:
			draw_polyline(outline, Color(col, 0.25), 9.0 if hot else 6.0, true)
		draw_polyline(outline, col, 2.5, true)

		var here := lit and Waypoints.normalize(w.scene) == _here
		if here:
			var pulse := 0.5 + 0.5 * sin(_t * 4.0)
			draw_arc(p, r + 10.0 + pulse * 6.0, 0.0, TAU, 48, Color(Color.WHITE, 0.35 + 0.4 * pulse), 2.0, true)

		if font == null:
			return
		var icon := "?"
		if lit:
			icon = "H" if w.kind == Waypoint.Kind.TOWN else ("!" if w.kind == Waypoint.Kind.BOSS else str(w.dungeon_level))
		draw_string(font, p + Vector2(-40, 9), icon, HORIZONTAL_ALIGNMENT_CENTER, 80, 26,
				Color.WHITE if lit else col)
		var name := _name_of(w)
		var name_y := r + 30.0
		if side == ABOVE:
			name_y = _above_y(w)
		elif side == LOWER:
			name_y += LINE_DROP
		draw_string(font, p + Vector2(-110, name_y), name, HORIZONTAL_ALIGNMENT_CENTER, 220, NAME_SIZE,
				WaypointPanel.COL_TEXT if lit else col)
		if here:
			draw_string(font, p + Vector2(-110, -r - 16), "YOU ARE HERE", HORIZONTAL_ALIGNMENT_CENTER,
					220, HERE_SIZE, Color.WHITE)

	## Towns are squares, dungeons diamonds, boss dungeons hexagons.
	func _shape(kind: Waypoint.Kind, c: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		match kind:
			Waypoint.Kind.TOWN:
				var s := r * 0.82
				pts = PackedVector2Array([c + Vector2(-s, -s), c + Vector2(s, -s), c + Vector2(s, s), c + Vector2(-s, s)])
			Waypoint.Kind.BOSS:
				for i in 6:
					pts.append(c + Vector2.from_angle(TAU * i / 6.0) * r)
			_:
				pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		return pts
