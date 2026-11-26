extends Control
## SAVE EDITOR (for testing): change a character's credits, rank, quests, keys, waypoints, ending
## and tower progress, then save. Run this scene on its own (open save_editor.tscn and press F6,
## or `godot --path . res://tools/save_editor/save_editor.tscn`); it never starts the game.
##
## It must run through Godot so it edits the real save folder (user://saves). Close the game
## first: a running game keeps its own copy of the character and would save over these edits.
## Every save first copies the slot to user://saves/backups/ (slot_N_<date>.json).
##
## The rules for each change are in SaveEdit.

const FONT_PATH := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const ACCENT := Color("#00E5FF")
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_OK := Color(0.35, 0.95, 0.6)
const COL_WARN := Color(1.0, 0.55, 0.35)
const BACKUP_DIR := "user://saves/backups/"

var _font: Font
var _slot := -1
var _data: Dictionary = {}
var _dirty := false
var _catalog: Array[QuestDefinition] = []

var _slots: VBoxContainer
var _title: Label
var _status: Label
var _tabs: TabContainer
var _save_btn: Button
var _revert_btn: Button


func _ready() -> void:
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catalog = SaveEdit.quest_catalog()
	_build()
	_list_slots()
	_show_empty()
	_as_a_window.call_deferred()


## The game's settings may have put the window in fullscreen (Settings, from settings.cfg): the
## editor is a plain window with its own title, whatever the game uses.
func _as_a_window() -> void:
	var win := get_window()
	win.title = "CodeBreak: Requiem  //  Save Editor (for playtesting)"
	if win.mode != Window.MODE_WINDOWED:
		win.mode = Window.MODE_WINDOWED
		win.size = Vector2i(1440, 900)
		win.move_to_center()


# ---------- SLOTS ----------
func _list_slots() -> void:
	for c in _slots.get_children():
		c.queue_free()
	_slots.add_child(_label("CHARACTERS", 20, ACCENT))
	for i in SaveManager.MAX_SLOTS:
		if not SaveManager.slot_exists(i):
			continue
		var d := SaveManager.load_slot(i)
		var b := _button("%d  %s\n   %s  ·  %s  ·  %d CR" % [i, str(d.get("name", "?")),
				str(d.get("class_id", "")).capitalize(), Ranks.LADDER[SaveEdit.rank_index(d)]["name"],
				SaveEdit.credits(d)], 15)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 56)
		b.pressed.connect(_open_slot.bind(i))
		_slots.add_child(b)
	if _slots.get_child_count() == 1:
		_slots.add_child(_label("No saves in user://saves.", 15, COL_DIM))


func _open_slot(i: int) -> void:
	if _dirty and i != _slot:
		_set_status("Unsaved changes to slot %d were dropped." % _slot, COL_WARN)
	_slot = i
	_data = SaveManager.load_slot(i)
	_dirty = false
	_refresh()


func _refresh() -> void:
	if _data.is_empty():
		_show_empty()
		return
	_title.text = "SLOT %d  //  %s  (%s)" % [_slot, str(_data.get("name", "?")).to_upper(),
			str(_data.get("class_id", "")).capitalize()]
	var keep := _tabs.current_tab
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_tabs.add_child(_overview_tab())
	_tabs.add_child(_quests_tab())
	_tabs.add_child(_keys_tab())
	_tabs.add_child(_waypoints_tab())
	_tabs.current_tab = clampi(keep, 0, _tabs.get_tab_count() - 1)
	_tabs.visible = true
	_save_btn.disabled = not _dirty
	_revert_btn.disabled = not _dirty


func _show_empty() -> void:
	_title.text = "SAVE EDITOR"
	_tabs.visible = false
	_save_btn.disabled = true
	_revert_btn.disabled = true
	_set_status("Pick a character on the left. Close the game first: a running game would save over your edits.", COL_DIM)


func _changed(what: String) -> void:
	_dirty = true
	_save_btn.disabled = false
	_revert_btn.disabled = false
	_set_status("Changed: %s. Not saved yet." % what, COL_WARN)


func _save() -> void:
	if _slot < 0 or _data.is_empty():
		return
	var backup := _backup(_slot)
	if backup == "":
		_set_status("Could not back up slot %d, so nothing was saved." % _slot, COL_WARN)
		return
	if SaveManager.save_slot(_slot, _data):
		_dirty = false
		_set_status("Saved slot %d. Backup: %s" % [_slot, backup], COL_OK)
		_list_slots()
		_refresh()
	else:
		_set_status("Saving slot %d failed. The backup is %s" % [_slot, backup], COL_WARN)


## Copies the slot's file into BACKUP_DIR. Returns the backup's path, or "" if it failed.
func _backup(slot: int) -> String:
	DirAccess.make_dir_recursive_absolute(BACKUP_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var to := BACKUP_DIR + "slot_%d_%s.json" % [slot, stamp]
	var from := SaveManager.SAVE_DIR + "slot_%d.json" % slot
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to)) != OK:
		return ""
	return to


func _revert() -> void:
	if _slot >= 0:
		_open_slot(_slot)
		_set_status("Reloaded slot %d from disk." % _slot, COL_DIM)


# ---------- OVERVIEW: credits, rank, ending, tower ----------
func _overview_tab() -> Control:
	var box := _tab_box("OVERVIEW")
	var col: VBoxContainer = box.get_meta(&"col")

	col.add_child(_label("CREDITS", 18, ACCENT))
	var cr_row := HBoxContainer.new()
	cr_row.add_theme_constant_override("separation", 8)
	var spin := SpinBox.new()
	spin.max_value = 100000000
	spin.step = 1
	spin.value = SaveEdit.credits(_data)
	spin.custom_minimum_size.x = 200
	spin.value_changed.connect(func(v: float) -> void:
		SaveEdit.set_credits(_data, int(v))
		_changed("credits %d" % int(v)))
	cr_row.add_child(spin)
	for add in [1000, 10000, 100000]:
		var b := _button("+%d" % add, 15)
		b.pressed.connect(func() -> void: spin.value += add)
		cr_row.add_child(b)
	var zero := _button("0", 15)
	zero.pressed.connect(func() -> void: spin.value = 0)
	cr_row.add_child(zero)
	col.add_child(cr_row)

	col.add_child(_label("RANK", 18, ACCENT))
	var rank := OptionButton.new()
	_style(rank, 16)
	for r in Ranks.LADDER:
		rank.add_item(r["name"])
	rank.selected = SaveEdit.rank_index(_data)
	rank.item_selected.connect(func(i: int) -> void:
		SaveEdit.set_rank(_data, i, _catalog)
		_changed("rank %s" % Ranks.LADDER[i]["name"])
		_refresh())
	col.add_child(rank)
	col.add_child(_note("Completes every exam up to the rank with a DISTINCTION and un-starts the ones above."))

	col.add_child(_label("ENDING", 18, ACCENT))
	var ending := OptionButton.new()
	_style(ending, 16)
	var ids := [""] + Endings.IDS
	for id in ids:
		ending.add_item("NONE (not chosen yet)" if id == "" else str(id).to_upper())
	ending.selected = maxi(ids.find(SaveEdit.ending(_data)), 0)
	ending.item_selected.connect(func(i: int) -> void:
		SaveEdit.set_ending(_data, ids[i])
		_changed("ending %s" % (ids[i] if ids[i] != "" else "none")))
	col.add_child(ending)
	col.add_child(_note("The ending opens The Recursion and changes the Core. It doesn't complete the Root Process: set that on the QUESTS tab if you need it."))

	col.add_child(_label("THE RECURSION: HIGHEST FLOOR CLEARED", 18, ACCENT))
	var tower := SpinBox.new()
	tower.max_value = Tower.FLOORS
	tower.value = SaveEdit.tower_cleared(_data)
	tower.custom_minimum_size.x = 200
	tower.value_changed.connect(func(v: float) -> void:
		SaveEdit.set_tower_cleared(_data, int(v))
		_changed("tower floor %d" % int(v)))
	col.add_child(tower)
	col.add_child(_note("0 = none. Floors above the next one lose their rolls and roll again when they're revealed."))
	return box


# ---------- QUESTS ----------
func _quests_tab() -> Control:
	var box := _tab_box("QUESTS")
	var col: VBoxContainer = box.get_meta(&"col")
	col.add_child(_note("Setting a quest doesn't give its rewards (credits, items, keys) or start the quests after it. Keys are on the KEYS tab."))
	var bulk := HBoxContainer.new()
	bulk.add_theme_constant_override("separation", 8)
	var done_all := _button("COMPLETE ALL", 15)
	done_all.pressed.connect(_set_all_quests.bind(SaveEdit.QuestStatus.COMPLETED))
	bulk.add_child(done_all)
	var reset_all := _button("RESET ALL", 15)
	reset_all.pressed.connect(_set_all_quests.bind(SaveEdit.QuestStatus.NOT_STARTED))
	bulk.add_child(reset_all)
	col.add_child(bulk)
	var by_act := SaveEdit.quests_by_act(_catalog)
	var acts: Array = by_act.keys()
	acts.sort_custom(func(a: int, b: int) -> bool: return (a if a > 0 else 99) < (b if b > 0 else 99))   # OTHER last
	for act in acts:
		var defs: Array[QuestDefinition] = []
		defs.assign(by_act[act])
		var done := defs.filter(func(d: QuestDefinition) -> bool:
			return SaveEdit.quest_status(_data, d.id) == SaveEdit.QuestStatus.COMPLETED).size()
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var spacer := Control.new()
		spacer.custom_minimum_size.y = 6
		col.add_child(spacer)
		var title := _label("%s   (%d / %d completed)" % [SaveEdit.ACT_TITLES.get(act, "ACT %d" % act), done, defs.size()], 18,
				COL_OK if done == defs.size() else ACCENT)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var done_act := _button("COMPLETE ACT", 14)
		done_act.pressed.connect(_set_act_quests.bind(act, SaveEdit.QuestStatus.COMPLETED))
		head.add_child(done_act)
		var reset_act := _button("RESET ACT", 14)
		reset_act.pressed.connect(_set_act_quests.bind(act, SaveEdit.QuestStatus.NOT_STARTED))
		head.add_child(reset_act)
		col.add_child(head)
		var line := ColorRect.new()
		line.color = Color(ACCENT, 0.3)
		line.custom_minimum_size = Vector2(0, 1)
		col.add_child(line)
		for def in defs:
			_quest_row(col, def)
	return box


## One quest: its title and id, and its state to pick.
func _quest_row(col: VBoxContainer, def: QuestDefinition) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var st := SaveEdit.quest_status(_data, def.id)
	var name_l := _label("   %s   %s" % [def.title, def.id], 16,
			COL_OK if st == SaveEdit.QuestStatus.COMPLETED else ACCENT if st != SaveEdit.QuestStatus.NOT_STARTED else COL_DIM)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	row.add_child(name_l)
	var opt := OptionButton.new()
	_style(opt, 14)
	for s in SaveEdit.STATUS_NAMES:
		opt.add_item(s)
	opt.selected = st
	opt.custom_minimum_size.x = 230
	opt.item_selected.connect(func(i: int) -> void:
		SaveEdit.set_quest_status(_data, def, i)
		_changed("%s %s" % [def.id, SaveEdit.STATUS_NAMES[i].to_lower()])
		_refresh())
	row.add_child(opt)
	col.add_child(row)


## COMPLETE ACT / RESET ACT: every quest of one act (SaveEdit.QUEST_ACTS).
func _set_act_quests(act: int, status: SaveEdit.QuestStatus) -> void:
	var defs: Array[QuestDefinition] = []
	defs.assign(SaveEdit.quests_by_act(_catalog).get(act, []))
	SaveEdit.set_all_quests(_data, defs, status)
	_changed("%s quests %s" % [SaveEdit.ACT_TITLES.get(act, "act %d" % act).split("  //")[0].to_lower(),
			SaveEdit.STATUS_NAMES[status].to_lower()])
	_refresh()


func _set_all_quests(status: SaveEdit.QuestStatus) -> void:
	SaveEdit.set_all_quests(_data, _catalog, status)
	_changed("every quest %s" % SaveEdit.STATUS_NAMES[status].to_lower())
	_refresh()


# ---------- KEYS ----------
func _keys_tab() -> Control:
	var box := _tab_box("KEYS")
	var col: VBoxContainer = box.get_meta(&"col")
	col.add_child(_note("Quest items and keys the character has recovered. Keys open sealed portals (the Stack Trace's stack_road, the Kernel's kernel_road...)."))
	var ids: Array = QuestItems.ITEMS.keys()
	ids.sort()
	for id in ids:
		var cb := CheckBox.new()
		_style(cb, 15)
		var info: Dictionary = QuestItems.ITEMS[id]
		cb.text = "%s   (%s)%s" % [str(info.get("name", id)), id,
				("   opens " + str(info["opens"])) if info.has("opens") else ""]
		cb.button_pressed = SaveEdit.has_key(_data, id)
		cb.toggled.connect(func(on: bool) -> void:
			SaveEdit.set_key(_data, id, on)
			_changed("%s %s" % [id, "on" if on else "off"]))
		col.add_child(cb)
	return box


# ---------- WAYPOINTS ----------
func _waypoints_tab() -> Control:
	var box := _tab_box("WAYPOINTS")
	var col: VBoxContainer = box.get_meta(&"col")
	col.add_child(_note("Discovered waypoints can be travelled to from the map (U). Checking a dungeon also gives its clear reward (+script points) and its boss kill (+knob steps); unchecking takes them back. Convoy stops also have ROUTE CLEARED, which opens the next stop on the route terminal."))
	for act in Waypoints.acts():
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var t := _label("%s  %s" % [act.title, act.subtitle], 18, ACCENT)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var all := _button("ALL", 14)
		all.pressed.connect(_set_act.bind(act, true))
		head.add_child(all)
		var none := _button("NONE", 14)
		none.pressed.connect(_set_act.bind(act, false))
		head.add_child(none)
		col.add_child(head)
		for w in act.waypoints:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 16)
			var cb := CheckBox.new()
			_style(cb, 15)
			var bosses := PackedStringArray()
			for b in SaveEdit.area_bosses(w):
				bosses.append(str(b).capitalize())
			cb.text = "%s%s%s" % [w.display_name, ("   (level %d)" % w.dungeon_level) if w.dungeon_level > 0 else "   (town)",
					("   boss: " + ", ".join(bosses)) if not bosses.is_empty() else ""]
			cb.button_pressed = SaveEdit.has_waypoint(_data, w.id)
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cb.toggled.connect(func(on: bool) -> void:
				SaveEdit.set_waypoint_with_rewards(_data, w, on)
				_changed("waypoint %s %s" % [w.id, "on" if on else "off"]))
			row.add_child(cb)
			if Waypoints.is_convoy_stop(w):
				var rc := CheckBox.new()
				_style(rc, 14)
				rc.text = "ROUTE CLEARED"
				rc.button_pressed = SaveEdit.has_route_cleared(_data, w.id)
				rc.toggled.connect(func(on: bool) -> void:
					SaveEdit.set_route_cleared(_data, w.id, on)
					_changed("route %s %s" % [w.id, "cleared" if on else "not cleared"]))
				row.add_child(rc)
			col.add_child(row)
	return box


func _set_act(act: WaypointAct, on: bool) -> void:
	for w in act.waypoints:
		SaveEdit.set_waypoint_with_rewards(_data, w, on)
		if Waypoints.is_convoy_stop(w):
			SaveEdit.set_route_cleared(_data, w.id, on)
	_changed("%s waypoints %s" % [act.title, "all" if on else "none"])
	_refresh()


# ---------- BUILDING ----------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.09)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	_title = _label("SAVE EDITOR", 30, ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_revert_btn = _button("REVERT", 18)
	_revert_btn.pressed.connect(_revert)
	head.add_child(_revert_btn)
	_save_btn = _button("SAVE", 18)
	_save_btn.pressed.connect(_save)
	head.add_child(_save_btn)
	var quit := _button("QUIT", 18)
	quit.pressed.connect(func() -> void: get_tree().quit())
	head.add_child(quit)
	_status = _label("", 16, COL_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 1.0
	col.add_child(_status)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var left := ScrollContainer.new()
	left.custom_minimum_size.x = 330
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(left)
	_slots = VBoxContainer.new()
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots.add_theme_constant_override("separation", 6)
	left.add_child(_slots)
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _font:
		_tabs.add_theme_font_override("font", _font)
	_tabs.add_theme_font_size_override("font_size", 17)
	body.add_child(_tabs)


## A scrolling tab page; its content column is meta "col".
func _tab_box(tab_name: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)
	scroll.set_meta(&"col", col)
	return scroll


func _set_status(text: String, c: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", c)


func _label(text: String, fsize: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", c)
	return l


func _note(text: String) -> Label:
	var l := _label(text, 14, Color(COL_DIM, 0.85))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1.0
	return l


func _button(text: String, fsize: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	_style(b, fsize)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.08, 0.12, 0.9) if state != "hover" else Color(0.0, 0.25, 0.32, 0.95)
		sb.border_color = Color(ACCENT, 0.25 if state == "disabled" else 0.7)
		sb.set_border_width_all(2)
		sb.set_content_margin_all(8)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", ACCENT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(ACCENT, 0.3))
	return b


func _style(c: Control, fsize: int) -> void:
	if _font:
		c.add_theme_font_override("font", _font)
	c.add_theme_font_size_override("font_size", fsize)
	c.add_theme_color_override("font_color", COL_TEXT)
