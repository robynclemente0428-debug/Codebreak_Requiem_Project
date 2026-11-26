class_name PartyMenu
extends Control
## Co-op: click another player's character to see a small menu by them:
##   INFO    their character sheet, in the character panel (CharacterPanel.inspect), as their
##           own machine has it (Coop.ask_info): refreshed while it stays open
##   TRADE   asks them to trade. If they accept, both get the trade window.
## The click is used up here, so it doesn't also fire the skill on the left mouse button (like
## NpcInfoPanel). Hovering another player shows a pointing hand and their name.
##
## ---- Trading ----
## Each side offers items from their backpack (click one to offer it, click it again to take it
## back) and credits. Any change to either offer takes back both ACCEPTs. When both have
## accepted the same two offers, each machine checks its side (the items are still in the
## backpack, the credits are there, the backpack has room for what comes in) and says COMMIT; when
## a machine has both commits for those offers, it swaps: its items and credits out, the other's
## in, then saves. Messages go straight to the other player (Coop.trade_send):
##   "ask" / "answer" [yes, why]                       a trade request, and its answer
##   "offer"  [items (ItemInstance.to_dict), credits, version]   our offer, whenever it changes
##   "accept" [on, our version, their version]         ACCEPT, for exactly these two offers
##   "commit" [our version, their version]             checked on our side: swap
##   "cancel" [why]                                    the window closes on both
## AreaManager adds this panel beside the NPC info card. In single player it does nothing.

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const ACCENT := Color("#00E5FF")
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_OK := Color(0.30, 1.0, 0.55)
const COL_WARN := Color(1.0, 0.35, 0.35)
const COL_GOLD := Color(1.0, 0.82, 0.30)
const COL_BG := Color(0.02, 0.06, 0.08, 0.94)
const RAY_LENGTH := 200.0
const REQUEST_SECONDS := 20.0          # a trade request nobody answers is dropped after this
const INFO_REFRESH := 2.0              # seconds between refreshes of an open INFO sheet
const MAX_OFFER := 12                  # items one side may offer

var _font: Font
var _menu: PanelContainer
var _menu_box: VBoxContainer
var _menu_peer := 0
var _tag: Label
var _hovered: Player
var _pointing := false
var _request: PanelContainer
var _request_label: Label
var _request_peer := 0
var _request_left := 0.0
var _asking_peer := 0                  # we asked them to trade, waiting for the answer
var _asking_left := 0.0
var _info_peer := 0
var _info_in := 0.0
var _info_shown := false               # their sheet arrived and is showing (until then: waiting)
var _trade: _Trade
var _tooltip: ItemTooltip


func _enter_tree() -> void:
	add_to_group("party_menu")         # the pause menu's Esc closes it first


func _ready() -> void:
	_font = load(DEFAULT_FONT) if ResourceLoader.exists(DEFAULT_FONT) else null
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag = _label("", 18, ACCENT)
	_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_tag.add_theme_constant_override("outline_size", 6)
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.visible = false
	add_child(_tag)
	_build_menu()
	_build_request()
	_trade = _Trade.new()
	_trade.menu = self
	_trade.visible = false
	add_child(_trade)
	_tooltip = ItemTooltip.new()
	_tooltip.visible = false
	_tooltip.z_index = 10
	add_child(_tooltip)
	Coop.player_info.connect(_on_player_info)
	Coop.trade_message.connect(_on_trade_message)


func is_open() -> bool:
	return _menu.visible or _request.visible or _trade.visible


## Esc (the pause menu): the menu, then a request (declined), then the trade (cancelled).
func close() -> void:
	if _menu.visible:
		_menu.visible = false
	elif _request.visible:
		_answer_request(false)
	elif _trade.visible:
		_trade.cancel("CANCELLED")


# ---------- HOVER AND CLICK ----------
func _process(delta: float) -> void:
	if not Coop.in_game:
		if is_open():
			_menu.visible = false
			_request.visible = false
			_trade.visible = false
		_set_hover(null)
		return
	_set_hover(null if _ui_under_mouse() else _player_under_mouse())
	if _menu.visible:
		var p := Coop.player_node(_menu_peer)
		if p == null or not p.visible:
			_menu.visible = false
	if _request.visible:
		_request_left -= delta
		if _request_left <= 0.0 or Coop.player_node(_request_peer) == null:
			_answer_request(false)
	if _asking_peer != 0:
		_asking_left -= delta
		if _asking_left <= 0.0:
			_toast("NO ANSWER FROM %s" % Coop.peer_name(_asking_peer).to_upper(), COL_DIM)
			_asking_peer = 0
	if _trade.visible:
		var partner := Coop.player_node(_trade.peer)
		if partner == null or not partner.visible:
			_trade.close_trade("%s LEFT" % Coop.peer_name(_trade.peer).to_upper())
	if _info_peer != 0:
		var sheet := _character_panel()
		_info_in -= delta
		if not _info_shown:
			if _info_in <= -3.0:                 # no answer in a few seconds: forget it
				_info_peer = 0
		elif sheet == null or sheet.inspected_peer() != _info_peer:
			_info_peer = 0                       # the sheet was closed, or shows someone else
		elif _info_in <= 0.0:
			_info_in = INFO_REFRESH
			Coop.ask_info(_info_peer)


func _input(event: InputEvent) -> void:
	if not Coop.in_game or not (event is InputEventMouseButton and event.pressed):
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	if _ui_under_mouse():
		return                                       # a panel (or this menu) takes it
	var p := _player_under_mouse()
	if p == null:
		_menu.visible = false                        # a click in the world closes the menu
		return
	get_viewport().set_input_as_handled()            # no skill cast for this click
	var peer := Coop.player_peer(p)
	if _menu.visible and _menu_peer == peer:
		_menu.visible = false
	else:
		_open_menu(peer)


func _set_hover(p: Player) -> void:
	if p != _hovered:
		_hovered = p
		_set_pointing(p != null)
		if p != null:
			_tag.text = "%s  [CLICK]" % Coop.peer_name(Coop.player_peer(p)).to_upper()
			_tag.add_theme_color_override("font_color", Coop.player_colour(Coop.player_peer(p)))
	_tag.visible = p != null and not _menu.visible
	if _tag.visible:
		_tag.position = (get_viewport().get_mouse_position() + Vector2(22, 18)).round()


## Another player's character under the mouse (its body), or null.
func _player_under_mouse() -> Player:
	var me := Coop.own_player(get_tree()) as Node3D
	if me == null:
		return null
	var vp := me.get_viewport()
	var cam := vp.get_camera_3d()
	if cam == null:
		return null
	var mouse := vp.get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var query := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(mouse) * RAY_LENGTH)
	query.collide_with_areas = false
	if me is CollisionObject3D:
		query.exclude = [(me as CollisionObject3D).get_rid()]
	var n := me.get_world_3d().direct_space_state.intersect_ray(query).get("collider") as Node
	while n != null:
		if n is Player:
			return n as Player if (n as Player).is_remote and (n as Player).visible else null
		n = n.get_parent()
	return null


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


# ---------- THE MENU ----------
func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", _box_style(ACCENT))
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.visible = false
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 6)
	_menu.add_child(_menu_box)
	add_child(_menu)


func _open_menu(peer: int) -> void:
	_menu_peer = peer
	for c in _menu_box.get_children():
		c.queue_free()
	var info: Dictionary = Coop.roster.get(peer, {})
	var name_l := _label(Coop.peer_name(peer).to_upper(), 20, Coop.player_colour(peer))
	_menu_box.add_child(name_l)
	var class_id := str(info.get("class_id", ""))
	_menu_box.add_child(_label("%s  ·  %s" % [class_id.capitalize().to_upper(), Coop.rank_name(peer)], 14, COL_DIM))
	var info_b := _button("INFO", func() -> void: _show_info(peer))
	_menu_box.add_child(info_b)
	var trade_b := _button("TRADE", func() -> void: _ask_trade(peer))
	trade_b.disabled = _trade.visible or _asking_peer != 0
	_menu_box.add_child(trade_b)
	_menu.visible = true
	_menu.reset_size()
	var screen := get_viewport().get_visible_rect().size
	var at := get_viewport().get_mouse_position() + Vector2(16, -10)
	at.x = clampf(at.x, 16.0, screen.x - _menu.size.x - 16.0)
	at.y = clampf(at.y, 16.0, screen.y - _menu.size.y - 16.0)
	_menu.position = at.round()


# ---------- INFO ----------
func _show_info(peer: int) -> void:
	_menu.visible = false
	_info_peer = peer
	_info_in = INFO_REFRESH
	_info_shown = false
	Coop.ask_info(peer)


func _on_player_info(peer: int, info: Dictionary) -> void:
	if peer != _info_peer:
		return
	var sheet := _character_panel()
	if sheet != null:
		sheet.inspect(peer, info)
		_info_shown = true
		_info_in = INFO_REFRESH


func _character_panel() -> CharacterPanel:
	return get_tree().get_first_node_in_group("character_panel") as CharacterPanel


# ---------- TRADE REQUESTS ----------
func _ask_trade(peer: int) -> void:
	_menu.visible = false
	if _trade.visible or _asking_peer != 0:
		return
	_asking_peer = peer
	_asking_left = REQUEST_SECONDS
	Coop.trade_send(peer, "ask")
	_toast("TRADE REQUEST SENT TO %s" % Coop.peer_name(peer).to_upper(), COL_DIM)


func _build_request() -> void:
	_request = PanelContainer.new()
	_request.add_theme_stylebox_override("panel", _box_style(COL_GOLD))
	_request.mouse_filter = Control.MOUSE_FILTER_STOP
	_request.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_request.add_child(box)
	_request_label = _label("", 18, COL_GOLD)
	_request_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_request_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_button("ACCEPT", func() -> void: _answer_request(true)))
	row.add_child(_button("DECLINE", func() -> void: _answer_request(false)))
	box.add_child(row)
	add_child(_request)


func _answer_request(yes: bool) -> void:
	if not _request.visible:
		return
	_request.visible = false
	var peer := _request_peer
	_request_peer = 0
	if yes and not _trade.visible and Coop.player_node(peer) != null:
		Coop.trade_send(peer, "answer", [true, ""])
		_trade.start(peer)
	else:
		Coop.trade_send(peer, "answer", [false, "DECLINED"])


func _on_trade_message(peer: int, what: String, args: Array) -> void:
	match what:
		"ask":
			if _trade.visible or _request.visible or _asking_peer != 0:
				Coop.trade_send(peer, "answer", [false, "BUSY"])
				return
			_request_peer = peer
			_request_left = REQUEST_SECONDS
			_request_label.text = "%s WANTS TO TRADE" % Coop.peer_name(peer).to_upper()
			_request.visible = true
			_request.reset_size()
			var screen := get_viewport().get_visible_rect().size
			_request.position = Vector2((screen.x - _request.size.x) * 0.5, screen.y * 0.22).round()
		"answer":
			if peer != _asking_peer:
				return
			_asking_peer = 0
			if args.size() > 0 and bool(args[0]):
				_trade.start(peer)
			else:
				var why := str(args[1]).left(24) if args.size() > 1 else "DECLINED"
				_toast("%s: %s" % [Coop.peer_name(peer).to_upper(), why], COL_WARN)
		_:
			if _trade.visible and peer == _trade.peer:
				_trade.on_message(what, args)


# ---------- TOOLTIP (the trade window's items) ----------
func show_tooltip(item: ItemInstance) -> void:
	if item == null:
		_tooltip.hide_item()
		_tooltip.visible = false
		return
	var me := Coop.own_player(get_tree())
	_tooltip.show_item(item, me.get("equipment") as EquipmentComponent if me != null else null)
	_tooltip.visible = true
	_tooltip.reset_size()
	var screen := get_viewport().get_visible_rect().size
	var at := get_viewport().get_mouse_position() + Vector2(20, 12)
	if at.x + _tooltip.size.x > screen.x - 12.0:
		at.x = get_viewport().get_mouse_position().x - _tooltip.size.x - 20.0
	at.y = clampf(at.y, 12.0, maxf(screen.y - _tooltip.size.y - 12.0, 12.0))
	_tooltip.position = at.round()


# ---------- HELPERS ----------
func _toast(text: String, col: Color) -> void:
	QuestItems.toast(get_tree(), text, col)


func _label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, on_press: Callable, fsize := 17) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(COL_DIM, 0.45))
	b.add_theme_stylebox_override("normal", _flat(Color(0.03, 0.10, 0.13, 0.95), Color(ACCENT, 0.45)))
	b.add_theme_stylebox_override("hover", _flat(Color(0.05, 0.16, 0.20, 0.95), ACCENT))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.0, 0.25, 0.30, 0.95), ACCENT))
	b.add_theme_stylebox_override("disabled", _flat(Color(0.02, 0.05, 0.06, 0.8), Color(COL_DIM, 0.2)))
	b.pressed.connect(on_press)
	return b


func _box_style(edge: Color) -> StyleBoxFlat:
	var sb := _flat(COL_BG, Color(edge, 0.8))
	sb.set_content_margin_all(14)
	return sb


static func _flat(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	return sb


# ---------- THE TRADE WINDOW ----------
class _Trade extends PanelContainer:
	var menu: PartyMenu
	var peer := 0
	var _mine: Array[ItemInstance] = []          # our offer: items still in our backpack
	var _credits := 0
	var _version := 0
	var _theirs: Array = []                      # their offer, as they sent it (to_dict)
	var _their_items: Array[ItemInstance] = []   # ...built from it, for showing
	var _their_credits := 0
	var _their_version := -1
	var _i_accept := false
	var _they_accept := false
	var _committed := false
	var _their_commit := false
	var _done := false
	var _send_in := -1.0                         # > 0: our offer changed, send it when this runs out

	var _title: Label
	var _mine_head: Label
	var _theirs_head: Label
	## The same slots as the inventory's backpack (InventoryPanel.ItemSlot): your backpack in
	## its own order (offered items lit up), and each offer's slots.
	var _mine_grid: GridContainer
	var _theirs_grid: GridContainer
	var _bag_grid: GridContainer
	var _bag_count: Label
	var _credits_box: SpinBox
	var _their_credits_l: Label
	var _accept_b: Button
	var _status: Label

	func _ready() -> void:
		add_theme_stylebox_override("panel", menu._box_style(PartyMenu.ACCENT))
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(820, 0)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		add_child(box)
		_title = menu._label("", 22, PartyMenu.ACCENT)
		box.add_child(_title)
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 18)
		box.add_child(cols)
		# Our offer
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(left)
		_mine_head = menu._label("", 17, PartyMenu.COL_TEXT)
		left.add_child(_mine_head)
		_mine_grid = _grid(left, OFFER_COLUMNS, PartyMenu.MAX_OFFER, _on_offer_slot)
		var credit_row := HBoxContainer.new()
		credit_row.add_child(menu._label("CREDITS ", 16, PartyMenu.COL_GOLD))
		_credits_box = SpinBox.new()
		_credits_box.min_value = 0
		_credits_box.step = 1
		_credits_box.rounded = true
		_credits_box.custom_minimum_size.x = 160
		_credits_box.value_changed.connect(_on_credits)
		credit_row.add_child(_credits_box)
		left.add_child(credit_row)
		# Their offer
		var right := VBoxContainer.new()
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(right)
		_theirs_head = menu._label("", 17, PartyMenu.COL_TEXT)
		right.add_child(_theirs_head)
		_theirs_grid = _grid(right, OFFER_COLUMNS, PartyMenu.MAX_OFFER, Callable())
		_their_credits_l = menu._label("", 16, PartyMenu.COL_GOLD)
		right.add_child(_their_credits_l)
		# Our backpack, laid out like the inventory's
		var bag_head := HBoxContainer.new()
		var bag_title := menu._label("YOUR BACKPACK", 17, PartyMenu.COL_TEXT)
		bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bag_head.add_child(bag_title)
		_bag_count = menu._label("", 15, PartyMenu.COL_DIM)
		bag_head.add_child(_bag_count)
		box.add_child(bag_head)
		box.add_child(menu._label("Click an item to offer it; click it in your offer to take it back.",
				13, PartyMenu.COL_DIM))
		var inv := _inventory()
		_bag_grid = _grid(box, BAG_COLUMNS, inv.capacity if inv != null else 30, _on_bag_slot)
		# Buttons
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		_accept_b = menu._button("ACCEPT", _on_accept)
		row.add_child(_accept_b)
		row.add_child(menu._button("CANCEL", func() -> void: cancel("CANCELLED")))
		_status = menu._label("", 15, PartyMenu.COL_DIM)
		_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(_status)
		box.add_child(row)

	const SLOT_SIZE := 60.0
	const BAG_COLUMNS := 10
	const OFFER_COLUMNS := 6

	## A grid of `count` inventory slots (InventoryPanel.ItemSlot). A left click on a slot with
	## an item calls on_click(item).
	func _grid(parent: Control, columns: int, count: int, on_click: Callable) -> GridContainer:
		var grid := GridContainer.new()
		grid.columns = columns
		grid.add_theme_constant_override("h_separation", 5)
		grid.add_theme_constant_override("v_separation", 5)
		parent.add_child(grid)
		_fit_slots(grid, count, on_click)
		return grid

	func _fit_slots(grid: GridContainer, count: int, on_click: Callable) -> void:
		while grid.get_child_count() > count:
			var last := grid.get_child(grid.get_child_count() - 1)
			grid.remove_child(last)
			last.queue_free()
		while grid.get_child_count() < count:
			var s := InventoryPanel.ItemSlot.new()
			s.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
			s.accent = PartyMenu.ACCENT
			s.font = menu._font if menu._font != null else ThemeDB.fallback_font
			s.rarity_colors = InventoryPanel.RARITY_COLORS
			s.disabled_label = "OFFERED"
			s.hovered.connect(func(slot) -> void: menu.show_tooltip(slot.item))
			s.unhovered.connect(func() -> void: menu.show_tooltip(null))
			if on_click.is_valid():
				s.clicked.connect(func(slot, button: int, _double: bool) -> void:
					if button == MOUSE_BUTTON_LEFT and slot.item != null:
						on_click.call(slot.item))
			grid.add_child(s)

	## An offered item is greyed out in the backpack and can't be clicked there: it comes back
	## by clicking it in YOUR OFFER.
	func _on_bag_slot(item: ItemInstance) -> void:
		if not item in _mine:
			_offer(item)

	func _on_offer_slot(item: ItemInstance) -> void:
		_take_back(item)

	# ---- opening and closing ----
	func start(p_peer: int) -> void:
		peer = p_peer
		_mine.clear()
		_credits = 0
		_version = 0
		_theirs.clear()
		_their_items.clear()
		_their_credits = 0
		_their_version = -1
		_i_accept = false
		_they_accept = false
		_committed = false
		_their_commit = false
		_done = false
		var inv := _inventory()
		if inv != null and not inv.changed.is_connected(_on_bag_changed):
			inv.changed.connect(_on_bag_changed)
		var wallet := _wallet()
		_credits_box.set_value_no_signal(0)
		_credits_box.max_value = wallet.amount if wallet != null else 0
		visible = true
		_refresh()
		reset_size()
		var screen := get_viewport().get_visible_rect().size
		position = ((screen - size) * 0.5).round()
		_send_offer()

	## Ours: tell them and close.
	func cancel(why: String) -> void:
		if not visible:
			return
		Coop.trade_send(peer, "cancel", [why])
		close_trade(why)

	func close_trade(why: String) -> void:
		if not visible:
			return
		visible = false
		menu.show_tooltip(null)
		var inv := _inventory()
		if inv != null and inv.changed.is_connected(_on_bag_changed):
			inv.changed.disconnect(_on_bag_changed)
		if why != "":
			menu._toast("TRADE: %s" % why, PartyMenu.COL_OK if _done else PartyMenu.COL_WARN)

	func _process(delta: float) -> void:
		if _send_in > 0.0:
			_send_in -= delta
			if _send_in <= 0.0:
				_send_offer()

	# ---- our offer ----
	func _offer(item: ItemInstance) -> void:
		if _locked() or _mine.size() >= PartyMenu.MAX_OFFER or item in _mine:
			return
		_mine.append(item)
		_send_offer()

	func _take_back(item: ItemInstance) -> void:
		if _locked():
			return
		_mine.erase(item)
		_send_offer()

	func _on_credits(v: float) -> void:
		if _locked():
			_credits_box.set_value_no_signal(_credits)
			return
		_credits = int(v)
		_send_in = 0.35                            # typing a number sends once, not per digit

	## Our backpack changed (a drop, a sale): an offered item that left it leaves the offer.
	func _on_bag_changed() -> void:
		var inv := _inventory()
		var before := _mine.size()
		_mine.assign(_mine.filter(func(i: ItemInstance) -> bool: return inv != null and inv.has_item(i)))
		var wallet := _wallet()
		_credits_box.max_value = wallet.amount if wallet != null else 0
		if _mine.size() != before and not _committed:
			_send_offer()
		else:
			_refresh()

	## A new version of our offer: both ACCEPTs are taken back.
	func _send_offer() -> void:
		_send_in = -1.0
		_version += 1
		_i_accept = false
		_they_accept = false
		_committed = false
		_their_commit = false
		var dicts: Array = []
		for i in _mine:
			dicts.append(i.to_dict())
		Coop.trade_send(peer, "offer", [dicts, _credits, _version])
		_refresh()

	func _locked() -> bool:
		return _committed or _done

	# ---- accepting and swapping ----
	func _on_accept() -> void:
		if _locked() or _their_version < 0:
			return
		_i_accept = not _i_accept
		Coop.trade_send(peer, "accept", [_i_accept, _version, _their_version])
		_refresh()
		_check_both()

	func on_message(what: String, args: Array) -> void:
		match what:
			"offer":
				if args.size() < 3 or not args[0] is Array:
					return
				_theirs = (args[0] as Array).slice(0, PartyMenu.MAX_OFFER)
				_their_items.clear()
				for d in _theirs:
					var it := ItemInstance.from_dict(d) if d is Dictionary else null
					if it != null:
						_their_items.append(it)
				_their_credits = clampi(int(args[1]), 0, 1000000000)
				_their_version = int(args[2])
				_i_accept = false
				_they_accept = false
				_committed = false
				_their_commit = false
				_refresh()
			"accept":
				# Theirs counts only for exactly the two offers we have now
				_they_accept = args.size() >= 3 and bool(args[0]) and int(args[1]) == _their_version \
						and int(args[2]) == _version
				_refresh()
				_check_both()
			"commit":
				if args.size() >= 2 and int(args[0]) == _their_version and int(args[1]) == _version:
					_their_commit = true
					_try_swap()
			"cancel":
				close_trade(str(args[0]).left(32) if not args.is_empty() else "CANCELLED")

	func _check_both() -> void:
		if not (_i_accept and _they_accept) or _committed:
			return
		var why := _check_ours()
		if why != "":
			cancel(why)
			return
		_committed = true                          # locked: nothing changes now
		Coop.trade_send(peer, "commit", [_version, _their_version])
		_refresh()
		_try_swap()

	## "" when our side can go through: our items still here, our credits too, room for theirs.
	func _check_ours() -> String:
		var inv := _inventory()
		var wallet := _wallet()
		if inv == null or wallet == null:
			return "NO CHARACTER"
		for i in _mine:
			if not inv.has_item(i):
				return "AN OFFERED ITEM IS GONE"
		if _credits > wallet.amount:
			return "NOT ENOUGH CREDITS"
		if _their_items.size() != _theirs.size():
			return "AN ITEM COULDN'T BE READ"
		if inv.items.size() - _mine.size() + _their_items.size() > inv.capacity:
			return "%s'S BACKPACK IS FULL" % Coop.peer_name(Coop.my_id()).to_upper()
		return ""

	func _try_swap() -> void:
		if not (_committed and _their_commit) or _done:
			return
		var inv := _inventory()
		var wallet := _wallet()
		var why := _check_ours()
		if why != "":
			close_trade("FAILED: %s" % why)          # (checked when we committed: rare)
			return
		if inv.changed.is_connected(_on_bag_changed):
			inv.changed.disconnect(_on_bag_changed)    # our own swap isn't an edit of the offer
		for i in _mine.duplicate():
			inv.remove_item(i)
		if _credits > 0:
			wallet.spend(_credits)
		for i in _their_items:
			inv.add_item(i)
		if _their_credits > 0:
			wallet.add(_their_credits)
		_done = true
		SaveManager.save_party()                   # kept, whatever happens next
		close_trade("COMPLETE")

	# ---- showing it ----
	func _refresh() -> void:
		if not visible:
			return
		var them := Coop.peer_name(peer).to_upper()
		_title.text = "TRADE  //  %s" % them
		_mine_head.text = "YOUR OFFER%s" % ("   // ACCEPTED" if _i_accept else "")
		_mine_head.add_theme_color_override("font_color", PartyMenu.COL_OK if _i_accept else PartyMenu.COL_TEXT)
		_theirs_head.text = "%s'S OFFER%s" % [them, "   // ACCEPTED" if _they_accept else ""]
		_theirs_head.add_theme_color_override("font_color", PartyMenu.COL_OK if _they_accept else PartyMenu.COL_TEXT)
		_show(_mine_grid, _mine, false)
		_show(_theirs_grid, _their_items, false)
		var inv := _inventory()
		if inv != null:
			_fit_slots(_bag_grid, inv.capacity, _on_bag_slot)
			_show(_bag_grid, inv.items, true)
			_bag_count.text = "%d / %d" % [inv.items.size(), inv.capacity]
		_their_credits_l.text = "CREDITS  %d" % _their_credits
		_credits_box.editable = not _locked()
		_accept_b.text = "ACCEPTED" if _i_accept else "ACCEPT"
		_accept_b.disabled = _locked() or _their_version < 0
		if _committed:
			_status.text = "SWAPPING..."
		elif _i_accept and not _they_accept:
			_status.text = "WAITING FOR %s" % them
		elif _they_accept and not _i_accept:
			_status.text = "%s HAS ACCEPTED" % them
		else:
			_status.text = "ANY CHANGE TAKES BACK BOTH ACCEPTS"

	## Puts `items` in `grid`'s slots, in order (the rest empty). In the backpack an offered item's
	## slot is greyed out and tagged OFFERED.
	func _show(grid: GridContainer, items: Array[ItemInstance], mark_offered: bool) -> void:
		var slots := grid.get_children()
		for i in slots.size():
			var s = slots[i]
			s.item = items[i] if i < items.size() else null
			s.disabled = mark_offered and s.item != null and s.item in _mine
			s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND \
					if s.item != null and not s.disabled and grid != _theirs_grid and not _locked() \
					else Control.CURSOR_ARROW

	func _inventory() -> InventoryComponent:
		var me := Coop.own_player(get_tree())
		return me.get("inventory") as InventoryComponent if me != null else null

	func _wallet() -> CurrencyComponent:
		var me := Coop.own_player(get_tree())
		return me.get("currency") as CurrencyComponent if me != null else null
