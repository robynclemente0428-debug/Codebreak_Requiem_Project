class_name ShopPanel
extends Control
## Opened by a ShopNPC. Left: the vendor's stock. Right: your backpack.
## Left-click selects. Right-click or double-click buys / sells. The button does the same.
## Hover an item for its card (a floating tooltip beside the slot, like the inventory's), with
## its price. Hold CTRL to compare with what you're wearing: the card adds how your stats would
## change and the item it would replace is shown next to it. With nothing hovered, CTRL shows
## the selected item.

@export var panel_width: float = 900.0
@export var panel_height: float = 660.0
@export_range(0.0, 1.0, 0.01) var bg_opacity: float = 0.92
@export var font_scale: float = 1.0
@export var font: Font
@export var accent := Color("#00E5FF")
@export var slot_size: float = 64.0
@export var columns: int = 5
@export var max_distance: float = 6.0           # walking this far from the NPC closes the shop
@export var tooltip_width: float = 360.0
var _reach := 0.0                               # opened from the NPC card: a longer leash

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
## The convoy's power junction (a DeckSystem) shuts the shops while it's down. By path: see HullBreach.
const DeckSystemScript := preload("res://scenes/map/town/convoy/deck_system.gd")
const CHAMFER := 24.0
const MIN_SHOP_CELLS := 10

const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_WARN := Color(1.0, 0.30, 0.37)
const COL_CREDIT := Color(1.0, 0.82, 0.30)

var _font: Font
var _inv: InventoryComponent
var _equip: EquipmentComponent
var _wallet: CurrencyComponent
var _shop: ShopNPC
var _player: Node3D
var _inv_panel: InventoryPanel

var _built := false
var _open := false
var _tween: Tween
var _msg_tween: Tween
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _changed_mouse_mode := false

var _selected: ItemInstance
var _hover: ItemInstance
var _hover_slot: InventoryPanel.ItemSlot

var _tip: InventoryPanel.TipFrame            # card for the hovered item
var _tip_cmp: InventoryPanel.TipFrame        # CTRL: card for the item it would replace
var _tip_anchor: Control

var _title: Label
var _greeting: Label
var _credits_label: Label
var _reroll_btn: Button
var _shop_grid: GridContainer
var _bag_grid: GridContainer
var _sel_label: Label
var _price_label: Label
var _action_btn: Button
var _msg_label: Label


func _enter_tree() -> void:
	add_to_group("shop_panel")


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
	_build_ui()
	_built = true
	visible = false
	modulate.a = 0.0


# ---------- PUBLIC ----------
func bind(inventory: InventoryComponent, equipment: EquipmentComponent, wallet: CurrencyComponent) -> void:
	if _inv and _inv.changed.is_connected(_on_data_changed):
		_inv.changed.disconnect(_on_data_changed)
	if _wallet and _wallet.changed.is_connected(_on_data_changed):
		_wallet.changed.disconnect(_on_data_changed)
	_inv = inventory
	_equip = equipment
	_wallet = wallet
	if _inv:
		_inv.changed.connect(_on_data_changed)
	if _wallet:
		_wallet.changed.connect(_on_data_changed)


func is_open() -> bool:
	return _open


## reach: how far you may be from the shopkeeper before it closes (0 = max_distance).
func open_shop(shop: ShopNPC, player: Node3D, reach: float = 0.0) -> void:
	if _open or not _built:
		return
	# On the convoy: the Null knocked out the market row's power (a DeckSystem)
	var power = DeckSystemScript.find(get_tree(), "power")
	if power != null and power.is_offline():
		QuestItems.toast(get_tree(), "NO POWER\n%s\n%s" % [power.offline_text, power.fix_hint()],
				Color(1.0, 0.35, 0.35))
		return
	_reach = reach
	if _inv == null or _wallet == null:
		push_warning("ShopPanel: not bound. Call bind(inventory, equipment, currency) from the player.")
		return
	_shop = shop
	_player = player
	shop.engage(player)                         # the shopkeeper turns to face you
	_shop.stock_changed.connect(_on_data_changed)
	_inv_panel = get_tree().get_first_node_in_group("inventory_panel") as InventoryPanel
	if _inv_panel:
		_inv_panel.close()                      # the shop shows your backpack itself
	if "input_locked" in _player:
		_player.input_locked = true

	_title.text = "// %s //" % shop.npc_name.to_upper()
	_greeting.text = shop.shop.greeting if shop.shop else ""
	_selected = null
	_hover = null

	_open = true
	var mode := Input.mouse_mode
	if mode == Input.MOUSE_MODE_CAPTURED or mode == Input.MOUSE_MODE_HIDDEN \
			or mode == Input.MOUSE_MODE_CONFINED_HIDDEN:
		_prev_mouse_mode = mode
		_changed_mouse_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	visible = true
	_fade(1.0)


func close() -> void:
	if not _open:
		return
	_open = false
	if _shop and _shop.stock_changed.is_connected(_on_data_changed):
		_shop.stock_changed.disconnect(_on_data_changed)
	if _player and is_instance_valid(_player) and "input_locked" in _player:
		_player.input_locked = false
	_shop = null
	if _changed_mouse_mode:
		Input.mouse_mode = _prev_mouse_mode
		_changed_mouse_mode = false
	_hover_slot = null
	_update_tooltip()
	_fade(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _open and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if _open and event is InputEventKey and not event.echo and event.keycode in [KEY_ALT, KEY_CTRL]:
		_update_tooltip.call_deferred()            # after the key state has changed

func _process(_delta: float) -> void:
	if _open and _shop != null and _player != null and is_instance_valid(_player):
		if _player.global_position.distance_to(_shop.global_position) > maxf(max_distance, _reach):
			close()
	if _tip != null and _tip.visible:
		_place_tips()


func _fade(target: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", target, 0.16)
	if target <= 0.0:
		_tween.finished.connect(func() -> void:
			if not _open:
				visible = false)


func _on_data_changed(_arg = null) -> void:
	if _built and _open:
		_refresh()


# ---------- BUILDING THE UI ----------
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
	title_row.add_theme_constant_override("separation", 16)
	col.add_child(title_row)
	_title = _label("// VENDOR //", 26, accent)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title)
	_credits_label = _label("", 20, COL_CREDIT)
	title_row.add_child(_credits_label)
	_reroll_btn = _button("REROLL", 16)
	_reroll_btn.custom_minimum_size = Vector2(0, 36)
	_reroll_btn.tooltip_text = "Replace the random stock with new items.\nFixed stock stays. Costs more each time."
	_reroll_btn.pressed.connect(_on_reroll)
	title_row.add_child(_reroll_btn)
	var close_btn := _button("X", 20)
	close_btn.custom_minimum_size = Vector2(44, 36)
	close_btn.pressed.connect(close)
	title_row.add_child(close_btn)

	_greeting = _label("", 14, COL_DIM)
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_greeting)
	col.add_child(_rule())

	var lists := HBoxContainer.new()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lists.add_theme_constant_override("separation", 16)
	col.add_child(lists)
	_shop_grid = _build_list(lists, "FOR SALE")
	_bag_grid = _build_list(lists, "YOUR BACKPACK")

	col.add_child(_build_detail())

	var hint := _label("RIGHT-CLICK OR DOUBLE-CLICK: BUY / SELL   |   CTRL: COMPARE   |   [ ESC ] LEAVE", 13, COL_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)

	var overlay := SkillPanel.ScanOverlay.new()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Floating item cards (top_level, so they can sit outside the panel)
	_tip = _make_tip()
	_tip_cmp = _make_tip()


func _make_tip() -> InventoryPanel.TipFrame:
	var t := InventoryPanel.TipFrame.new()
	t.accent = accent
	t.custom_minimum_size.x = tooltip_width
	add_child(t)
	return t


func _build_list(parent: Control, title: String) -> GridContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	box.add_child(_label(title, 17, COL_DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 150.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(scroll.get_v_scroll_bar())
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	return grid


## The bar under the lists: the selected item, its price and the BUY / SELL button.
## (Item details are on the floating card now.)
func _build_detail() -> PanelContainer:
	var frame := PanelContainer.new()
	var style := _flat(Color(0, 0, 0, 0.30), Color(accent, 0.35), 1)
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	frame.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	frame.add_child(row)
	_sel_label = _label("", 17, COL_DIM)
	_sel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_label.clip_text = true
	_sel_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sel_label.custom_minimum_size.x = 1.0
	_sel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_sel_label)
	_msg_label = _label("", 15, COL_WARN)
	_msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_msg_label.modulate.a = 0.0
	row.add_child(_msg_label)
	_price_label = _label("", 18, COL_CREDIT)
	_price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_price_label)
	_action_btn = _button("SELL", 20)
	_action_btn.custom_minimum_size = Vector2(150, 44)
	_action_btn.pressed.connect(_do_action)
	row.add_child(_action_btn)
	return frame


func _make_slot(kind: String) -> InventoryPanel.ItemSlot:
	var s := InventoryPanel.ItemSlot.new()
	s.kind = kind                                # "shop" or "bag"
	s.custom_minimum_size = Vector2(slot_size, slot_size)
	s.accent = accent
	s.font = _font if _font else ThemeDB.fallback_font
	s.rarity_colors = InventoryPanel.RARITY_COLORS
	s.hovered.connect(_on_slot_hovered)
	s.unhovered.connect(_on_slot_unhovered)
	s.clicked.connect(_on_slot_clicked)
	return s


# ---------- REFRESHING ----------
func _refresh() -> void:
	if _shop == null:
		return
	_hover = null                                # slots get rebuilt, so any hover is stale
	_hover_slot = null
	if _selected != null and not (_shop.stock.has(_selected) or _inv.has_item(_selected)):
		_selected = null
	_fill(_shop_grid, _shop.stock, "shop", MIN_SHOP_CELLS)
	_fill(_bag_grid, _inv.items, "bag", _inv.capacity)
	_credits_label.text = "CREDITS  %d" % _wallet.amount
	_update_reroll()
	_sync_selection()
	_update_detail()
	_update_action()


func _fill(grid: GridContainer, items: Array, kind: String, min_cells: int) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for i in maxi(items.size(), min_cells):
		var s := _make_slot(kind)
		s.item = items[i] if i < items.size() else null
		grid.add_child(s)


func _sync_selection() -> void:
	for grid in [_shop_grid, _bag_grid]:
		for s: InventoryPanel.ItemSlot in grid.get_children():
			s.selected = s.item != null and s.item == _selected


## The bottom bar shows the selected item; the card follows the mouse.
func _update_detail() -> void:
	if _selected == null:
		_sel_label.text = "HOVER AN ITEM TO INSPECT IT, CLICK TO SELECT"
		_sel_label.add_theme_color_override("font_color", COL_DIM)
		_price_label.text = ""
	else:
		_sel_label.text = _selected.get_display_name().to_upper()
		_sel_label.add_theme_color_override("font_color",
			InventoryPanel.RARITY_COLORS.get(_selected.rarity, COL_TEXT))
		_price_label.text = _price_text(_selected)
		_price_label.add_theme_color_override("font_color", _price_color(_selected))
	_update_tooltip()


func _price_text(item: ItemInstance) -> String:
	if _is_shop_item(item):
		return "PRICE  %d CR" % _shop.buy_price(item)
	return "SELLS FOR  %d CR" % _shop.sell_price(item)


func _price_color(item: ItemInstance) -> Color:
	if _is_shop_item(item) and _wallet != null and _shop.buy_price(item) > _wallet.amount:
		return COL_WARN
	return COL_CREDIT


## Shows the card for the hovered item (or, holding CTRL with nothing hovered, the selected
## one): its details, its price, and with CTRL how your stats would change plus a card for the
## item it would replace. Same cards as the inventory (InventoryPanel draws the contents).
func _update_tooltip() -> void:
	if _tip == null:
		return
	var ctrl := Input.is_key_pressed(KEY_CTRL)
	var slot: InventoryPanel.ItemSlot = null
	if _hover_slot != null and is_instance_valid(_hover_slot) and _hover_slot.item != null:
		slot = _hover_slot
	elif ctrl and _selected != null:
		slot = _slot_showing(_selected)
	if slot == null or not _open or _shop == null:
		_tip.visible = false
		_tip_cmp.visible = false
		_tip_anchor = null
		return
	var item: ItemInstance = slot.item
	_tip_anchor = slot
	_tip.clear()
	if _inv_panel != null:
		_inv_panel.fill_item_detail(_tip.box, item)
	else:
		_tip.box.add_child(_label(item.get_display_name().to_upper(), 20, COL_TEXT))
	_tip.box.add_child(_rule())
	_tip.box.add_child(_label(_price_text(item), 17, _price_color(item)))

	var comparable := _inv_panel != null and _inv_panel.can_compare(item)
	var current: ItemInstance = _inv_panel.equipped_for(item) if comparable else null
	if comparable:
		if ctrl:
			_inv_panel.add_compare_lines(_tip.box, current, item)
		else:
			_tip.box.add_child(_rule())
			var h := _label("HOLD CTRL TO COMPARE", 13, accent)
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_tip.box.add_child(h)
	_tip.visible = true

	if comparable and ctrl and current != null:
		_tip_cmp.clear()
		_tip_cmp.box.add_child(_label("CURRENTLY EQUIPPED", 13, accent))
		_inv_panel.fill_item_detail(_tip_cmp.box, current)
		_tip_cmp.visible = true
	else:
		_tip_cmp.visible = false
	_place_tips()


## The slot currently drawing `item` (shop or backpack), or null.
func _slot_showing(item: ItemInstance) -> InventoryPanel.ItemSlot:
	for grid in [_shop_grid, _bag_grid]:
		for s: InventoryPanel.ItemSlot in grid.get_children():
			if s.item == item:
				return s
	return null


## The card sits beside the slot (right, or left if it doesn't fit); the compare card next to
## it on the same side, or on the other side of the slot when there's no room. Kept on screen.
func _place_tips() -> void:
	if _tip_anchor == null or not is_instance_valid(_tip_anchor) or not _tip.visible:
		return
	var r := _tip_anchor.get_global_rect()
	var screen := get_viewport_rect().size
	var gap := 12.0
	_tip.reset_size()
	var right_side := r.end.x + gap + _tip.size.x <= screen.x - 8.0
	var pos := Vector2(r.end.x + gap if right_side else r.position.x - gap - _tip.size.x, r.position.y)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, screen.x - _tip.size.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, screen.y - _tip.size.y - 8.0))
	_tip.global_position = pos.round()
	if _tip_cmp.visible:
		_tip_cmp.reset_size()
		var p2 := Vector2(pos.x + _tip.size.x + gap if right_side else pos.x - gap - _tip_cmp.size.x, pos.y)
		if p2.x < 8.0 or p2.x + _tip_cmp.size.x > screen.x - 8.0:
			# no room past the card: the other side of the slot
			p2.x = r.position.x - gap - _tip_cmp.size.x if right_side else r.end.x + gap
		p2.x = clampf(p2.x, 8.0, maxf(8.0, screen.x - _tip_cmp.size.x - 8.0))
		p2.y = clampf(p2.y, 8.0, maxf(8.0, screen.y - _tip_cmp.size.y - 8.0))
		_tip_cmp.global_position = p2.round()


func _update_action() -> void:
	var has := _selected != null
	_action_btn.disabled = not has
	_action_btn.text = "BUY" if (has and _is_shop_item(_selected)) else "SELL"


# ---------- ACTIONS ----------
func _is_shop_item(item: ItemInstance) -> bool:
	return _shop != null and _shop.stock.has(item)


func _on_slot_hovered(slot) -> void:
	_hover = slot.item
	_hover_slot = slot
	_update_tooltip()


func _on_slot_unhovered() -> void:
	_hover = null
	_hover_slot = null
	_update_tooltip()


func _on_slot_clicked(slot, button: int, double: bool) -> void:
	_selected = slot.item                        # clicking an empty cell clears the selection
	_sync_selection()
	_update_detail()
	_update_action()
	if slot.item != null and (button == MOUSE_BUTTON_RIGHT or double):
		_do_action()


func _do_action() -> void:
	if _selected == null or _shop == null:
		return
	var err := ""
	if _is_shop_item(_selected):
		err = _shop.try_buy(_selected, _inv, _wallet)
	else:
		err = _shop.try_sell(_selected, _inv, _wallet)
	if err != "":
		_notify(err)
		return
	_selected = null                             # avoids accidental repeat actions
	_hover = null
	_hover_slot = null
	_sync_selection()
	_update_detail()
	_update_action()


func _update_reroll() -> void:
	var show := _shop != null and _shop.can_reroll()
	_reroll_btn.visible = show
	if show:
		var cost := _shop.reroll_cost()
		_reroll_btn.text = "REROLL  %d CR" % cost
		_reroll_btn.disabled = _wallet == null or _wallet.amount < cost


func _on_reroll() -> void:
	if _shop == null:
		return
	var err := _shop.try_reroll(_wallet)
	if err != "":
		_notify(err)
		return
	if _selected != null and _is_shop_item(_selected):
		_selected = null                          # the item it pointed at is gone
	_refresh()


func _notify(text: String) -> void:
	_msg_label.text = text
	_msg_label.modulate.a = 1.0
	if _msg_tween:
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_interval(1.2)
	_msg_tween.tween_property(_msg_label, "modulate:a", 0.0, 0.5)


# ---------- STYLING HELPERS ----------
# PASTE HERE: the whole "STYLING HELPERS" block from InventoryPanel,
# from _draw() down to and including _style_scrollbar().
# Use the InventoryPanel copy (not SkillPanel's), because its _button() has the disabled styling.

func _draw() -> void:
	var w := size.x
	var h := size.y
	# Chamfers on the top-right and bottom-left, mirroring the character panel on the left
	var poly := PackedVector2Array([
		Vector2(0, 0), Vector2(w - CHAMFER, 0), Vector2(w, CHAMFER),
		Vector2(w, h), Vector2(CHAMFER, h), Vector2(0, h - CHAMFER)])
	draw_colored_polygon(poly, Color(0.02, 0.05, 0.09, bg_opacity))
	var outline := PackedVector2Array(poly)
	outline.append(poly[0])
	draw_polyline(outline, Color(accent, 0.18), 7.0, true)    # glow
	draw_polyline(outline, accent, 2.0, true)


func _label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", roundi(fsize * font_scale))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, fsize: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", roundi(fsize * font_scale))
	b.add_theme_color_override("font_color", COL_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(COL_DIM, 0.35))
	b.add_theme_stylebox_override("normal", _flat(Color(accent, 0.06), Color(accent, 0.35), 1))
	b.add_theme_stylebox_override("hover", _flat(Color(accent, 0.16), Color(accent, 0.8), 1))
	b.add_theme_stylebox_override("pressed", _flat(Color(accent, 0.28), accent, 2))
	b.add_theme_stylebox_override("hover_pressed", _flat(Color(accent, 0.28), accent, 2))
	b.add_theme_stylebox_override("disabled", _flat(Color(accent, 0.02), Color(accent, 0.12), 1))
	return b


func _flat(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(accent, 0.5)
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _style_scrollbar(bar: ScrollBar) -> void:
	bar.custom_minimum_size = Vector2(8, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(accent, 0.08)
	bar.add_theme_stylebox_override("scroll", track)
	for entry in [["grabber", 0.55], ["grabber_highlight", 0.85], ["grabber_pressed", 1.0]]:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(accent, entry[1])
		bar.add_theme_stylebox_override(entry[0], g)
