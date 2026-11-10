class_name SkillPanel
extends Control
## Path of Exile 2 style skills menu, built in code in the same look as the inventory.
## Press K to open it.
##
##  - HOTKEYS: the keys from your Input Map. Click a key, then click a socketed skill to bind it.
##    Right-click a key to clear it.
##  - SKILL SOCKETS: left-click an empty socket to pick a gem from your backpack.
##    Right-click a filled socket to take the gem back out.
##  - Each skill has support sockets next to it. Hover anything for a tooltip.
##  - SCRIPTING tab: build WHEN / DO programs for socketed skills and supports (SkillScriptTab).
##
## Setup: add a plain Control to the Hud CanvasLayer, attach this script, and call bind() from the player.

@export var toggle_key: Key = KEY_K
@export var panel_width: float = 780.0
@export var panel_height: float = 660.0
## Size of the menu while the SCRIPTING tab is open (it is clamped to fit the screen).
@export var script_panel_width: float = 1120.0
@export var script_panel_height: float = 800.0
## Text size of the code in the SCRIPTING tab. Everything in that tab scales with it.
@export var script_font_size: int = 17
@export_range(0.0, 1.0, 0.01) var bg_opacity: float = 0.92
@export var font_scale: float = 1.0
@export var font: Font                          # leave empty to use the Courier Prime font below
@export var accent := Color("#00E5FF")
@export var slot_size: float = 64.0
## Keys the player may not bind to a skill (menu keys and escape).
@export var reserved_keys: Array[int] = [KEY_ESCAPE, KEY_K, KEY_I, KEY_C, KEY_M]
@export var auto_bind: bool = true
const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const CHAMFER := 24.0
const ROWS_RIGHT_GAP := 22                        # px between the skill rows' text and the scroll bar
const TIP_WIDTH := 300.0                          # gem tooltips: text wraps at this width
const TIP_PAD_X := 12.0
const SUPPORT_CELLS := 4                          # support cells drawn per skill row (extra ones show locked)

const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_WARN := Color(1.0, 0.30, 0.37)
const COL_SKILL := Color(0.30, 0.95, 0.60)        # skill gems
const COL_SUPPORT := Color(0.45, 0.75, 1.0)       # support gems

var _font: Font
var _skills: SkillComponent
var _inv: InventoryComponent

var _built := false
var _open := false
var _tween: Tween
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _changed_mouse_mode := false

var _pending_action: StringName = &""             # the hotkey waiting for a skill to be bound
var _rebinding: StringName = &""                 # the hotkey waiting for a new key to be pressed
var _picker_kind := ""                            # "skill" or "support"
var _picker_socket := -1

var _hotkeys: Dictionary = {}                     # action -> GemSlot
var _hotkey_labels: Dictionary = {}               # action -> Label
var _rows: Array[Dictionary] = []                 # {skill: GemSlot, supports: Array, info: Label}
var _rows_box: VBoxContainer
var _picker_frame: PanelContainer
var _picker_title: Label
var _picker_empty: Label
var _picker_grid: GridContainer
var _tip: PanelContainer
var _tip_box: VBoxContainer
var _msg_label: Label
var _msg_tween: Tween

const SIDE_GAP := 16.0                 # breathing room between the two panels

var _sockets_page: VBoxContainer
var _script_page: SkillScriptTab
var _tab_sockets: Button
var _tab_script: Button
var _tab := "sockets"                  # "sockets" or "scripting"

var _inventory_panel: InventoryPanel
var _equip: EquipmentComponent
var _shift_tween: Tween

func quick_socket(item: ItemInstance) -> String:
	if _skills == null or _inv == null or item == null:
		return "SKILLS MENU NOT READY"
	open()

	if item.definition.skill_gem != null:
		var gem_def := item.definition.skill_gem
		if not SkillInstance.definition_allows(gem_def, _equip):
			return "NEEDS: " + SkillInstance.definition_requires_text(gem_def)
		for i in _skills.sockets.size():
			if _skills.sockets[i].gem != null:
				continue
			if not _skills.socket_skill(i, item, _inv):
				return "THAT GEM CANNOT GO THERE"
			if auto_bind:
				for action in SkillComponent.ACTIONS:
					if not _skills.bindings.has(action):
						_skills.bind_action(action, i)
						break
			return ""
		return "NO FREE SKILL SOCKET"

	if item.definition.support_gem != null:
		for i in _skills.sockets.size():
			if _skills.can_socket_support(i, item):
				_skills.socket_support(i, item, _inv)
				return ""
		return "NO SKILL CAN USE THIS SUPPORT"

	return "CANNOT EQUIP THIS ITEM"

func _enter_tree() -> void:
	add_to_group("skill_panel")

func is_open() -> bool:
	return _open

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	Settings.bind_to(self, &"auto_bind", "gameplay", "auto_bind_skills")
	KeyBindings.load_saved()
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_layout()
	_build_ui()
	_built = true
	visible = false
	modulate.a = 0.0
	_apply_bound_data()
	call_deferred("_find_inventory_panel")                        # the inventory may not be ready yet
	get_viewport().size_changed.connect(func() -> void:
		_layout()
		_shift_for_inventory(false))

func _find_inventory_panel() -> void:
	_inventory_panel = get_tree().get_first_node_in_group("inventory_panel") as InventoryPanel
	if _inventory_panel:
		_inventory_panel.open_changed.connect(_on_inventory_open_changed)


func _on_inventory_open_changed(_is_open: bool) -> void:
	_shift_for_inventory(_open)                    # animate only if this panel is showing


## How far left to move so this panel doesn't sit under the inventory. 0 if the inventory is closed.
func _avoid_distance() -> float:
	if _inventory_panel == null or not _inventory_panel.is_open():
		return 0.0
	var vp := get_viewport_rect().size
	var my_right := vp.x * 0.5 + _width() * 0.5
	var inv_left := vp.x - (InventoryPanel.OPEN_X + _inventory_panel.panel_width)
	var distance := maxf(my_right - inv_left + SIDE_GAP, 0.0)
	var room_on_left := maxf(vp.x * 0.5 - _width() * 0.5 - 8.0, 0.0)
	return minf(distance, room_on_left)           # never push the panel off the left edge


func _shift_for_inventory(animate: bool) -> void:
	var dx := -_avoid_distance()
	var left := -_width() * 0.5 + dx
	var right := _width() * 0.5 + dx
	if _shift_tween:
		_shift_tween.kill()
	if not animate:
		offset_left = left
		offset_right = right
		return
	_shift_tween = create_tween().set_parallel(true)
	_shift_tween.tween_property(self, "offset_left", left, 0.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shift_tween.tween_property(self, "offset_right", right, 0.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _layout() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -_width() * 0.5
	offset_right = _width() * 0.5
	offset_top = -_height() * 0.5
	offset_bottom = _height() * 0.5


## The menu is bigger while scripting, but never bigger than the screen.
func _width() -> float:
	var w := script_panel_width if _tab == "scripting" else panel_width
	return minf(w, get_viewport_rect().size.x - 32.0) if is_inside_tree() else w


func _height() -> float:
	var h := script_panel_height if _tab == "scripting" else panel_height
	return minf(h, get_viewport_rect().size.y - 32.0) if is_inside_tree() else h

# ---------- PUBLIC ----------
func bind(skills: SkillComponent, inventory: InventoryComponent, equipment: EquipmentComponent = null) -> void:
	if _equip and _equip.equipment_changed.is_connected(_on_data_changed):
		_equip.equipment_changed.disconnect(_on_data_changed)
	_equip = equipment
	if _equip:
		_equip.equipment_changed.connect(_on_data_changed)
		
	if _skills and _skills.changed.is_connected(_on_data_changed):
		_skills.changed.disconnect(_on_data_changed)
		
	if _inv and _inv.changed.is_connected(_on_data_changed):
		_inv.changed.disconnect(_on_data_changed)
	_skills = skills
	_inv = inventory
	if _skills:
		_skills.changed.connect(_on_data_changed)
	if _inv:
		_inv.changed.connect(_on_data_changed)
	if _built:
		_apply_bound_data()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open or not _built:
		return
	_open = true
	var mode := Input.mouse_mode
	if mode == Input.MOUSE_MODE_CAPTURED or mode == Input.MOUSE_MODE_HIDDEN \
			or mode == Input.MOUSE_MODE_CONFINED_HIDDEN:
		_prev_mouse_mode = mode
		_changed_mouse_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _skills == null or _inv == null:
		push_warning("SkillPanel: not bound. Is bind() being called from the player?")
	_refresh()
	_shift_for_inventory(false)
	visible = true
	_fade(1.0)
	GameEvents.report("open_panel", "skills")


func close() -> void:
	if not _open:
		return
	_open = false
	_pending_action = &""
	_stop_rebind()
	_close_picker()
	_hide_tip()
	if _changed_mouse_mode:
		Input.mouse_mode = _prev_mouse_mode
		_changed_mouse_mode = false
	_fade(0.0)


# ---------- REBINDING KEYS ----------
func _key_text(action: StringName) -> String:
	return "PRESS KEY" if action == _rebinding else GemText.key_label(action)


func _start_rebind(action: StringName) -> void:
	_pending_action = &""
	_rebinding = action
	_close_picker()
	_refresh()
	_msg_label.text = "PRESS A KEY OR MOUSE BUTTON   (ESC CANCELS)"
	_msg_label.modulate.a = 1.0
	if _msg_tween:
		_msg_tween.kill()


func _stop_rebind() -> void:
	if _rebinding == &"":
		return
	_rebinding = &""
	if _msg_tween:
		_msg_tween.kill()
	_msg_label.modulate.a = 0.0
	if _built:
		_refresh()


func _reset_keys() -> void:
	_stop_rebind()
	KeyBindings.reset_all()
	_refresh()
	_notify("KEYS RESET TO DEFAULT")


## Runs before the game sees the key, so the key that is pressed to rebind never also fires a skill.
func _input(event: InputEvent) -> void:
	if _rebinding == &"" or not _open:
		return
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	var is_key := key != null and key.pressed and not key.echo
	var is_mouse := mouse != null and mouse.pressed
	if not (is_key or is_mouse):
		return
	if is_key and key.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return                                        # wait for the real key
	if is_mouse and mouse.button_index >= MOUSE_BUTTON_WHEEL_UP \
			and mouse.button_index <= MOUSE_BUTTON_WHEEL_RIGHT:
		return                                        # the scroll wheel is not bindable
	get_viewport().set_input_as_handled()
	if is_key and key.keycode == KEY_ESCAPE:
		_stop_rebind()
		return
	if is_mouse and mouse.button_index == MOUSE_BUTTON_LEFT \
			and get_global_rect().has_point(get_global_mouse_position()):
		_stop_rebind()                                # a left click on the menu just cancels
		return
	var action := _rebinding
	_stop_rebind()
	var error := KeyBindings.rebind(action, event, SkillComponent.ACTIONS, reserved_keys)
	_refresh()
	if error != "":
		_notify(error)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == toggle_key:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _open:
		if _picker_frame.visible:
			_close_picker()
		else:
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


func _process(_delta: float) -> void:
	if _tip.visible:
		_position_tip()


func _on_data_changed() -> void:
	if _built:
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
	col.add_child(title_row)
	var title := _label("// SKILLS //", 26, accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn := _button("X", 20)
	close_btn.custom_minimum_size = Vector2(44, 36)
	close_btn.pressed.connect(close)
	title_row.add_child(close_btn)
	col.add_child(_build_tabs())
	col.add_child(_rule())

	# SOCKETS page: everything that was here before
	_sockets_page = VBoxContainer.new()
	_sockets_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sockets_page.add_theme_constant_override("separation", 10)
	col.add_child(_sockets_page)
	var page := _sockets_page

	var hotkey_head := HBoxContainer.new()
	page.add_child(hotkey_head)
	var hotkey_title := _label("HOTKEYS", 17, COL_DIM)
	hotkey_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hotkey_head.add_child(hotkey_title)
	var reset_btn := _button("RESET KEYS", 13)
	reset_btn.pressed.connect(_reset_keys)
	hotkey_head.add_child(reset_btn)
	page.add_child(_build_hotkeys())
	page.add_child(_rule())

	page.add_child(_label("SKILL SOCKETS", 17, COL_DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 120.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(scroll.get_v_scroll_bar())
	page.add_child(scroll)
	# Keep the rows clear of the scroll bar: their right-aligned "KEY [..]  MANA .." text would
	# otherwise run under it.
	var rows_pad := MarginContainer.new()
	rows_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_pad.add_theme_constant_override("margin_right", ROWS_RIGHT_GAP)
	scroll.add_child(rows_pad)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 8)
	rows_pad.add_child(_rows_box)
	_rebuild_rows(6)

	page.add_child(_build_picker())

	# SCRIPTING page
	_script_page = SkillScriptTab.new()
	_script_page.panel = self
	_script_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_script_page.visible = false
	col.add_child(_script_page)
	_script_page.build()

	_msg_label = _label("", 15, COL_WARN)
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.modulate.a = 0.0
	col.add_child(_msg_label)

	var hint := _label("[ %s ] CLOSE   |   HOTKEY, THEN SKILL: BIND   |   LEFT-CLICK EMPTY: SOCKET   |   RIGHT-CLICK: REMOVE" \
		% OS.get_keycode_string(toggle_key), 12, COL_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(hint)
	var hint2 := _label("CLICK THE KEY UNDER A HOTKEY, THEN PRESS A NEW KEY TO REBIND IT", 12, COL_DIM)
	hint2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(hint2)

	var overlay := ScanOverlay.new()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Tooltip is added last so it draws over everything else
	_tip = PanelContainer.new()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.custom_minimum_size.x = TIP_WIDTH
	var tip_style := _flat(Color(0.02, 0.05, 0.09, 0.97), Color(accent, 0.8), 1)
	tip_style.content_margin_left = TIP_PAD_X
	tip_style.content_margin_right = TIP_PAD_X
	tip_style.content_margin_top = 10
	tip_style.content_margin_bottom = 10
	_tip.add_theme_stylebox_override("panel", tip_style)
	_tip_box = VBoxContainer.new()
	_tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_box.add_theme_constant_override("separation", 3)
	_tip.add_child(_tip_box)
	add_child(_tip)


func _build_tabs() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	_tab_sockets = _button("SOCKETS", 15)
	_tab_script = _button("SCRIPTING", 15)
	for b in [_tab_sockets, _tab_script]:
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(150, 34)
		row.add_child(b)
	_tab_sockets.button_pressed = true
	_tab_sockets.pressed.connect(show_tab.bind("sockets"))
	_tab_script.pressed.connect(show_tab.bind("scripting"))
	return row


## Switch between the "sockets" and "scripting" pages.
func show_tab(tab_name: String) -> void:
	_tab = tab_name
	var scripting := tab_name == "scripting"
	_sockets_page.visible = not scripting
	_script_page.visible = scripting
	_tab_sockets.set_pressed_no_signal(not scripting)
	_tab_script.set_pressed_no_signal(scripting)
	_pending_action = &""
	_stop_rebind()
	_close_picker()
	_hide_tip()
	_layout()                                  # the scripting tab uses a bigger menu
	_shift_for_inventory(false)
	queue_redraw()
	if scripting:
		_script_page.refresh()
	else:
		_refresh()


func _build_hotkeys() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for action in SkillComponent.ACTIONS:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var s := _make_slot("hotkey")
		s.action = action
		s.hint = "-"
		cell.add_child(s)
		var lbl := _button(_key_text(action), 14)
		lbl.custom_minimum_size = Vector2(slot_size, 28.0)
		lbl.pressed.connect(_start_rebind.bind(action))
		cell.add_child(lbl)
		row.add_child(cell)
		_hotkeys[action] = s
		_hotkey_labels[action] = lbl
	return row


func _rebuild_rows(count: int) -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	for i in count:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var skill_slot := _make_slot("skill")
		skill_slot.socket_i = i
		skill_slot.hint = "+"
		row.add_child(skill_slot)

		var support_box := HBoxContainer.new()
		support_box.add_theme_constant_override("separation", 6)
		var cells: Array = []
		for j in SUPPORT_CELLS:
			var cell := _make_slot("support")
			cell.socket_i = i
			cell.support_i = j
			cell.hint = "+"
			support_box.add_child(cell)
			cells.append(cell)
		row.add_child(support_box)

		var info := _label("", 15, COL_TEXT)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(info)

		_rows_box.add_child(row)
		_rows.append({"skill": skill_slot, "supports": cells, "info": info})


func _build_picker() -> PanelContainer:
	_picker_frame = PanelContainer.new()
	_picker_frame.visible = false
	_picker_frame.add_theme_stylebox_override("panel", _flat(Color(0, 0, 0, 0.35), Color(accent, 0.5), 1))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_picker_frame.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	_picker_title = _label("SELECT A GEM", 16, accent)
	_picker_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_picker_title)
	var cancel := _button("CANCEL", 14)
	cancel.pressed.connect(_close_picker)
	head.add_child(cancel)

	_picker_empty = _label("NO MATCHING GEMS IN YOUR BACKPACK", 14, COL_DIM)
	box.add_child(_picker_empty)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 150.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(scroll.get_v_scroll_bar())
	box.add_child(scroll)
	_picker_grid = GridContainer.new()
	_picker_grid.columns = 8
	_picker_grid.add_theme_constant_override("h_separation", 6)
	_picker_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_picker_grid)
	return _picker_frame


func _make_slot(kind: String) -> GemSlot:
	var s := GemSlot.new()
	s.kind = kind
	s.custom_minimum_size = Vector2(slot_size, slot_size)
	s.accent = accent
	s.skill_col = COL_SKILL
	s.support_col = COL_SUPPORT
	s.font = _font if _font else ThemeDB.fallback_font
	s.hovered.connect(_on_slot_hovered)
	s.unhovered.connect(_hide_tip)
	s.clicked.connect(_on_slot_clicked)
	return s


# ---------- REFRESHING ----------
func _apply_bound_data() -> void:
	var count := _skills.sockets.size() if _skills else 6
	if count > 0 and count != _rows.size():
		_rebuild_rows(count)
	_refresh()


func _refresh() -> void:
	if not _built:
		return
	_hide_tip()
	if _script_page.visible:
		_script_page.refresh()

	for action in SkillComponent.ACTIONS:
		var slot: GemSlot = _hotkeys[action]
		var index := -1
		if _skills:
			index = _skills.bindings.get(action, -1)
		slot.item = _skills.sockets[index].gem if index >= 0 else null
		slot.highlight = action == _pending_action
		(_hotkey_labels[action] as Button).text = _key_text(action)

	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var s: SkillComponent.Socket = null
		if _skills and i < _skills.sockets.size():
			s = _skills.sockets[i]

		var skill_slot: GemSlot = row["skill"]
		skill_slot.item = s.gem if s else null
		skill_slot.incompatible = s != null and s.skill != null and not s.skill.weapon_allows(_equip)
		
		var capacity := 0
		if s and s.gem:
			capacity = s.gem.definition.skill_gem.max_support_slots
		var cells: Array = row["supports"]
		for j in cells.size():
			var cell: GemSlot = cells[j]
			cell.item = s.supports[j] if (s and j < s.supports.size()) else null
			cell.locked = j >= capacity
		var info: Label = row["info"]
		if s and s.skill:
			var action := _skills.action_of(i)
			var key := GemText.key_label(action) if action != &"" else "--"
			if s.skill.weapon_allows(_equip):
				info.text = "KEY [%s]   MANA %s" % [key, GemText.num(s.skill.get_mana_cost())]
				info.add_theme_color_override("font_color", COL_TEXT)
			else:
				info.text = "NEEDS: " + s.skill.required_weapons_text()
				info.add_theme_color_override("font_color", COL_WARN)
		else:
			info.text = "EMPTY"
			info.add_theme_color_override("font_color", COL_TEXT)


# ---------- TUTORIAL ----------
## What the tutorial hints (autoload/tutorial_hints.gd) need to know about this panel.
func tutorial_state() -> Dictionary:
	return {
		"tab": _tab,
		"picker": _built and _picker_frame.visible,
		"pending": _pending_action,
	}


## Controls the tutorial hints can outline. Empty while closed.
## ids: picker, empty_socket, filled_socket, empty_support, filled_support, tab_sockets, tab_script, script_palette,
##      script_apply, hotkey_<action> (e.g. hotkey_attack)
func tutorial_target(id: String) -> Array[Control]:
	var out: Array[Control] = []
	if not _open or not _built:
		return out
	match id:
		"picker":
			if _picker_frame.visible:
				for c in _picker_grid.get_children():
					if c is Control:
						out.append(c)
		"empty_socket", "filled_socket":
			for row in _rows:
				var slot: GemSlot = row["skill"]
				if (slot.item == null) == (id == "empty_socket"):
					out.append(slot)
					break
		"empty_support", "filled_support":       # first open (unlocked) support cell, or a used one
			for row in _rows:
				var found := false
				for cell: GemSlot in row["supports"]:
					if not cell.locked and (cell.item == null) == (id == "empty_support"):
						out.append(cell)
						found = true
						break
				if found:
					break
		"tab_sockets":
			out.append(_tab_sockets)
		"tab_script":
			out.append(_tab_script)
		"script_palette", "script_apply":
			out.append_array(_script_page.tutorial_target(id))
		_:
			if id.begins_with("script:"):          # inside the SCRIPTING tab
				out.append_array(_script_page.tutorial_target(id.trim_prefix("script:")))
			else:
				var action := StringName(id.trim_prefix("hotkey_"))
				if id.begins_with("hotkey_") and _hotkeys.has(action):
					out.append(_hotkeys[action])
	return out


## The SCRIPTING tab's tutorial state for a rule using `condition_id` (see SkillScriptTab).
func tutorial_script_state(condition_id: String) -> Dictionary:
	return _script_page.tutorial_state(condition_id) if _built else {}


## The SCRIPTING GUIDE (ScriptGuide), for the tutorial: open it on the SCRIPTING tab, and is it open.
func open_script_guide(page := "") -> void:
	if _built and _open and _tab == "scripting":
		_script_page.open_guide(page)


func script_guide_open() -> bool:
	return _built and _open and _script_page.guide_open()


# ---------- CLICKING ----------
func _on_slot_clicked(slot: GemSlot, button: int) -> void:
	if _skills == null or _inv == null:
		return
	match slot.kind:
		"hotkey":
			if button == MOUSE_BUTTON_RIGHT:
				_skills.clear_action(slot.action)
				_pending_action = &""
			else:
				_pending_action = &"" if _pending_action == slot.action else slot.action
			_refresh()
		"skill":
			_click_skill(slot, button)
		"support":
			_click_support(slot, button)
		"picker":
			_pick(slot.item)


func _click_skill(slot: GemSlot, button: int) -> void:
	var i := slot.socket_i
	if slot.item == null:
		if button == MOUSE_BUTTON_LEFT:
			_open_picker("skill", i)
		return
	if button == MOUSE_BUTTON_RIGHT:
		if not _skills.unsocket_skill(i, _inv):
			_notify("NOT ENOUGH BACKPACK SPACE FOR THE GEMS")
		return
	if _pending_action == &"":
		_notify("CLICK A HOTKEY ABOVE FIRST")
		return
	_skills.bind_action(_pending_action, i)
	_pending_action = &""
	_refresh()


func _click_support(slot: GemSlot, button: int) -> void:
	if slot.locked:
		var no_skill := _skills.sockets[slot.socket_i].gem == null
		_notify("SOCKET A SKILL FIRST" if no_skill else "NO MORE SUPPORT SLOTS ON THIS SKILL")
		return
	if slot.item == null:
		if button == MOUSE_BUTTON_LEFT:
			_open_picker("support", slot.socket_i)
		return
	if button == MOUSE_BUTTON_RIGHT:
		if not _skills.unsocket_support(slot.socket_i, slot.support_i, _inv):
			_notify("BACKPACK FULL")


# ---------- GEM PICKER ----------
func _open_picker(kind: String, socket: int) -> void:
	_picker_kind = kind
	_picker_socket = socket
	for child in _picker_grid.get_children():
		_picker_grid.remove_child(child)
		child.queue_free()
	var count := 0
	for item in _inv.items:
		var fits := false
		if kind == "skill":
			fits = item.definition.skill_gem != null
		else:
			fits = _skills.can_socket_support(socket, item)
		if not fits:
			continue
		var s := _make_slot("picker")
		s.item = item
		_picker_grid.add_child(s)
		count += 1
	_picker_title.text = "SELECT A SKILL GEM" if kind == "skill" else "SELECT A SUPPORT GEM"
	_picker_empty.visible = count == 0
	_picker_frame.visible = true


func _close_picker() -> void:
	_picker_frame.visible = false
	_picker_kind = ""
	_picker_socket = -1
	_hide_tip()


func _pick(item: ItemInstance) -> void:
	if item == null:
		return
	if _picker_kind == "skill" and not SkillInstance.definition_allows(item.definition.skill_gem, _equip):
		_notify("NEEDS: " + SkillInstance.definition_requires_text(item.definition.skill_gem))
		return
	var ok := false
	if _picker_kind == "skill":
		ok = _skills.socket_skill(_picker_socket, item, _inv)
		if ok and _pending_action != &"":                 # a hotkey was waiting, so bind it straight away
			_skills.bind_action(_pending_action, _picker_socket)
			_pending_action = &""
	else:
		ok = _skills.socket_support(_picker_socket, item, _inv)
	if ok:
		_close_picker()
	else:
		_notify("THAT GEM CANNOT GO THERE")


# ---------- TOOLTIPS ----------
func _on_slot_hovered(slot: GemSlot) -> void:
	var parts := _tooltip_for(slot)
	if parts.is_empty():
		_hide_tip()
		return
	for child in _tip_box.get_children():
		_tip_box.remove_child(child)
		child.queue_free()
	# Wrapping lines get a fixed width up front: a wrapping label only knows its height once it
	# knows its width, and without one it measures one word per line (a far too tall tooltip).
	var wrap_w := TIP_WIDTH - TIP_PAD_X * 2.0
	for part in parts:                                    # each part is [text, colour, font size]
		var l := _label(part[0], part[2], part[1])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = wrap_w
		_tip_box.add_child(l)
	_tip.visible = true
	_fit_tip()
	_fit_tip.call_deferred()                              # once more after layout: final height


## Shrinks the tooltip to its content and keeps it on screen.
func _fit_tip() -> void:
	if _tip == null or not _tip.visible:
		return
	_tip.size = Vector2.ZERO
	_tip.reset_size()
	_position_tip()


func _hide_tip() -> void:
	if _tip:
		_tip.visible = false


func _position_tip() -> void:
	var vp := get_viewport_rect().size
	var ts := _tip.get_combined_minimum_size()
	var p := get_global_mouse_position() + Vector2(18.0, 18.0)
	p.x = minf(p.x, vp.x - ts.x - 8.0)
	p.y = minf(p.y, vp.y - ts.y - 8.0)
	_tip.global_position = p


func _tooltip_for(slot: GemSlot) -> Array:
	match slot.kind:
		"hotkey":
			if slot.item == null:
				return [["EMPTY HOTKEY", COL_DIM, 18],
					["Click it, then click a socketed skill to bind that skill here. Right-click clears it.", COL_DIM, 14]]
			return _skill_tip(_skills.bindings.get(slot.action, -1))
		"skill":
			if slot.item == null:
				return [["EMPTY SKILL SOCKET", COL_DIM, 18],
					["Left-click to socket a skill gem from your backpack.", COL_DIM, 14]]
			return _skill_tip(slot.socket_i)
		"support":
			if slot.locked:
				var no_skill := _skills.sockets[slot.socket_i].gem == null
				return [["LOCKED", COL_DIM, 18],
					["Socket a skill gem first." if no_skill else "This skill has no more support slots.", COL_DIM, 14]]
			if slot.item == null:
				return [["EMPTY SUPPORT SOCKET", COL_DIM, 18],
					["Left-click to socket a support gem that works with this skill.", COL_DIM, 14]]
			return _support_tip(slot.item, "")
		"picker":
			if slot.item.definition.skill_gem != null:
				return _gem_preview_tip(slot.item)
			return _support_tip(slot.item, "Left-click to socket it.")
	return []


func _skill_tip(socket_index: int) -> Array:
	if _skills == null or socket_index < 0 or socket_index >= _skills.sockets.size():
		return []
	var s := _skills.sockets[socket_index]
	if s.gem == null:
		return []
	var def := s.gem.definition.skill_gem
	var parts: Array = [[s.gem.get_display_name().to_upper(), COL_SKILL, 20]]
	var action := _skills.action_of(socket_index)
	var sub := "SKILL GEM"
	if action != &"":
		sub += "  //  KEY [%s]" % GemText.key_label(action)
	parts.append([sub, COL_DIM, 14])
	parts.append(["TAGS: " + GemText.tag_names(def.tags), COL_DIM, 13])
	if def.description != "":
		parts.append([def.description, COL_TEXT, 15])
	parts.append(["", COL_TEXT, 5])
	for line in GemText.skill_lines(s.skill):
		parts.append([line, COL_TEXT, 16])
	if not s.supports.is_empty():
		parts.append(["", COL_TEXT, 5])
		parts.append(["SUPPORTS", COL_DIM, 14])
		for sup in s.supports:
			parts.append([sup.get_display_name(), COL_SUPPORT, 15])
	if not s.skill.weapon_allows(_equip):
		parts.append(["REQUIRES: " + s.skill.required_weapons_text(), COL_WARN, 14])
	return parts


func _gem_preview_tip(item: ItemInstance) -> Array:
	var def := item.definition.skill_gem
	var parts: Array = [
		[item.get_display_name().to_upper(), COL_SKILL, 20],
		["SKILL GEM", COL_DIM, 14],
		["TAGS: " + GemText.tag_names(def.tags), COL_DIM, 13]]
	if def.description != "":
		parts.append([def.description, COL_TEXT, 15])
	parts.append(["", COL_TEXT, 5])
	for line in GemText.gem_lines(def):
		parts.append([line, COL_TEXT, 16])
	if not SkillInstance.definition_allows(def, _equip):
		parts.append(["", COL_TEXT, 5])
		parts.append(["REQUIRES: " + SkillInstance.definition_requires_text(def), COL_WARN, 14])
	parts.append(["", COL_TEXT, 5])
	parts.append(["Left-click to socket it.", COL_DIM, 13])
	return parts

func _support_tip(item: ItemInstance, footer: String) -> Array:
	var def := item.definition.support_gem
	var parts: Array = [
		[item.get_display_name().to_upper(), COL_SUPPORT, 20],
		["SUPPORT GEM", COL_DIM, 14],
		["WORKS WITH: " + GemText.tag_names(def.allowed_tags), COL_DIM, 13]]
	if def.description != "":
		parts.append([def.description, COL_TEXT, 15])
	parts.append(["", COL_TEXT, 5])
	for line in GemText.support_lines(def):
		parts.append([line, COL_SUPPORT, 16])
	if footer != "":
		parts.append(["", COL_TEXT, 5])
		parts.append([footer, COL_DIM, 13])
	return parts


func _notify(text: String) -> void:
	_msg_label.text = text
	_msg_label.modulate.a = 1.0
	if _msg_tween:
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_interval(1.2)
	_msg_tween.tween_property(_msg_label, "modulate:a", 0.0, 0.5)


# ---------- STYLING HELPERS ----------
# (Same look as CharacterPanel and InventoryPanel.)
func _draw() -> void:
	var w := size.x
	var h := size.y
	var poly := PackedVector2Array([
		Vector2(CHAMFER, 0), Vector2(w, 0), Vector2(w, h - CHAMFER),
		Vector2(w - CHAMFER, h), Vector2(0, h), Vector2(0, CHAMFER)])
	draw_colored_polygon(poly, Color(0.02, 0.05, 0.09, bg_opacity))
	var outline := PackedVector2Array(poly)
	outline.append(poly[0])
	draw_polyline(outline, Color(accent, 0.18), 7.0, true)
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
	b.add_theme_stylebox_override("normal", _flat(Color(accent, 0.06), Color(accent, 0.35), 1))
	b.add_theme_stylebox_override("hover", _flat(Color(accent, 0.16), Color(accent, 0.8), 1))
	b.add_theme_stylebox_override("pressed", _flat(Color(accent, 0.28), accent, 2))
	b.add_theme_stylebox_override("hover_pressed", _flat(Color(accent, 0.28), accent, 2))
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
## One square cell: a hotkey, a skill socket, a support socket, or a gem in the picker.
class GemSlot extends Control:
	signal hovered(slot)
	signal unhovered
	signal clicked(slot, button)

	var item: ItemInstance:
		set(value):
			item = value
			queue_redraw()
	var locked := false:
		set(value):
			locked = value
			queue_redraw()
	var highlight := false:
		set(value):
			highlight = value
			queue_redraw()
	var incompatible := false:
		set(value):
			incompatible = value
			queue_redraw()
	var kind := ""                  # "hotkey", "skill", "support" or "picker"
	var socket_i := -1              # which skill socket row this belongs to
	var support_i := -1             # which support cell in that row
	var action: StringName = &""    # hotkeys only
	var hint := ""                  # faint text shown when empty
	var accent := Color.WHITE
	var skill_col := Color.WHITE
	var support_col := Color.WHITE
	var font: Font
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
				clicked.emit(self, event.button_index)
				accept_event()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := 9.0
		var poly := PackedVector2Array([
			Vector2(0, 0), Vector2(w - c, 0), Vector2(w, c),
			Vector2(w, h), Vector2(c, h), Vector2(0, h - c)])
		var outline := PackedVector2Array(poly)
		outline.append(poly[0])

		if locked:
			draw_colored_polygon(poly, Color(0, 0, 0, 0.35))
			draw_polyline(outline, Color(accent, 0.12), 1.5, true)
			draw_string(font, Vector2(0, h * 0.5 + 6.0), "-", HORIZONTAL_ALIGNMENT_CENTER, w, 20,
				Color(accent, 0.2))
			return

		var col := accent
		if item != null:
			col = skill_col if item.definition.skill_gem != null else support_col
		draw_colored_polygon(poly, Color(col, 0.18 if item != null else 0.05))

		var edge := accent if highlight else col
		if incompatible and item != null:
			edge = Color(1.0, 0.30, 0.37)
		var alpha := 0.9 if item != null else 0.25
		if _hover or highlight:
			draw_polyline(outline, Color(edge, 0.25), 7.0, true)    # glow
			alpha = 1.0
		draw_polyline(outline, Color(edge, alpha), 3.0 if highlight else 2.0, true)

		if item != null:
			draw_string(font, Vector2(0, h * 0.5 + 7.0), item.definition.display_name.left(3).to_upper(),
				HORIZONTAL_ALIGNMENT_CENTER, w, 20, col)
		elif hint != "":
			draw_string(font, Vector2(0, h * 0.5 + 9.0), hint, HORIZONTAL_ALIGNMENT_CENTER, w, 26,
				Color(accent, 0.4))


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
		# The sweep stays inside the scanlines' band, so it never shows past the panel's edges
		var top := 2.0 + 4.0                          # half the sweep's 8 px thickness
		var band := maxf(size.y - 4.0 - 8.0, 1.0)
		var sweep_y := top + fposmod(t * 90.0, band)
		draw_line(Vector2(inset, sweep_y), Vector2(size.x - inset, sweep_y), Color(1, 1, 1, 0.05), 8.0)
