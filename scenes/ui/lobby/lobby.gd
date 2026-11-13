extends Control
## The co-op lobby (main menu LOBBY -> Character Select -> here). The session itself is the
## Coop autoload; this is only its screen. Three steps on one fixed panel:
##   CHOICE   HOST A GAME or JOIN A GAME
##   JOIN     the games heard on this network (Coop.found), or the host's address typed in
##   ROOM     who is in the party; the host presses START, everyone else waits
## BACK always goes one step back; from CHOICE it returns to the main menu.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const ACCENT := Color("#00E5FF")                # the menus' cyan (CyberDialog, Character Select)
const TEXT_SOFT := Color(0.66, 0.84, 0.9)       # descriptions and hints: calmer than the accent
const TEXT_WARN := Color(1.0, 0.78, 0.4)        # the status line (connecting, couldn't connect)
const PANEL_SIZE := Vector2(900, 660)           # fixed, so the panel doesn't jump between steps

enum Step { CHOICE, JOIN, ROOM }

var _step := Step.CHOICE
var _connecting := false
var _joined_address := ""

var _pages: Dictionary = {}                     # Step -> Control
var _subtitle: Label
var _searching: Label
var _host_list: VBoxContainer
var _address: LineEdit
var _room_heading: Label
var _room_list: VBoxContainer
var _room_hint: Label
var _start_btn: Button
var _status: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if SaveManager.party.is_empty():            # opened without a character (run on its own)
		get_tree().change_scene_to_file.call_deferred(MAIN_MENU)
		return
	theme = load("res://scenes/ui/theme/cyber_theme.tres")
	_build()
	Coop.roster_changed.connect(_refresh_room)
	Coop.hosts_changed.connect(_refresh_hosts)
	Coop.join_failed.connect(_on_join_failed)
	Coop.session_closed.connect(_on_session_closed)
	_show(Step.CHOICE)


func _process(_delta: float) -> void:
	if _step == Step.JOIN and Coop.is_listening():
		_searching.text = "Searching" + ".".repeat(int(Time.get_ticks_msec() / 500.0) % 4)
	if _connecting and Coop.active:             # the host let us in
		_connecting = false
		_show(Step.ROOM)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()


# ---------- STEPS ----------
func _show(step: Step) -> void:
	_step = step
	for s in _pages:
		(_pages[s] as Control).visible = s == step
	_status.text = ""
	if step == Step.JOIN:
		if not Coop.start_listening():
			_status.text = "Can't search from this window. Type the host's address instead."
		_refresh_hosts()
	else:
		Coop.stop_listening()
	if step == Step.ROOM:
		_refresh_room()


func _on_host() -> void:
	var err := Coop.host()
	if err != OK:
		_status.text = "Couldn't open a game here (%s). Is another one already hosting on this PC?" % error_string(err)
		return
	_show(Step.ROOM)


func _join(address: String, port: int) -> void:
	if _connecting:
		return
	var err := Coop.join(address, port)
	if err != OK:
		_status.text = "Couldn't start connecting (%s)." % error_string(err)
		return
	_connecting = true
	_joined_address = address
	_status.text = "Connecting to %s ..." % address


func _join_by_address() -> void:
	if _address.text.strip_edges() != "":
		_join(_address.text.strip_edges(), Coop.PORT)


func _on_join_failed(reason: String) -> void:
	_connecting = false
	if _step == Step.ROOM:
		_show(Step.JOIN)
	_status.text = reason


func _on_session_closed(reason: String) -> void:
	if Coop.in_game:
		return                                  # the game's own scenes handle that
	_connecting = false
	_show(Step.CHOICE)
	_status.text = reason


func _on_back() -> void:
	match _step:
		Step.ROOM:
			var was_host := Coop.is_host()
			Coop.leave()
			_connecting = false
			_show(Step.CHOICE if was_host else Step.JOIN)
		Step.JOIN:
			Coop.leave()                        # also drops a connection attempt in progress
			_connecting = false
			_show(Step.CHOICE)
		_:
			Coop.leave()
			get_tree().change_scene_to_file(MAIN_MENU)   # the main menu unseats the character


# ---------- LISTS ----------
func _refresh_hosts() -> void:
	if _step != Step.JOIN:
		return
	for child in _host_list.get_children():
		child.queue_free()
	var ids := Coop.found.keys()
	ids.sort()
	if ids.is_empty():
		var none := _wrapped("No games found yet.\nAsk the host to choose HOST A GAME. Both PCs need to be on the same Wi-Fi or router."
				if Coop.is_listening() else "Searching isn't available in this window.")
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		none.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_host_list.add_child(none)
		_searching.visible = Coop.is_listening()
		return
	for id: String in ids:
		var h: Dictionary = Coop.found[id]
		var full: bool = h.players >= h.max
		var other_version: bool = h.version != Coop.PROTOCOL
		var off := full or other_version
		var details := PackedStringArray()
		if str(h["class"]) != "":
			details.append(h["class"])
		details.append("%d of %d players" % [h.players, h.max])
		if other_version:
			details.append("different game version")
		var action := "FULL" if full else ("—" if other_version else "JOIN  ›")
		var row := _row("%s's game" % h.name, "   ·   ".join(details), action, off)
		row.disabled = off
		row.pressed.connect(_join.bind(h.address, h.port))
		_host_list.add_child(row)


func _refresh_room() -> void:
	if _step != Step.ROOM or _room_list == null:
		return
	for child in _room_list.get_children():
		child.queue_free()
	var ids := Coop.roster.keys()
	ids.sort()
	var me := Coop.my_id()
	for id: int in ids:
		var info: Dictionary = Coop.roster[id]
		var tags := PackedStringArray()
		if id == 1:
			tags.append("HOST")
		if id == me:
			tags.append("YOU")
		var row := _row(str(info.get("name", "Player")),
				"%s   ·   Level %d" % [str(info.get("class_id", "")).capitalize(), int(info.get("level", 1))],
				"  ".join(tags), false)
		row.focus_mode = Control.FOCUS_NONE
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE      # a card, not a button
		_room_list.add_child(row)
	_room_heading.text = "PARTY   %d / %d" % [ids.size(), Coop.MAX_PLAYERS]
	_start_btn.visible = Coop.is_host()
	if Coop.is_host():
		var addresses := ", ".join(Coop.lan_addresses())
		_room_hint.text = "Players on your network can now see this game in their list.\nIf they can't, give them this address: %s" % (
				addresses if addresses != "" else "(no network found)")
	else:
		_room_hint.text = "Waiting for the host to start the game."


# ---------- BUILDING THE SCREEN ----------
func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.035, 0.055)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var circuit := CircuitBackgroundx.new()         # the same traces as the other menus, fainter
	circuit.opacity = 0.14
	circuit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(circuit)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	var panel_box := _box(Color(0.03, 0.085, 0.12, 0.96), Color(ACCENT, 0.75))
	panel_box.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", panel_box)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	# Header: the title, and who you're playing
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	box.add_child(head)
	head.add_child(_text("CO-OP LOBBY", 44, ACCENT))
	var me := Coop.my_info()
	_subtitle = _text("Playing as %s   ·   %s   ·   Level %d" % [
			me.get("name", "?"), str(me.get("class_id", "")).capitalize(), int(me.get("level", 1))], 20, TEXT_SOFT)
	head.add_child(_subtitle)
	var rule := ColorRect.new()
	rule.color = Color(ACCENT, 0.3)
	rule.custom_minimum_size.y = 2
	box.add_child(rule)

	# CHOICE
	var choice := _page(box, Step.CHOICE)
	choice.add_child(_text("WHAT WOULD YOU LIKE TO DO?", 20, TEXT_SOFT))
	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 20)
	choice.add_child(cards)
	cards.add_child(_card("HOST A GAME",
			"Open a game on this PC. Players on your network will see it in their list, and you decide when it starts.", _on_host))
	cards.add_child(_card("JOIN A GAME",
			"Look for a game that someone on your network is hosting.", _show.bind(Step.JOIN)))
	choice.add_child(_wrapped("Everyone plays their own character and keeps their own loot and progress. The party travels together, starting in the host's town."))

	# JOIN
	var join := _page(box, Step.JOIN)
	var list_head := HBoxContainer.new()
	join.add_child(list_head)
	var heading := _text("GAMES ON THIS NETWORK", 24, ACCENT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_head.add_child(heading)
	_searching = _text("", 20, TEXT_SOFT)
	_searching.custom_minimum_size.x = 150       # room for the dots, so the text doesn't shift
	list_head.add_child(_searching)
	_host_list = _scroll_list(join)
	join.add_child(_text("Can't see the game? Type the address shown on the host's screen.", 18, TEXT_SOFT))
	var by_address := HBoxContainer.new()
	by_address.add_theme_constant_override("separation", 12)
	join.add_child(by_address)
	_address = LineEdit.new()
	_address.placeholder_text = "e.g. 192.168.1.8"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.add_theme_font_size_override("font_size", 24)
	_address.text_submitted.connect(func(_t: String) -> void: _join_by_address())
	by_address.add_child(_address)
	var address_btn := Button.new()
	address_btn.text = "CONNECT"
	address_btn.custom_minimum_size.x = 180
	_style_button(address_btn, 24)
	address_btn.pressed.connect(_join_by_address)
	by_address.add_child(address_btn)

	# ROOM
	var room := _page(box, Step.ROOM)
	_room_heading = _text("PARTY", 24, ACCENT)
	room.add_child(_room_heading)
	_room_list = _scroll_list(room)
	_room_hint = _wrapped("")
	room.add_child(_room_hint)

	# Footer: BACK, what's going on, and the host's START
	var foot := HBoxContainer.new()
	foot.custom_minimum_size.y = 56
	foot.add_theme_constant_override("separation", 20)
	box.add_child(foot)
	var back_btn := Button.new()
	back_btn.text = "‹  BACK"
	back_btn.custom_minimum_size.x = 160
	_style_button(back_btn, 24)
	back_btn.pressed.connect(_on_back)
	foot.add_child(back_btn)
	_status = _text("", 20, TEXT_WARN)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(_status)
	_start_btn = Button.new()
	_start_btn.text = "START GAME  ›"
	_start_btn.custom_minimum_size.x = 260
	_start_btn.visible = false
	_style_button(_start_btn, 26)
	_start_btn.pressed.connect(func() -> void: Coop.start_game())
	foot.add_child(_start_btn)


func _page(parent: Control, step: Step) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 12)
	page.visible = false
	parent.add_child(page)
	_pages[step] = page
	return page


func _scroll_list(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list


func _text(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _wrapped(text: String) -> Label:
	var label := _text(text, 20, TEXT_SOFT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	return sb


## The menus' button look (Character Select's values), at a readable size.
func _style_button(b: Button, font_size: int) -> void:
	b.add_theme_stylebox_override("normal", _box(Color(0.02, 0.07, 0.1, 0.7), Color(ACCENT, 0.6)))
	b.add_theme_stylebox_override("hover", _box(Color(ACCENT, 0.18), ACCENT))
	b.add_theme_stylebox_override("pressed", _box(Color(ACCENT, 0.32), ACCENT))
	b.add_theme_stylebox_override("focus", _box(Color(ACCENT, 0.1), ACCENT))
	b.add_theme_stylebox_override("disabled", _box(Color(0.02, 0.07, 0.1, 0.4), Color(ACCENT, 0.2)))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_disabled_color", Color(ACCENT, 0.3))


## A big button with a title and a line saying what it does.
func _card(title: String, about: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 200
	_style_button(b, 24)
	b.pressed.connect(on_press)
	b.add_child(_inside([_text(title, 34, ACCENT), _wrapped(about)], 24))
	return b


## A list row: a name with a line of details under it on the left, a short tag on the right.
func _row(title: String, details: String, tag: String, faded: bool) -> Button:
	var row := Button.new()
	row.custom_minimum_size.y = 84
	_style_button(row, 24)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var who := VBoxContainer.new()
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_constant_override("separation", 0)
	who.add_child(_text(title, 26, Color(ACCENT, 0.4) if faded else ACCENT))
	who.add_child(_text(details, 18, TEXT_SOFT))
	line.add_child(who)
	var right := _text(tag, 24, Color(ACCENT, 0.4) if faded else ACCENT)
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.add_child(right)
	row.add_child(_inside([line], 16))
	return row


## Lays `parts` out inside a button (a Button isn't a container), without taking its clicks.
func _inside(parts: Array, margin: int) -> Control:
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	for part: Control in parts:
		col.add_child(part)
	return pad
