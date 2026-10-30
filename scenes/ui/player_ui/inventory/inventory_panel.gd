class_name InventoryPanel
extends Control
## Retro-futuristic inventory. Press I to slide it open from the right.
## It builds its whole UI in code (same approach as CharacterPanel), so there is nothing to set
## up in the scene tree: add a plain Control, attach this script, and call bind() from the player.
##
## Hover an item to see its card (a floating tooltip beside the slot), left-click to select,
## right-click or double-click to equip / unequip. The buttons at the bottom act on the
## selected item. Hold CTRL to compare: the card adds how your stats would change, and the
## item it would replace is shown next to it. With nothing hovered, CTRL shows the selected item.

@export var toggle_key: Key = KEY_I
@export var panel_width: float = 620.0
@export_range(0.0, 1.0, 0.01) var bg_opacity: float = 0.88
@export var font_scale: float = 1.0
@export var font: Font                          # leave empty to use the Courier Prime font below
@export var accent := Color("#00E5FF")
@export var slot_size: float = 80.0
@export var columns: int = 6
@export var tooltip_width: float = 360.0

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const OPEN_X := 32.0
const CLOSED_GAP := 20.0
const CHAMFER := 24.0
const DEFAULT_CAPACITY := 30

const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_WARN := Color(1.0, 0.30, 0.37)
const COL_AFFIX := Color(0.45, 0.75, 1.0)
const COL_BETTER := Color(0.40, 1.0, 0.55)
const COL_WORSE := Color(1.0, 0.38, 0.38)
## Stats where going down is the good direction (shown green when they drop).
const LOWER_IS_BETTER := [StatTypes.Stat.MANA_COST]

const RARITY_COLORS := {
	"normal": Color(0.85, 0.96, 1.0),
	"magic": Color(0.30, 0.64, 1.0),
	"rare": Color(1.0, 0.82, 0.30),
	"skill_gem": GemText.COL_SKILL,
	"support_gem": GemText.COL_SUPPORT,
}

signal open_changed(is_open: bool)

## The equipment row, left to right. glyph is shown inside an empty slot.
const EQUIP_SLOTS := [
	{"slot": EquipmentSlots.Slot.WEAPON, "label": "WEAPON", "glyph": "WPN", "kind": "sword"},
	{"slot": EquipmentSlots.Slot.OFF_HAND, "label": "OFF HAND", "glyph": "OFF", "kind": "shield"},
	{"slot": EquipmentSlots.Slot.HEAD, "label": "HEAD", "glyph": "HED", "kind": "helmet"},
	{"slot": EquipmentSlots.Slot.BODY, "label": "BODY", "glyph": "BDY", "kind": "body"},
	{"slot": EquipmentSlots.Slot.HANDS, "label": "HANDS", "glyph": "HND", "kind": "hands"},
	{"slot": EquipmentSlots.Slot.FEET, "label": "FEET", "glyph": "FT", "kind": "boots"},
]
## Stim (potion) slots, a second row under the gear. The label shows the hotkey.
const STIM_ROW := [
	{"slot": EquipmentSlots.Slot.STIM_1, "action": &"stim_1", "glyph": "", "kind": "stim"},
	{"slot": EquipmentSlots.Slot.STIM_2, "action": &"stim_2", "glyph": "", "kind": "stim"},
]

## Display names for stats in item text. Anything missing falls back to the enum name.
const STAT_LABELS := {
	StatTypes.Stat.MAX_HEALTH: "Maximum Life",
	StatTypes.Stat.ARMOUR: "Armour",
	StatTypes.Stat.MOVE_SPEED: "Movement Speed",
	StatTypes.Stat.MIN_ATTACK_DAMAGE: "Attack Damage",
	StatTypes.Stat.MAX_ATTACK_DAMAGE: "Attack Damage",
	StatTypes.Stat.ATTACK_SPEED: "Attack Speed",
	StatTypes.Stat.CRIT_CHANCE: "Critical Strike Chance",
	StatTypes.Stat.CRIT_MULTIPLIER: "Critical Strike Multiplier",
	StatTypes.Stat.LIFE_ON_HIT: "Life on Hit",
	StatTypes.Stat.MANA: "Maximum Mana",
	StatTypes.Stat.SKILL_DAMAGE_MULT: "Skill Damage",
	StatTypes.Stat.STRENGTH: "Strength",
	StatTypes.Stat.DEXTERITY: "Dexterity",
	StatTypes.Stat.INTELLIGENCE: "Intelligence",
	StatTypes.Stat.REGENERATION: "Life Regeneration",
}

var _font: Font
var _inv: InventoryComponent
var _equip: EquipmentComponent

var _built := false
var _open := false
var _tween: Tween
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _changed_mouse_mode := false
var _suppress_refresh := false

var _selected: ItemInstance
var _hover_slot: ItemSlot                    # the slot under the mouse (its item can change)
var _tip: TipFrame                           # card for the hovered item
var _tip_cmp: TipFrame                       # CTRL: card for the item it would replace
var _tip_anchor: ItemSlot                    # the slot the cards sit next to

var _eq_slots: Dictionary = {}              # slot id -> ItemSlot
var _grid_slots: Array[ItemSlot] = []
var _grid: GridContainer
var _count_label: Label
var _equip_btn: Button
var _discard_btn: Button
var _msg_label: Label
var _msg_tween: Tween

var _credit_label: Label
var _wallet: CurrencyComponent

# Joined in _enter_tree so the player can find the panel even if it readies first
func _enter_tree() -> void:
	add_to_group("inventory_panel")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_layout()
	_build_ui()
	_built = true
	visible = false
	_apply_bound_data()


func _layout() -> void:
	# Docked to the right edge, full height with a margin
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_top = 32.0
	offset_bottom = -32.0
	_set_offsets(false)


func _set_offsets(opened: bool) -> void:
	offset_left = -(OPEN_X + panel_width) if opened else CLOSED_GAP
	offset_right = -OPEN_X if opened else CLOSED_GAP + panel_width


# ---------- PUBLIC ----------
func bind(inventory: InventoryComponent, equipment: EquipmentComponent) -> void:
	if _inv and _inv.changed.is_connected(_on_data_changed):
		_inv.changed.disconnect(_on_data_changed)
	if _equip and _equip.equipment_changed.is_connected(_on_data_changed):
		_equip.equipment_changed.disconnect(_on_data_changed)
	_inv = inventory
	_equip = equipment
	if _inv:
		_inv.changed.connect(_on_data_changed)
	if _equip:
		_equip.equipment_changed.connect(_on_data_changed)
	if _built:
		_apply_bound_data()


func toggle() -> void:
	if _open:
		close()
	else:
		open()

func is_open() -> bool:
	return _open

func open() -> void:
	if _open or not _built:
		return
	_open = true
	open_changed.emit(true)
	GameEvents.report("open_panel", "inventory")
	# A captured or hidden cursor can't click UI, so show it while the panel is open
	var mode := Input.mouse_mode
	if mode == Input.MOUSE_MODE_CAPTURED or mode == Input.MOUSE_MODE_HIDDEN \
			or mode == Input.MOUSE_MODE_CONFINED_HIDDEN:
		_prev_mouse_mode = mode
		_changed_mouse_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _inv == null or _equip == null:
		push_warning("InventoryPanel: not bound. Is bind() being called from the player?")
	_refresh()
	if not visible:
		_set_offsets(false)
		modulate.a = 0.0
		visible = true
	_play_slide(true)


func close() -> void:
	if not _open:
		return
	_open = false
	open_changed.emit(false)
	_hover_slot = null
	_update_tooltip()
	if _changed_mouse_mode:
		Input.mouse_mode = _prev_mouse_mode
		_changed_mouse_mode = false
	_play_slide(false)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == toggle_key:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _open:
		close()
		get_viewport().set_input_as_handled()


func _play_slide(opening: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	var left := -(OPEN_X + panel_width) if opening else CLOSED_GAP
	var right := -OPEN_X if opening else CLOSED_GAP + panel_width
	_tween.tween_property(self, "offset_left", left, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "offset_right", right, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0 if opening else 0.0, 0.18)
	if not opening:
		_tween.finished.connect(_on_slide_finished)


func _on_slide_finished() -> void:
	if not _open:
		visible = false


func _on_data_changed() -> void:
	if _built and not _suppress_refresh:
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
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	# Title bar
	var title_row := HBoxContainer.new()
	col.add_child(title_row)
	var title := _label("// INVENTORY //", 26, accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	
	var close_btn := _button("X", 20)
	close_btn.custom_minimum_size = Vector2(44, 36)
	close_btn.pressed.connect(close)
	title_row.add_child(close_btn)
	
	col.add_child(_rule())

	# Equipped items
	col.add_child(_label("EQUIPPED", 17, COL_DIM))
	col.add_child(_build_equipment_row())
	col.add_child(_build_stim_row())
	col.add_child(_rule())

	# Backpack header
	var bag_head := HBoxContainer.new()
	bag_head.add_theme_constant_override("separation", 12)
	col.add_child(bag_head)
	var bag_title := _label("BACKPACK", 17, COL_DIM)
	bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_head.add_child(bag_title)
	_count_label = _label("", 17, accent)
	bag_head.add_child(_count_label)
	
	var credit_spacer := Control.new()
	credit_spacer.custom_minimum_size.x = 20
	bag_head.add_child(credit_spacer)
	
	_credit_label = _label("", 17, Color(1.0, 0.82, 0.30))
	bag_head.add_child(_credit_label)
	
	var sort_btn := _button("SORT", 15)
	sort_btn.pressed.connect(_on_sort_pressed)
	bag_head.add_child(sort_btn)

	# Backpack grid
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 120.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(scroll.get_v_scroll_bar())
	col.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	_rebuild_grid(DEFAULT_CAPACITY)

	# Equip / discard buttons (the item card is a floating tooltip now)
	col.add_child(_build_actions())

	var hint := _label("[ %s ] CLOSE  |  RIGHT-CLICK: EQUIP / UNEQUIP  |  CTRL: COMPARE" \
		% OS.get_keycode_string(toggle_key), 13, COL_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(hint)

	# Scanlines go on top of everything
	var overlay := ScanOverlay.new()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Floating item cards (top_level, so they can sit outside the panel)
	_tip = _make_tip()
	_tip_cmp = _make_tip()


func _make_tip() -> TipFrame:
	var t := TipFrame.new()
	t.accent = accent
	t.custom_minimum_size.x = tooltip_width
	add_child(t)
	return t

func bind_currency(wallet: CurrencyComponent) -> void:
	_wallet = wallet
	wallet.changed.connect(func(_a: int) -> void: _refresh_credits())
	_refresh_credits()

func _refresh_credits() -> void:
	if _credit_label and _wallet:
		_credit_label.text = "%d CR" % _wallet.amount

func _build_equipment_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for def in EQUIP_SLOTS:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var s := _make_slot()
		s.kind = "equip"
		s.slot_id = def["slot"]
		s.placeholder = def["glyph"]
		s.placeholder_kind = def["kind"]
		cell.add_child(s)
		var lbl := _label(def["label"], 12, COL_DIM)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(lbl)
		row.add_child(cell)
		_eq_slots[def["slot"]] = s
	return row


## Stim (potion) slots under the gear: smaller cells, each labelled with its hotkey.
func _build_stim_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var title := _label("STIMS", 15, COL_DIM)
	title.custom_minimum_size.x = 70
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	for def in STIM_ROW:
		var s := _make_slot()
		s.kind = "equip"
		s.slot_id = def["slot"]
		s.placeholder_kind = def["kind"]
		s.custom_minimum_size = Vector2(slot_size * 0.7, slot_size * 0.7)
		row.add_child(s)
		var key := _label("[%s]" % GemText.key_label(def["action"]), 14, accent)
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(key)
		var gap := Control.new()
		gap.custom_minimum_size.x = 14
		row.add_child(gap)
		_eq_slots[def["slot"]] = s
	var hint := _label("REFILL FROM KILLS, FULL IN TOWN", 12, Color(COL_DIM, 0.7))
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)
	return row


func _build_actions() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_equip_btn = _button("EQUIP", 18)
	_equip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_btn.custom_minimum_size.y = 40
	_equip_btn.pressed.connect(_primary_action)
	buttons.add_child(_equip_btn)
	_discard_btn = _button("DISCARD", 18)
	_discard_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_discard_btn.custom_minimum_size.y = 40
	_discard_btn.pressed.connect(_discard_selected)
	buttons.add_child(_discard_btn)

	_msg_label = _label("", 15, COL_WARN)
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.modulate.a = 0.0
	box.add_child(_msg_label)
	return box


func _make_slot() -> ItemSlot:
	var s := ItemSlot.new()
	s.custom_minimum_size = Vector2(slot_size, slot_size)
	s.accent = accent
	s.font = _font if _font else ThemeDB.fallback_font
	s.rarity_colors = RARITY_COLORS
	s.hovered.connect(_on_slot_hovered)
	s.unhovered.connect(_on_slot_unhovered)
	s.clicked.connect(_on_slot_clicked)
	return s


func _rebuild_grid(count: int) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_grid_slots.clear()
	for i in count:
		var s := _make_slot()
		s.kind = "bag"
		_grid.add_child(s)
		_grid_slots.append(s)


# ---------- REFRESHING ----------
func _apply_bound_data() -> void:
	var cap := _inv.capacity if _inv else DEFAULT_CAPACITY
	if cap != _grid_slots.size():
		_rebuild_grid(cap)
	_refresh()


func _refresh() -> void:
	if not _built:
		return
	if _selected != null and not _owns(_selected):
		_selected = null

	for def in EQUIP_SLOTS + STIM_ROW:
		var s: ItemSlot = _eq_slots[def["slot"]]
		s.item = _equip.get_equipped(def["slot"]) if _equip else null

	var items: Array[ItemInstance] = []
	if _inv:
		items = _inv.items
	for i in _grid_slots.size():
		_grid_slots[i].item = items[i] if i < items.size() else null
	_count_label.text = "%d / %d" % [items.size(), _grid_slots.size()]

	_sync_selection()
	_update_tooltip()
	_update_buttons()
	_refresh_credits()


func _sync_selection() -> void:
	for s in _grid_slots:
		s.selected = s.item != null and s.item == _selected
	for slot_id in _eq_slots:
		var s: ItemSlot = _eq_slots[slot_id]
		s.selected = s.item != null and s.item == _selected


func _update_buttons() -> void:
	var has := _selected != null
	_equip_btn.disabled = not has
	_equip_btn.text = "UNEQUIP" if (has and _is_equipped(_selected)) else "EQUIP"
	_discard_btn.disabled = not (has and _inv != null and _inv.has_item(_selected))

# ---------- ITEM CARDS (TOOLTIPS) ----------
## Shows the card for the hovered item (or, holding CTRL with nothing hovered, the selected
## one). Holding CTRL adds how your stats would change and shows the item it would replace.
func _update_tooltip() -> void:
	if _tip == null:
		return
	var ctrl := Input.is_key_pressed(KEY_CTRL)
	var slot: ItemSlot = null
	if _hover_slot != null and is_instance_valid(_hover_slot) and _hover_slot.item != null:
		slot = _hover_slot
	elif ctrl and _selected != null:
		slot = _slot_showing(_selected)
	if slot == null or not _open:
		_tip.visible = false
		_tip_cmp.visible = false
		_tip_anchor = null
		return
	var item := slot.item
	_tip_anchor = slot
	_tip.clear()
	fill_item_detail(_tip.box, item)

	var comparable := _can_compare(item)
	var current: ItemInstance = null
	if comparable:
		var target: int = _equip.slot_for(item)
		current = _equip.get_equipped(target) if target >= 0 else null
		if ctrl:
			_add_compare_lines(_tip.box, current, item)
		else:
			_tip.box.add_child(_rule())
			var h := _label("HOLD CTRL TO COMPARE", 13, accent)
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_tip.box.add_child(h)
	_tip.visible = true

	if comparable and ctrl and current != null:
		_tip_cmp.clear()
		var head := _label("CURRENTLY EQUIPPED", 13, accent)
		_tip_cmp.box.add_child(head)
		fill_item_detail(_tip_cmp.box, current)
		_tip_cmp.visible = true
	else:
		_tip_cmp.visible = false
	_place_tips()


## For ShopPanel's cards: same compare rules and lines as the inventory.
func can_compare(item: ItemInstance) -> bool:
	return _can_compare(item)


## The item `item` would replace (null = that slot is empty, or it can't be worn).
func equipped_for(item: ItemInstance) -> ItemInstance:
	if _equip == null or item == null:
		return null
	var target: int = _equip.slot_for(item)
	return _equip.get_equipped(target) if target >= 0 else null


func add_compare_lines(box: VBoxContainer, current: ItemInstance, item: ItemInstance) -> void:
	_add_compare_lines(box, current, item)


## Gear that isn't worn yet. Gems and stims don't change your stats, so there's nothing to compare.
func _can_compare(item: ItemInstance) -> bool:
	return _equip != null and item != null and not _is_equipped(item) \
		and not item.definition.is_gem() and not item.definition.is_stim() \
		and _equip.slot_for(item) >= 0


## "IF EQUIPPED": every stat that would change, green for better and red for worse.
func _add_compare_lines(box: VBoxContainer, current: ItemInstance, item: ItemInstance) -> void:
	box.add_child(_rule())
	box.add_child(_label("IF EQUIPPED" if current == null else "IF SWAPPED", 14, accent))
	if not _equip.can_equip(item):
		var why := _label(_equip.last_block_reason.to_upper(), 13, COL_WARN)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(why)
	var changes := stat_changes(current, item)
	if changes.is_empty():
		box.add_child(_label("NO STAT CHANGES", 14, COL_DIM))
		return
	for c in changes:
		var stat: int = c[0]
		var d: float = c[1]
		var better := (d > 0.0) != (stat in LOWER_IS_BETTER)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_l := _label(_compare_label(stat), 15, COL_TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(_label(_delta_text(stat, d), 15, COL_BETTER if better else COL_WORSE))
		box.add_child(row)


## How each of your final stats changes if `item` replaces `current` (null = empty slot).
## Works on throw-away copies of your stats, so nothing on the character is touched.
## Attributes are re-applied on both copies, so +Strength also shows its extra life, etc.
## Returns [[stat, change], ...] for the stats that change.
func stat_changes(current: ItemInstance, item: ItemInstance) -> Array:
	var src: StatComponent = _equip.stat_component if _equip else null
	if src == null:
		return []
	var before := _stat_copy(src)
	var after := _stat_copy(src)
	if current != null:
		after.remove_by_source_prefix("item_%s_" % current.definition.id)
	for m in item.build_modifiers():
		after.add_modifier(m)
	AttributeEffects.apply(before)
	AttributeEffects.apply(after)
	var out: Array = []
	for stat in StatTypes.Stat.values():
		var d := after.get_stat(stat) - before.get_stat(stat)
		if absf(d) > 0.0005:
			out.append([stat, d])
	before.free()
	after.free()
	return out


func _stat_copy(src: StatComponent) -> StatComponent:
	var c := StatComponent.new()
	c.base_stats = src.base_stats.duplicate()
	for m in src._modifiers:
		c.add_modifier(m)
	return c


func _compare_label(stat: int) -> String:
	match stat:
		StatTypes.Stat.MIN_ATTACK_DAMAGE:
			return "Min Attack Damage"
		StatTypes.Stat.MAX_ATTACK_DAMAGE:
			return "Max Attack Damage"
	return _stat_label(stat)


func _delta_text(stat: int, d: float) -> String:
	match stat:
		StatTypes.Stat.CRIT_CHANCE, StatTypes.Stat.SKILL_DAMAGE_MULT:
			return "%+.1f%%" % (d * 100.0)
		StatTypes.Stat.CRIT_MULTIPLIER, StatTypes.Stat.ATTACK_SPEED:
			return "%+.2f" % d
		StatTypes.Stat.MOVE_SPEED, StatTypes.Stat.LIFE_ON_HIT, StatTypes.Stat.REGENERATION, \
		StatTypes.Stat.MANA_REGEN, StatTypes.Stat.ATTACK_RANGE:
			return "%+.1f" % d
	if absf(d - roundf(d)) < 0.05:
		return "%+d" % roundi(d)
	return "%+.1f" % d


## The slot currently drawing `item` (backpack or equipment), or null.
func _slot_showing(item: ItemInstance) -> ItemSlot:
	for s in _grid_slots:
		if s.item == item:
			return s
	for slot_id in _eq_slots:
		if _eq_slots[slot_id].item == item:
			return _eq_slots[slot_id]
	return null


## Cards sit to the left of the slot (the panel is docked on the right), the compare card
## further left, both kept on screen.
func _place_tips() -> void:
	if _tip_anchor == null or not is_instance_valid(_tip_anchor) or not _tip.visible:
		return
	var r := _tip_anchor.get_global_rect()
	var screen := get_viewport_rect().size
	var gap := 12.0
	_tip.reset_size()
	var left := minf(get_global_rect().position.x, r.position.x)   # outside the panel's frame
	var pos := Vector2(left - _tip.size.x - gap, r.position.y)
	if pos.x < 8.0:
		pos.x = r.end.x + gap
	pos.y = clampf(pos.y, 8.0, maxf(8.0, screen.y - _tip.size.y - 8.0))
	_tip.global_position = pos.round()
	if _tip_cmp.visible:
		_tip_cmp.reset_size()
		var p2 := Vector2(pos.x - _tip_cmp.size.x - gap, pos.y)
		if p2.x < 8.0:
			p2.x = pos.x + _tip.size.x + gap
		p2.y = clampf(p2.y, 8.0, maxf(8.0, screen.y - _tip_cmp.size.y - 8.0))
		_tip_cmp.global_position = p2.round()


func _process(_delta: float) -> void:
	if _tip != null and _tip.visible:
		_place_tips()                              # follows the slot while the panel slides

## Fills `box` with an item's name, type, base stats and affixes. ShopPanel reuses this.
func fill_item_detail(box: VBoxContainer, item: ItemInstance) -> void:
	var def := item.definition
	var rarity_col: Color = RARITY_COLORS.get(item.rarity, COL_TEXT)

	var name_l := _label(item.get_display_name().to_upper(), 22, rarity_col)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(name_l)
	box.add_child(_label("%s  //  %s" % [_type_name(def), item.rarity.to_upper()], 14, COL_DIM))
	if Input.is_key_pressed(KEY_ALT):
		box.add_child(_label("ITEM LEVEL  %d" % item.item_level, 14, accent))
	var desc: String = def.get_description()
	if desc != "":
		var d := _label(desc, 14, COL_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(d)
	if _is_equipped(item):
		box.add_child(_label("[ EQUIPPED ]", 14, accent))
	else:
		var slot: int = _equip.slot_for(item) if _equip else def.get_slot()
		var current: ItemInstance = _equip.get_equipped(slot) if (_equip and slot >= 0) else null
		if current != null:
			box.add_child(_label("REPLACES  " + current.get_display_name().to_upper(), 13, COL_DIM))

	if def.stim != null:
		box.add_child(_rule())
		for entry in StimRoller.lines(item):
			var sl := _label(entry[0], 16 if entry[1] else 17, COL_AFFIX if entry[1] else COL_TEXT)
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.add_child(sl)
		return
	var base_lines := _base_lines(def.base_stats)
	if not base_lines.is_empty() or not item.rolled_affixes.is_empty():
		box.add_child(_rule())
	for text in base_lines:
		box.add_child(_label(text, 17, COL_TEXT))
	if not base_lines.is_empty() and not item.rolled_affixes.is_empty():
		box.add_child(_rule())
	var show_ids := Input.is_key_pressed(KEY_ALT)
	for entry in item.rolled_affixes:
		var text := _affix_text(entry)
		if show_ids:
			var a: AffixDefinition = entry["affix"]
			text += "  [%s]" % a.id
		var l := _label(text, 16, COL_AFFIX)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(l)

func _input(event: InputEvent) -> void:
	if _open and event is InputEventKey and not event.echo \
			and event.keycode in [KEY_ALT, KEY_CTRL]:
		_update_tooltip.call_deferred()            # after the key state has changed

# ---------- ITEM TEXT ----------
func _type_name(def: ItemDefinition) -> String:
	if def.weapon_type != null:
		return def.weapon_type.display_name.to_upper()
	if def.equipment_type != null:
		return def.equipment_type.display_name.to_upper()
	if def.skill_gem != null:
		return "SKILL GEM"
	if def.support_gem != null:
		return "SUPPORT GEM"
	if def.stim != null:
		return "HEALTH STIM" if def.stim.kind == StimDefinition.Kind.HEALTH else "MANA STIM"
	return "ITEM"


func _stat_label(stat: int) -> String:
	if STAT_LABELS.has(stat):
		return STAT_LABELS[stat]
	return str(StatTypes.Stat.find_key(stat)).capitalize()


## Shows min and max attack damage together as one "10 - 20" line.
func _base_lines(base: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var mn: int = StatTypes.Stat.MIN_ATTACK_DAMAGE
	var mx: int = StatTypes.Stat.MAX_ATTACK_DAMAGE
	var paired := base.has(mn) and base.has(mx)
	if paired:
		out.append("Attack Damage  %d - %d" % [roundi(base[mn]), roundi(base[mx])])
	for stat in base.keys():
		if paired and (stat == mn or stat == mx):
			continue
		out.append("%s  %s" % [_stat_label(stat), _flat_text(stat, base[stat])])
	return out


func _flat_text(stat: int, v: float) -> String:
	match stat:
		StatTypes.Stat.CRIT_CHANCE, StatTypes.Stat.SKILL_DAMAGE_MULT:
			return "%+.1f%%" % (v * 100.0)
		StatTypes.Stat.CRIT_MULTIPLIER:
			return "%+.2f" % v
		StatTypes.Stat.ATTACK_SPEED, StatTypes.Stat.MOVE_SPEED, \
		StatTypes.Stat.LIFE_ON_HIT, StatTypes.Stat.REGENERATION:
			return "%+.1f" % v
	return "%+d" % roundi(v)


func _pct(v: float) -> String:
	return ("%.1f" % (v * 100.0)).trim_suffix(".0")


func _range_name(a: AffixDefinition) -> String:
	var n1 := _stat_label(a.min_stat)
	var n2 := _stat_label(a.max_stat)
	return n1 if n1 == n2 else "%s and %s" % [n1, n2]


func _affix_text(entry: Dictionary) -> String:
	var a: AffixDefinition = entry["affix"]
	var v: float = float(entry.get("rolled_value", 0.0))
	match a.shape:
		AffixDefinition.AffixShape.DAMAGE_RANGE:
			return "Adds %d - %d %s" % [roundi(entry["rolled_min"]), roundi(entry["rolled_max"]), _range_name(a)]
		AffixDefinition.AffixShape.PERCENT_RANGE:
			return "%s%% %s %s" % [_pct(absf(v)), "increased" if v >= 0.0 else "reduced", _range_name(a)]
		AffixDefinition.AffixShape.PERCENT_MULT_RANGE:
			return "%s%% %s %s" % [_pct(absf(v)), "more" if v >= 0.0 else "less", _range_name(a)]
	var label := _stat_label(a.stat)
	match a.op:
		Modifier.ModOp.FLAT_ADD:
			return "%s %s" % [_flat_text(a.stat, v), label]
		Modifier.ModOp.PERCENT_ADD:
			return "%s%% %s %s" % [_pct(absf(v)), "increased" if v >= 0.0 else "reduced", label]
		Modifier.ModOp.PERCENT_MULT:
			return "%s%% %s %s" % [_pct(absf(v)), "more" if v >= 0.0 else "less", label]
	return "%s: %s" % [label, str(v)]


# ---------- ACTIONS ----------
func _on_slot_hovered(slot: ItemSlot) -> void:
	_hover_slot = slot
	_update_tooltip()


func _on_slot_unhovered() -> void:
	_hover_slot = null
	_update_tooltip()


# ---------- TUTORIAL ----------
## Controls the tutorial hints (autoload/tutorial_hints.gd) can outline. Empty while closed.
func tutorial_target(id: String) -> Array[Control]:
	var out: Array[Control] = []
	if not _open or not _built:
		return out
	match id:
		"weapon_item":
			for s in _grid_slots:
				if s.item != null and s.item.definition.weapon_type != null:
					out.append(s)
					break
		"skill_gem_item":
			for s in _grid_slots:
				if s.item != null and s.item.definition.skill_gem != null:
					out.append(s)
					break
		"weapon_slot":
			if _eq_slots.has(EquipmentSlots.Slot.WEAPON):
				out.append(_eq_slots[EquipmentSlots.Slot.WEAPON])
	return out


func _on_slot_clicked(slot: ItemSlot, button: int, double: bool) -> void:
	_selected = slot.item                       # clicking an empty slot clears the selection
	_sync_selection()
	_update_buttons()
	_update_tooltip()
	if slot.item != null and (button == MOUSE_BUTTON_RIGHT or double):
		_primary_action()


func _primary_action() -> void:
	if _selected == null or _inv == null or _equip == null:
		return
	if _is_equipped(_selected):
		_unequip_selected()
	else:
		_equip_selected()


func _equip_selected() -> void:
	var item := _selected
	if item.definition.is_gem():
		var panel := get_tree().get_first_node_in_group("skill_panel") as SkillPanel
		if panel == null:
			_notify("SKILLS MENU NOT FOUND")
			return
		var error: String = panel.quick_socket(item)
		if error != "":
			_notify(error)
		return
	var slot: int = _equip.slot_for(item)
	if slot < 0:
		_notify("CANNOT EQUIP THIS ITEM")
		return
	var previous: ItemInstance = _equip.get_equipped(slot)

	# Remove from the backpack first so the swapped-out item always has room.
	# Refresh is held back until the end so the selection isn't cleared mid-swap.
	_suppress_refresh = true
	_inv.remove_item(item)
	var ok: bool = _equip.equip(item, slot)
	if ok:
		if previous != null:
			_inv.add_item(previous)
	else:
		_inv.add_item(item)
		_notify("CANNOT EQUIP THIS ITEM")
	_suppress_refresh = false
	_refresh()


func _unequip_selected() -> void:
	if _inv.is_full():
		_notify("BACKPACK FULL")
		return
	var item := _selected
	var slot := _slot_of(item)
	if slot < 0:
		return
	_suppress_refresh = true
	_equip.unequip(slot)
	_inv.add_item(item)
	_suppress_refresh = false
	_refresh()


## Deletes the item permanently. There is no confirmation.
func _discard_selected() -> void:
	if _selected == null or _inv == null or not _inv.has_item(_selected):
		return
	var item := _selected
	_selected = null
	_inv.remove_item(item)
	_refresh()


func _on_sort_pressed() -> void:
	if _inv:
		_inv.sort_items()


func _is_equipped(item: ItemInstance) -> bool:
	return _equip != null and item != null and _equip.equipped.values().has(item)


func _slot_of(item: ItemInstance) -> int:
	if _equip == null:
		return -1
	for slot in _equip.equipped:
		if _equip.equipped[slot] == item:
			return slot
	return -1


func _owns(item: ItemInstance) -> bool:
	return (_inv != null and _inv.has_item(item)) or _is_equipped(item)


func _notify(text: String) -> void:
	_msg_label.text = text
	_msg_label.modulate.a = 1.0
	if _msg_tween:
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_interval(1.0)
	_msg_tween.tween_property(_msg_label, "modulate:a", 0.0, 0.5)


# ---------- STYLING HELPERS ----------
# (Same look as CharacterPanel. These could move into one shared script later.)
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


# ---------- SMALL DRAWN WIDGETS ----------
## One square item cell. Draws a chamfered box in the item's rarity colour, plus the
## item's icon, or its initials if the item has no icon yet.
class ItemSlot extends Control:
	signal hovered(slot)
	signal unhovered
	signal clicked(slot, button, double)

	var item: ItemInstance:
		set(value):
			item = value
			queue_redraw()
	var selected := false:
		set(value):
			selected = value
			queue_redraw()
	var kind := "bag"               # "bag" or "equip"
	var slot_id := -1               # equipment slots only
	var placeholder := ""           # text shown inside an empty equipment slot
	var placeholder_kind := ""      # glyph shown, dimmed, inside an empty equipment slot
	var accent := Color.WHITE
	var font: Font
	var rarity_colors := {}
	var _hover := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw()
			hovered.emit(self))
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw()
			unhovered.emit())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
				clicked.emit(self, event.button_index, event.double_click)
				accept_event()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := 10.0
		var poly := PackedVector2Array([
			Vector2(0, 0), Vector2(w - c, 0), Vector2(w, c),
			Vector2(w, h), Vector2(c, h), Vector2(0, h - c)])
		var col := accent
		if item != null:
			col = rarity_colors.get(item.rarity, accent)
		draw_colored_polygon(poly, Color(col, 0.16 if item != null else 0.05))

		var outline := PackedVector2Array(poly)
		outline.append(poly[0])
		var line_alpha := 0.9 if item != null else 0.25
		if _hover or selected:
			draw_polyline(outline, Color(col, 0.25), 7.0, true)    # glow
			line_alpha = 1.0
		draw_polyline(outline, Color(col, line_alpha), 3.0 if selected else 2.0, true)

		if item != null:
			var def := item.definition
			var icon: Texture2D = def.icon
			if icon != null:
				draw_texture_rect(icon, Rect2(8, 8, w - 16, h - 16), false)
			else:
				var drawn := false
				var kind := ItemGlyph.kind_for(def)
				if kind != "":
					drawn = ItemGlyph.draw(self, kind, Rect2(10, 8, w - 20, h - 28), col)
				if not drawn:
					var initials := def.display_name.left(3).to_upper() if def.is_gem() else _initials(def.display_name)
					draw_string(font, Vector2(0, h * 0.5 + 9.0), initials,
						HORIZONTAL_ALIGNMENT_CENTER, w, 22 if def.is_gem() else 26, col)
			var tag := ItemGlyph.type_tag(def)
			if tag != "":
				draw_string(font, Vector2(0, h - 7.0), tag, HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color(col, 0.8))
		elif placeholder_kind != "":
			ItemGlyph.draw(self, placeholder_kind, Rect2(10, 8, w - 20, h - 28), Color(accent, 0.3))
		elif placeholder != "":
			draw_string(font, Vector2(0, h * 0.5 + 6.0), placeholder,
				HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color(accent, 0.35))

	func _initials(text: String) -> String:
		var out := ""
		for word in text.split(" ", false):
			out += word.substr(0, 1).to_upper()
			if out.length() >= 2:
				break
		return out


## A floating item card: same chamfered frame as the panel. top_level, so it isn't clipped
## by the panel and can sit beside it. Ignores the mouse so it never blocks a click.
class TipFrame extends PanelContainer:
	const CHAMFER := 16.0
	var accent := Color.WHITE
	var bg_opacity := 0.95
	var box: VBoxContainer

	func _init() -> void:
		top_level = true
		z_index = 20
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pad := StyleBoxEmpty.new()
		pad.content_margin_left = 18
		pad.content_margin_right = 18
		pad.content_margin_top = 14
		pad.content_margin_bottom = 14
		add_theme_stylebox_override("panel", pad)
		box = VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 3)
		add_child(box)

	func clear() -> void:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
		size = Vector2.ZERO                         # shrink to the new content

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var poly := PackedVector2Array([
			Vector2(0, 0), Vector2(w - CHAMFER, 0), Vector2(w, CHAMFER),
			Vector2(w, h), Vector2(CHAMFER, h), Vector2(0, h - CHAMFER)])
		draw_colored_polygon(poly, Color(0.02, 0.05, 0.09, bg_opacity))
		var outline := PackedVector2Array(poly)
		outline.append(poly[0])
		draw_polyline(outline, Color(accent, 0.18), 7.0, true)
		draw_polyline(outline, accent, 2.0, true)


## CRT scanlines and a slow sweep drawn over the whole panel.
class ScanOverlay extends Control:
	var t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			t += delta
			queue_redraw()

	func _draw() -> void:
		var inset := 24.0
		var y := 2.0
		while y < size.y - 2.0:
			draw_line(Vector2(inset, y), Vector2(size.x - inset, y), Color(0, 0, 0, 0.13), 1.0)
			y += 3.0
		var sweep_y := fposmod(t * 90.0, size.y + 160.0) - 80.0
		draw_line(Vector2(inset, sweep_y), Vector2(size.x - inset, sweep_y), Color(1, 1, 1, 0.05), 8.0)
