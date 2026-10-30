class_name NpcInfoPanel
extends Control
## Click an NPC to see who they are: name, role, a short description, what they offer
## (talk, trade) and where their quests stand for you (ready to turn in, in progress,
## available). Hovering an NPC shows a pointing-hand cursor and their name.
##
## The click is used up here, so it doesn't also fire the skill on the left mouse button.
## The card's TALK and TRADE buttons, and each quest line, work from wherever you are:
## a quest line opens the conversation right at that quest (offer, reminder or turn in).
## Walking away still closes the conversation or shop. Walking up and pressing the interact
## key works as before.
##
## AreaManager adds this panel, like the waypoint map. NPCs fill in their card with the
## "Info card" settings on Interactable (info_title, info_description).

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const ACCENT := Color("#00E5FF")
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_READY := Color(1.0, 0.82, 0.30)
const COL_ACTIVE := Color(0.45, 0.75, 1.0)
const COL_NEW := Color(0.25, 1.0, 0.55)
const CARD_WIDTH := 420.0
const CHAMFER := 18.0
const CLOSE_DISTANCE := 25.0        # walking this far from the NPC closes the card
const MOVE_CLOSE := 0.35            # the player moving this far (metres) closes the card
const RAY_LENGTH := 200.0
const REACH_MARGIN := 4.0           # opened from the card: you may walk this much further away

var _font: Font
var _card: _Card
var _tag: Label                     # name under the cursor while hovering
var _npc: Interactable
var _hovered: Interactable
var _pointing := false
var _open_pos := Vector3.ZERO       # where the player stood when the card opened


func _enter_tree() -> void:
	add_to_group("npc_info")        # so the pause menu's Esc closes the card first


func _ready() -> void:
	_font = load(DEFAULT_FONT) if ResourceLoader.exists(DEFAULT_FONT) else null
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE      # only the card itself takes clicks
	_card = _Card.new()
	_card.font = _font
	_card.visible = false
	_card.close_requested.connect(close)
	_card.action_requested.connect(_on_action)
	add_child(_card)
	_tag = Label.new()
	if _font:
		_tag.add_theme_font_override("font", _font)
	_tag.add_theme_font_size_override("font_size", 18)
	_tag.add_theme_color_override("font_color", ACCENT)
	_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_tag.add_theme_constant_override("outline_size", 6)
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.visible = false
	add_child(_tag)


func is_open() -> bool:
	return _card.visible


func close() -> void:
	_card.visible = false
	_npc = null


func open_for(npc: Interactable) -> void:
	_npc = npc
	var p := _player()
	if p != null:
		_open_pos = p.global_position
	_card.show_npc(npc, p)
	_card.visible = true
	_place_card()


# ---------- CARD ACTIONS ----------
## kind: "talk", "trade" or "quest" (arg = quest id, state = "ready" / "active" / "new").
func _on_action(kind: String, arg: String, state: String) -> void:
	var npc := _npc
	var p := _player()
	if npc == null or not is_instance_valid(npc) or p == null:
		return
	close()
	var reach := p.global_position.distance_to(npc.global_position) + REACH_MARGIN
	match kind:
		"talk":
			_talk(npc, p, "start", reach)
		"trade":
			var shop_panel := get_tree().get_first_node_in_group("shop_panel") as ShopPanel
			if shop_panel != null and npc is ShopNPC:
				GameEvents.report("talk", str(npc.get("npc_id")))
				shop_panel.open_shop(npc as ShopNPC, p, reach)
		"quest":
			if npc is DialogueNPC:
				# Brack-style dialogues name their nodes offer_ / remind_ / ready_<quest id>;
				# anything else starts at "start", which routes to the quest itself.
				var prefix: String = {"ready": "ready_", "active": "remind_", "new": "offer_"}.get(state, "")
				_talk(npc, p, prefix + arg if prefix != "" else "start", reach)
			else:
				npc.interact(p)                  # QuestGiverNPC: turns in or starts on its own


func _talk(npc: Interactable, p: Node3D, label: String, reach: float) -> void:
	if not npc is DialogueNPC:
		npc.interact(p)
		return
	var panel := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if panel == null:
		return
	GameEvents.report("talk", str(npc.get("npc_id")))
	panel.open_dialogue(npc as DialogueNPC, p, label, reach)


# ---------- HOVER AND CLICK ----------
func _process(_delta: float) -> void:
	var npc := _npc_under_mouse() if not _ui_under_mouse() else null
	if npc != _hovered:
		_hovered = npc
		_set_pointing(npc != null)
		if npc != null:
			_tag.text = "%s  [CLICK]" % _npc_name(npc)
	_tag.visible = npc != null and npc != _npc
	if _tag.visible:
		var m := get_viewport().get_mouse_position()
		_tag.position = (m + Vector2(22, 18)).round()
	if _npc != null:
		var p := _player()
		if not is_instance_valid(_npc) or p == null \
				or p.global_position.distance_to(_npc.global_position) > CLOSE_DISTANCE:
			close()
		elif Vector2(p.global_position.x - _open_pos.x, p.global_position.z - _open_pos.z).length() > MOVE_CLOSE:
			close()                                  # the player walked off
		else:
			_place_card()


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _ui_under_mouse():
		return                                       # a panel (or this card) was clicked
	var npc := _npc_under_mouse()
	if npc == null:
		return
	get_viewport().set_input_as_handled()            # no skill cast for this click
	if npc == _npc and is_open():
		close()
	else:
		open_for(npc)


## The card sits beside the NPC on screen, kept inside the window.
func _place_card() -> void:
	if _npc == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var pos := _npc_screen_pos(_npc)
	var at := pos + Vector2(60, -_card.size.y * 0.5)
	if at.x + _card.size.x > screen.x - 16.0:
		at.x = pos.x - 60.0 - _card.size.x
	at.x = clampf(at.x, 16.0, screen.x - _card.size.x - 16.0)
	at.y = clampf(at.y, 16.0, screen.y - _card.size.y - 16.0)
	_card.position = at.round()


# ---------- FINDING NPCS ----------
func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


## The 3D world lives in a SubViewport; rays use its camera and its mouse position.
func _npc_under_mouse() -> Interactable:
	var p := _player()
	if p == null:
		return null
	var vp := p.get_viewport()
	var cam := vp.get_camera_3d()
	if cam == null:
		return null
	var mouse := vp.get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var query := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(mouse) * RAY_LENGTH)
	query.collide_with_areas = false                 # the NPC's body, not its big talk radius
	query.collide_with_bodies = true
	if p is CollisionObject3D:
		query.exclude = [(p as CollisionObject3D).get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(query)
	var n := hit.get("collider") as Node
	while n != null:
		if n is Interactable:
			return n as Interactable
		n = n.get_parent()
	return null


func _npc_screen_pos(npc: Node3D) -> Vector2:
	var p := _player()
	var vp := p.get_viewport() if p else null
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		return get_viewport().get_visible_rect().size * 0.5
	var world := npc.global_position + Vector3.UP * 1.6
	var in_view := cam.unproject_position(world)
	# The small 3D view is stretched to the window, so scale its pixels up
	var ratio := get_viewport().get_visible_rect().size / Vector2(vp.get_visible_rect().size)
	return in_view * ratio


func _ui_under_mouse() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and not (hovered is SubViewportContainer)


func _set_pointing(on: bool) -> void:
	if on == _pointing:
		return
	_pointing = on
	var view := get_tree().current_scene.find_child("SubViewportContainer", true, false) as Control
	var shape := Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	if view != null:
		view.mouse_default_cursor_shape = shape
	Input.set_default_cursor_shape(shape as Input.CursorShape)


static func _npc_name(npc: Interactable) -> String:
	var n = npc.get("npc_name")
	return str(n).to_upper() if n != null and str(n) != "" else String(npc.name).capitalize().to_upper()


## The card: built as one VBox so it sizes to its text.
class _Card extends PanelContainer:
	signal close_requested
	signal action_requested(kind: String, arg: String, state: String)
	var font: Font
	var _box: VBoxContainer

	func _ready() -> void:
		custom_minimum_size.x = NpcInfoPanel.CARD_WIDTH
		mouse_filter = Control.MOUSE_FILTER_STOP
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 18
		sb.content_margin_bottom = 16
		add_theme_stylebox_override("panel", sb)
		_box = VBoxContainer.new()
		_box.add_theme_constant_override("separation", 6)
		add_child(_box)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := NpcInfoPanel.CHAMFER
		var poly := PackedVector2Array([Vector2(c, 0), Vector2(w, 0), Vector2(w, h - c),
				Vector2(w - c, h), Vector2(0, h), Vector2(0, c)])
		draw_colored_polygon(poly, Color(0.02, 0.05, 0.09, 0.94))
		var outline := PackedVector2Array(poly)
		outline.append(poly[0])
		draw_polyline(outline, Color(NpcInfoPanel.ACCENT, 0.18), 6.0, true)
		draw_polyline(outline, NpcInfoPanel.ACCENT, 2.0, true)

	func show_npc(npc: Interactable, player: Node) -> void:
		for c in _box.get_children():
			c.queue_free()
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		_box.add_child(head)
		var title := _make_label(NpcInfoPanel._npc_name(npc), 26, NpcInfoPanel.ACCENT)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		head.add_child(_close_button())
		if npc.info_title != "":
			_add(npc.info_title.to_upper(), 16, NpcInfoPanel.COL_DIM)
		_rule()
		if npc.info_description != "":
			_add(npc.info_description, 17, NpcInfoPanel.COL_TEXT, true)

		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 10)
		if npc.get("dialogue") != null:
			buttons.add_child(_action_button("TALK", "talk", "", ""))
		if npc is ShopNPC and (npc as ShopNPC).shop != null:
			buttons.add_child(_action_button("TRADE", "trade", "", ""))
		if buttons.get_child_count() > 0:
			_box.add_child(buttons)
		else:
			buttons.free()

		var qm: QuestManager = player.get("quests") if player else null
		var rows := _quest_rows(npc, qm)
		if not rows.is_empty():
			_rule()
			_add("QUESTS", 15, NpcInfoPanel.COL_DIM)
			for r in rows:
				_box.add_child(_quest_button(r[0], r[1], r[2], r[3]))

		_add("Click to act, or walk up and press [%s]" % Interactable.key_name(), 14, Color(NpcInfoPanel.COL_DIM, 0.7))
		size = Vector2.ZERO                          # shrink to the new content

	## [text, colour] per quest this NPC deals with, most urgent first. Done quests are left out.
	func _quest_rows(npc: Interactable, qm: QuestManager) -> Array:
		if qm == null:
			return []
		var ready := []
		var active := []
		var fresh := []
		var ready_ids := {}
		for s in qm.ready_to_turn_in():
			ready_ids[s.def.id] = true
		for id in NpcInfoPanel.quests_of(npc):
			var def := qm.get_def(id)
			if def == null:
				continue
			var title := def.title.capitalize() if def.title != "" else id
			if ready_ids.has(id):
				ready.append(["!  " + title + "  -  ready to turn in", NpcInfoPanel.COL_READY, id, "ready"])
			elif qm.is_active(id):
				active.append([">  " + title + "  -  in progress", NpcInfoPanel.COL_ACTIVE, id, "active"])
			elif qm.can_start(def):
				fresh.append(["+  " + title + "  -  available", NpcInfoPanel.COL_NEW, id, "new"])
		return ready + active + fresh

	## TALK / TRADE.
	func _action_button(text: String, kind: String, arg: String, state: String) -> Button:
		var b := _styled_button(text, 17, NpcInfoPanel.ACCENT)
		b.custom_minimum_size = Vector2(120, 38)
		b.pressed.connect(func() -> void: action_requested.emit(kind, arg, state))
		return b

	## One quest line, clickable: opens the conversation at that quest.
	func _quest_button(text: String, col: Color, id: String, state: String) -> Button:
		var b := _styled_button(text, 16, col, true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = NpcInfoPanel.CARD_WIDTH - 44.0
		b.tooltip_text = {"ready": "Turn in", "active": "Ask about it", "new": "Hear the offer"}.get(state, "")
		b.pressed.connect(func() -> void: action_requested.emit("quest", id, state))
		return b

	func _styled_button(text: String, fsize: int, col: Color, flat := false) -> Button:
		var b := Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if font:
			b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", fsize)
		b.add_theme_color_override("font_color", col)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		for state in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			var on: bool = state != "normal"
			sb.bg_color = Color(col, 0.22 if on else (0.0 if flat else 0.08))
			sb.border_color = Color(col, 0.9 if on else (0.0 if flat else 0.5))
			sb.set_border_width_all(0 if flat and not on else 1)
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			b.add_theme_stylebox_override(state, sb)
		return b

	## The X in the top-right corner.
	func _close_button() -> Button:
		var b := Button.new()
		b.text = "X"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(34, 34)
		b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		b.tooltip_text = "Close  [Esc]"
		if font:
			b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 18)
		for state in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.0, 0.25, 0.32, 0.95) if state == "hover" else Color(0.02, 0.08, 0.12, 0.9)
			sb.border_color = Color(NpcInfoPanel.ACCENT, 0.8)
			sb.set_border_width_all(2)
			b.add_theme_stylebox_override(state, sb)
		b.add_theme_color_override("font_color", NpcInfoPanel.ACCENT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.pressed.connect(func() -> void: close_requested.emit())
		return b

	func _make_label(text: String, fsize: int, col: Color) -> Label:
		var l := Label.new()
		l.text = text
		if font:
			l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", fsize)
		l.add_theme_color_override("font_color", col)
		return l

	func _add(text: String, fsize: int, col: Color, wrap := false) -> void:
		var l := Label.new()
		l.text = text
		if font:
			l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", fsize)
		l.add_theme_color_override("font_color", col)
		if wrap:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = NpcInfoPanel.CARD_WIDTH - 44.0
		_box.add_child(l)

	func _rule() -> void:
		var r := ColorRect.new()
		r.color = Color(NpcInfoPanel.ACCENT, 0.3)
		r.custom_minimum_size.y = 1
		_box.add_child(r)


## Quest ids an NPC hands out or takes back: its `offers` (QuestGiverNPC) plus every quest its
## dialogue mentions in start_quest / turn_in / can_start: / quest_ready: / quest_active:.
static func quests_of(npc: Interactable) -> PackedStringArray:
	var ids := PackedStringArray()
	var offers = npc.get("offers")
	if offers is Array:
		for q in offers:
			if q != null and not ids.has(q.id):
				ids.append(q.id)
	var dlg = npc.get("dialogue")
	if dlg is DialogueData:
		var re := RegEx.create_from_string(
				"(?:start_quest|turn_in|can_start:|quest_ready:|quest_active:)\\s*([A-Za-z0-9_]+)")
		for m in re.search_all(dlg.source):
			var id := m.get_string(1)
			if not ids.has(id):
				ids.append(id)
	return ids
