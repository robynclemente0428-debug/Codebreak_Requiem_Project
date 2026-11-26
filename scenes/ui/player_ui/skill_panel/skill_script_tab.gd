class_name SkillScriptTab
extends VBoxContainer
## The SCRIPTING tab of the skills menu (SkillPanel), styled like a small code editor.
## Players build a SkillProgram by dragging snippets into the code; nothing is typed.
##
##  - EXPLORER (left): one "file" per socketed skill and per scriptable support. A skill and its
##                     supports share one point budget, so they are checked together.
##  - EDITOR (middle): one file at a time, in tabs above the code like a code editor: the
##                     skill's file, then each scriptable support, then routines.gd (Engineer).
##                     Click a tab (or the file in EXPLORER) to open it: its knobs in SNIPPETS,
##                     clear() acts on it. While dragging a line or snippet, hover a tab to open
##                     that file and drop it there. A tab shows * when unsaved, ! with errors.
##                     Each file's rules, with line numbers:
##                         always:
##                     +       damage += 20%          # costs 8.0
##                     -       attack_speed -= 20%    # pays 10.0
##                         when enemies_nearby(3, 4.0m):   # buffs x0.60
##                     +       range_bonus += 1.00m   # costs 8.0
##                     Loops repeat the skill. A loop's if blocks come after its cast(), checked
##                     each time a cast or repeat lands, and may end in break:
##                         when every_nth_cast(3):
##                     +       for i in range(2):         # 2 repeats, costs 3.6
##                                 cast()
##                                 if hit_nothing:
##                     -               break
##                     The +/- in the gutter marks buffs (cost points) and drawbacks (pay points).
##                     Numbers are buttons: click = up, right-click = down, mouse wheel = both.
##                     Drag a line onto another rule to move it, or onto SNIPPETS to delete it.
##                     Right-click a line to delete it. Click a line to select its rule.
##  - SNIPPETS (right): conditions and the selected file's knobs. Drag one into the editor, or
##                     click it to add it to the selected rule (or start a new rule).
##                     The registry comes as pieces: registry.add / remove(target), target in /
##                     not in registry, registry.size and the compare operators.
##                     "if" (Architect) nests a block in a rule: its header takes conditions, its
##                     lines sit one step further in, and drops on any of its lines go into it.
##                     Dropped on a line they fit, they change it; anywhere else they add a whole line.
##                     Two tabs: OFFENSE (damage, reach, loops, the gem blocks) and DEFENSE
##                     (staying alive: my_life_below, hit_recently, leech, barrier, guard...).
##  - OUTPUT (bottom): two tabs. OUTPUT: points, budget, blocks, tier and whether it runs.
##                     ERRORS (n): the compile errors and their fixes. It opens by itself when
##                     an error appears, and OUTPUT comes back once the script compiles.
##                     apply() runs the program.
##  - SET A / B / C (top right): the script sets. Each skill keeps one program per set and the
##                     script_set key swaps them all in the field (SkillComponent.switch_script_set).
##                     Sets start empty; on an empty set, copy_from(A) copies another set into it.
##                     rename() (or double-clicking a set) renames the current set ("SWARM", "BOSS"...).
##                     Sets past the player's rank aren't shown (Ranks.PERKS: B at OPERATOR, C at STRATEGIST),
##                     nor are blocks above it (Ranks.LOCKED_BLOCKS: loops need ARCHITECT).
##  - save_as() / load() (OUTPUT, rank ARCHITECT): the script library (SkillComponent.library).
##  - routines.gd (rank ENGINEER): the character's routines (ProgramRoutine), one more file in the
##                     editor and EXPLORER, shared by every skill. Each is "def name():" and its lines
##                     (knobs, registry writes, one level of if); no conditions or loops of its own.
##                     call name() (SNIPPETS, "routines") runs one from a rule: one block, and the
##                     skill pays for its lines. Click a call's name to switch routine, a routine's
##                     name to rename it. Routine edits are a draft too: apply() saves them for
##                     every skill, revert() drops them.
##  - guide() (top of the editor): the SCRIPTING GUIDE (ScriptGuide), laid over the tab: rules,
##                     always / when, blocks, knobs, points, discounts, with this skill's numbers.
##
## The panes are resizable: drag the bars between EXPLORER, the editor and SNIPPETS, and between
## the editor and OUTPUT. The sizes are saved (Settings "layout/script_panes"), so they stay as
## you left them, after a restart too.
##
## Edits are a draft until apply(). Built in code like the rest of SkillPanel, using its styling.

# Syntax colours
const COL_KEYWORD := Color(0.82, 0.55, 1.0)     # always / when / and / pass
const COL_FN := Color(1.0, 0.80, 0.40)          # condition calls
const COL_VAR := Color(0.45, 0.82, 1.0)         # knobs
const COL_NUM := Color(1.0, 0.62, 0.35)         # editable numbers
const COL_OP := Color(0.80, 0.86, 0.90)         # += -= ( ) :
const COL_COMMENT := Color(0.42, 0.58, 0.55)
const COL_GEM := Color(1.0, 0.50, 0.78)         # blocks a socketed support gem adds
const COL_GUTTER := Color(0.35, 0.48, 0.55)
const COL_BUFF := Color(0.30, 0.95, 0.60)       # gutter "+": costs points
const COL_DRAW := Color(1.0, 0.45, 0.45)        # gutter "-": pays points
const COL_OK := Color(0.30, 0.95, 0.60)
const COL_PENDING := Color(1.0, 0.85, 0.35)
const COL_VIOLET := Color(0.72, 0.42, 1.0)       # MERGE's violet rule slot
const COL_NEW := Color(1.0, 0.86, 0.25)         # the NEW badge on a snippet a rank just unlocked (NewBlocks)
const CODE_SIZE := 13
## Hints: every control here sets plain tooltip_text; ScriptTooltip shows it formatted (a title,
## coloured ERROR / FIX / COST / TIP / LOOP / HOW tags, code in the editor's colours).
var _hint: ScriptTooltip

## Set by SkillPanel before build().
var panel: SkillPanel

var _socket := -1
var _owner := ""                  # "" = the skill itself, otherwise a support gem's id
var _drafts: Dictionary = {}      # socket index -> SkillProgram being edited
var _selected: ProgramRule
var _rebuild_queued := false
var _line_no := 0
## "applied", "pending" (valid but not applied), "invalid" or "" (nothing to apply).
var _state := ""

var _gem_list: VBoxContainer
var _title: Label
var _rules_box: VBoxContainer
var _palette_box: VBoxContainer
var _console: RichTextLabel
var _output_frame: PanelContainer
var _errors_console: RichTextLabel
var _console_scroll: ScrollContainer  # OUTPUT's text: fills the pane, scrolls when it's small
var _errors_scroll: ScrollContainer   # ERRORS' text, likewise
# Resizable panes: where the player left each bar is saved in Settings "layout/script_panes"
var _splits := {}                      # "explorer" / "snippets" / "output" -> its SplitContainer
var _out_tab := "output"           # "output" or "errors": which console OUTPUT shows
var _out_tab_btns := {}            # tab name -> its button
var _last_errors := 0              # error count at the last update (more = open ERRORS)
## Check result for the open socket's draft, made at the start of each rebuild so the editor
## can mark the lines with errors while it draws them.
var _validation: ProgramValidation
var _issue_line: Dictionary = {}  # index in _validation.issues -> editor line number
# For the tutorial hints: the controls they can outline
var _rule_line: Dictionary = {}    # ProgramRule -> its first editor line
var _snippets: Dictionary = {}     # "cond:<type id>" / "knob:<knob id>" -> snippet in SNIPPETS
var _skill_file_btn: Dictionary = {}  # socket -> the skill's file button in the explorer
var _kernel_file_btn: Button           # kernel.gd's file button in the explorer (Act V), for the tutorial
var _effect_num: Dictionary = {}   # ProgramEffect -> its editable number
var _new_rule_ctrl: Control        # the "drop a snippet here to start a new rule" line
var _cond_nums: Dictionary = {}    # ProgramCondition -> [its editable numbers]
var _apply_btn: Button
var _revert_btn: Button
var _clear_btn: Button
var _set_btns: Array[Button] = []
var _copy_btns: Array[Button] = []  # copy_from(<set>): shown while the current set is empty
var _rename_edit: LineEdit         # takes a set button's place while it is being renamed
var _renaming := -1
var _rename_btn: Button            # rename(): renames the current set
var _palette_tab := "offense"      # "offense" or "defense": which snippets are listed
var _pal_into: Container           # the SNIPPETS section being filled (null = the list itself)
var _tab_btns := {}                # tab name -> its button
var _set_note: Label              # why a set didn't swap
# Script library (rank ARCHITECT): save_as() names the draft, load() lists the saved ones
var _save_edit: LineEdit
var _save_btn: Button
var _load_btn: Button
var _library_box: VBoxContainer   # under OUTPUT's buttons while load() is open
var _library_open := false
var _set_hooked: SkillComponent   # the SkillComponent whose script_set_changed we listen to
# The open file's code; the file tabs above it (one per file of the skill)
var _editor_scroll: ScrollContainer
var _file_tabs: HFlowContainer
# The SCRIPTING GUIDE (ScriptGuide), laid over the tab by guide()
var _guide: ScriptGuide
var _guide_btn: Button
# One-line tips in OUTPUT, the first time the player runs into an idea (ScriptTips)
var _tip_row: HBoxContainer
var _tip_label: Label
var _tip_page_btn: Button
var _tip_shown: Dictionary = {}    # {id, text, page} on screen now, {} for none
var _tip_hold := false             # apply() just showed one: the rebuild after it keeps it
# Routines (rank ENGINEER): routines.gd, edited as a draft like a script (ProgramRoutine.OWNER)
const ROUTINES_FILE := "@routines"
## kernel.gd (Act V, KernelScript): root lines about the zone, not a skill. Edits apply at once.
const KERNEL_FILE := "@kernel"
const COL_KERNEL := Color(1.0, 0.85, 0.4)
var _routine_draft: Array = []      # copies of SkillComponent.routines while editing ([] = not made yet)
var _routine_rename := -1           # the routine whose name box is open
var _routine_version := -1          # SkillComponent.routines_version the copy was made from


# ---------- BUILDING ----------
func build() -> void:
	add_theme_constant_override("separation", 6)
	_hint = ScriptTooltip.new()
	add_child(_hint)
	_hint.setup(self, panel._font, roundi(_sz(13) * panel.font_scale), panel.accent)

	# EXPLORER | (editor | SNIPPETS), each bar draggable
	var body := _split(false, "explorer", 40.0 * _k())
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var rest := _split(false, "snippets", -30.0 * _k())
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Left: explorer
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 110.0 * _k()
	body.add_child(left)
	body.add_child(rest)
	left.add_child(panel._label("EXPLORER", _sz(13), SkillPanel.COL_DIM))
	var left_scroll := _scroll()
	left.add_child(left_scroll)
	_gem_list = VBoxContainer.new()
	_gem_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gem_list.add_theme_constant_override("separation", 1)
	left_scroll.add_child(_gem_list)

	# Middle: editor + output
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.custom_minimum_size.x = 320.0 * _k()
	mid.add_theme_constant_override("separation", 6)
	rest.add_child(mid)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	mid.add_child(head)
	_title = panel._label("", _sz(14), panel.accent)
	_shrinkable(_title)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_guide_btn = _code_button("guide()", "The SCRIPTING GUIDE: rules, always and when, blocks, knobs, points and discounts.")
	_guide_btn.pressed.connect(toggle_guide)
	head.add_child(_guide_btn)
	_set_note = panel._label("", _sz(11), COL_DRAW)
	head.add_child(_set_note)
	for i in SkillComponent.SCRIPT_SETS:
		var c := _code_button("copy_from(%s)" % SkillComponent.SET_NAMES[i], "")
		c.pressed.connect(_copy_set.bind(i))
		c.visible = false
		head.add_child(c)
		_copy_btns.append(c)
	for i in SkillComponent.SCRIPT_SETS:
		var b := _code_button("SET %s" % SkillComponent.SET_NAMES[i], "")
		b.pressed.connect(_pick_set.bind(i))
		b.gui_input.connect(_on_set_button_input.bind(i))
		head.add_child(b)
		_set_btns.append(b)
	_rename_edit = _name_edit(SkillComponent.SET_NAME_MAX, "NAME")
	_rename_edit.text_submitted.connect(func(_t: String) -> void: _finish_rename())
	_rename_edit.focus_exited.connect(_finish_rename)
	head.add_child(_rename_edit)
	_rename_btn = _code_button("rename()", "Rename the current script set (\"SWARM\", \"BOSS\"...). "
			+ "Enter to save. You can also double-click a set.")
	_rename_btn.pressed.connect(func() -> void: _start_rename(_skills().script_set))
	head.add_child(_rename_btn)
	# editor / OUTPUT, the bar between them draggable
	_file_tabs = HFlowContainer.new()
	_file_tabs.add_theme_constant_override("h_separation", 2)
	_file_tabs.add_theme_constant_override("v_separation", 2)
	mid.add_child(_file_tabs)
	var rows := _split(true, "output", -90.0 * _k())
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(rows)
	var editor := PanelContainer.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.custom_minimum_size.y = 100.0 * _k()
	editor.add_theme_stylebox_override("panel", _box_style(Color(0.0, 0.02, 0.04, 0.6), Color(panel.accent, 0.3)))
	rows.add_child(editor)
	var mid_scroll := _scroll()
	mid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO   # long lines scroll when narrow
	panel._style_scrollbar(mid_scroll.get_h_scroll_bar())
	mid_scroll.get_h_scroll_bar().custom_minimum_size = Vector2(0, 8)   # styled for vertical bars
	_editor_scroll = mid_scroll
	editor.add_child(mid_scroll)
	_rules_box = VBoxContainer.new()
	_rules_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_box.add_theme_constant_override("separation", 0)
	mid_scroll.add_child(_rules_box)
	rows.add_child(_build_output())

	# Right: snippets. Dropping a code line here deletes it.
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 170.0 * _k()
	rest.add_child(right)
	right.add_child(panel._label("SNIPPETS", _sz(13), SkillPanel.COL_DIM))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	right.add_child(tabs)
	for tab_name in ["offense", "defense"]:
		var tb := _code_button(tab_name.to_upper(), "Damage, reach, loops and the gem blocks." if tab_name == "offense"
				else "Staying alive: life and hit conditions, leech, barrier, guard and defensive supports.")
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(_set_palette_tab.bind(tab_name))
		tabs.add_child(tb)
		_tab_btns[tab_name] = tb
	var right_scroll := _scroll()
	right.add_child(right_scroll)
	_palette_box = VBoxContainer.new()
	_palette_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette_box.add_theme_constant_override("separation", 2)
	# The scroll bar is drawn over the list's right edge: keep the snippets' numbers clear of it
	var pal_pad := MarginContainer.new()
	pal_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pal_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pal_pad.mouse_filter = Control.MOUSE_FILTER_PASS
	pal_pad.add_theme_constant_override("margin_right", roundi(12.0 * _k()))
	pal_pad.add_child(_palette_box)
	right_scroll.add_child(pal_pad)
	pal_pad.set_drag_forwarding(Callable(), _can_drop_on_palette, _drop_on_palette)
	right_scroll.set_drag_forwarding(Callable(), _can_drop_on_palette, _drop_on_palette)
	_palette_box.set_drag_forwarding(Callable(), _can_drop_on_palette, _drop_on_palette)

	var hint := panel._label("// DRAG SNIPPETS INTO THE CODE  |  DRAG A LINE OUT OR RIGHT-CLICK IT: DELETE  |  NUMBERS: CLICK UP, RIGHT-CLICK DOWN",
		_sz(11), COL_COMMENT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 1.0
	add_child(hint)


## A draggable split. `key` remembers where the player left its bar; `default_offset` is where
## it starts (from the side that doesn't expand: + grows the first pane, - the second).
func _split(vertical: bool, key: String, default_offset: float) -> SplitContainer:
	var s: SplitContainer = VSplitContainer.new() if vertical else HSplitContainer.new()
	s.add_theme_constant_override("separation", roundi(8.0 * _k()))
	s.add_theme_constant_override("minimum_grab_thickness", roundi(10.0 * _k()))
	s.add_theme_constant_override("autohide", 0)
	var bar := StyleBoxFlat.new()                      # a faint strip with a brighter centre line
	bar.bg_color = Color(panel.accent, 0.06)
	bar.border_color = Color(panel.accent, 0.35)
	if vertical:
		bar.content_margin_top = 0
		bar.border_width_top = 1
		bar.expand_margin_top = -roundi(4.0 * _k())
	else:
		bar.border_width_left = 1
		bar.expand_margin_left = -roundi(4.0 * _k())
	s.add_theme_stylebox_override("split_bar_background", bar)
	var saved: Dictionary = Settings.get_value("layout", "script_panes")
	s.split_offset = roundi(float(saved.get(key, default_offset)))
	s.dragged.connect(func(offset: int) -> void:
		var panes: Dictionary = (Settings.get_value("layout", "script_panes") as Dictionary).duplicate()
		panes[key] = offset
		Settings.set_value("layout", "script_panes", panes))
	_splits[key] = s
	return s


func _build_output() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box_style(Color(0, 0, 0, 0.5), Color(panel.accent, 0.3)))
	frame.custom_minimum_size.y = 70.0 * _k()       # the tabs and a line or two: drag the bar for more
	_output_frame = frame
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	frame.add_child(box)

	var head := HFlowContainer.new()               # wraps onto a second row when the pane is narrow
	head.add_theme_constant_override("h_separation", 6)
	head.add_theme_constant_override("v_separation", 4)
	box.add_child(head)
	for tab_name in ["output", "errors"]:
		var tb := _code_button(tab_name.to_upper(), "Points, budget, blocks and tier." if tab_name == "output"
				else "Compile errors and how to fix them.")
		tb.pressed.connect(_set_out_tab.bind(tab_name))
		head.add_child(tb)
		_out_tab_btns[tab_name] = tb
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	_apply_btn = _code_button("apply()", "Run this program on the skill.")
	_apply_btn.pressed.connect(_apply)
	head.add_child(_apply_btn)
	_revert_btn = _code_button("revert()", "Throw away changes since the last apply().")
	_revert_btn.pressed.connect(_revert)
	head.add_child(_revert_btn)
	_clear_btn = _code_button("clear()", "Delete every rule in this file.")
	_clear_btn.pressed.connect(_clear_gem)
	head.add_child(_clear_btn)
	_save_edit = _name_edit(SkillComponent.LIBRARY_NAME_MAX, "SCRIPT NAME")
	_save_edit.text_submitted.connect(func(_t: String) -> void: _finish_save(true))
	_save_edit.focus_exited.connect(_finish_save.bind(false))
	head.add_child(_save_edit)
	_save_btn = _code_button("save_as()", "")
	_save_btn.pressed.connect(_start_save)
	head.add_child(_save_btn)
	_load_btn = _code_button("load()", "")
	_load_btn.pressed.connect(_toggle_library)
	head.add_child(_load_btn)
	box.add_child(_build_tip_row())
	_library_box = VBoxContainer.new()
	_library_box.visible = false
	_library_box.add_theme_constant_override("separation", 2)
	box.add_child(_library_box)

	_console = RichTextLabel.new()
	_console.bbcode_enabled = true
	_console.fit_content = true
	_console.scroll_active = false
	_console.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_console.custom_minimum_size.x = 1.0
	_console.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if panel._font:
		_console.add_theme_font_override("normal_font", panel._font)
	_console.add_theme_font_size_override("normal_font_size", roundi(_sz(12) * panel.font_scale))
	_console.add_theme_color_override("default_color", SkillPanel.COL_TEXT)
	_console.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_errors_console = _console.duplicate() as RichTextLabel
	_console_scroll = _scroll()
	_console_scroll.add_child(_console)
	box.add_child(_console_scroll)
	_errors_scroll = _scroll()
	_errors_scroll.visible = false
	_errors_scroll.add_child(_errors_console)
	box.add_child(_errors_scroll)
	_update_out_tabs(0)
	return frame


func _set_out_tab(tab_name: String) -> void:
	_out_tab = tab_name
	_update_out_tabs(_last_errors)


## Shows the chosen console and styles the tab buttons: "ERRORS (2)" turns red while there are any.
func _update_out_tabs(errors: int) -> void:
	if _errors_console == null:
		return
	_console_scroll.visible = _out_tab == "output"
	_errors_scroll.visible = _out_tab == "errors"
	for tab_name in _out_tab_btns:
		var b: Button = _out_tab_btns[tab_name]
		var active: bool = tab_name == _out_tab
		var col: Color = panel.accent
		if tab_name == "errors":
			b.text = "ERRORS (%d)" % errors if errors > 0 else "ERRORS"
			if errors > 0:
				col = SkillPanel.COL_WARN
		var dim := Color(col, 0.6) if col != panel.accent else COL_GUTTER
		b.add_theme_color_override("font_color", col if active else dim)
		var st := (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
		st.border_color = col if active else Color(dim, 0.4)
		st.bg_color = Color(col, 0.15) if active else Color(0, 0, 0, 0)
		b.add_theme_stylebox_override("normal", st)


func _scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel._style_scrollbar(s.get_v_scroll_bar())
	return s


# ---------- STATE ----------
func _skills() -> SkillComponent:
	return panel._skills


func _sock() -> SkillComponent.Socket:
	var sk := _skills()
	if sk == null or _socket < 0 or _socket >= sk.sockets.size():
		return null
	return sk.sockets[_socket]


func _limits() -> SkillProgramLimits:
	return _skills().program_limits_for(_socket) if _sock() != null else null


## The program being edited for the current socket. Starts as a copy of the one in this set,
## running or not: one that doesn't fit right now opens with its errors, never as a blank file
## (applying a blank file would delete it).
func _draft() -> SkillProgram:
	if not _drafts.has(_socket):
		var stored := _skills().stored_program(_socket)
		_drafts[_socket] = stored.duplicate_program() if stored != null else SkillProgram.new()
	return _drafts[_socket]


func _support_ids(s: SkillComponent.Socket) -> Array:
	var ids: Array = []
	for item in s.supports:
		ids.append(item.definition.support_gem.id)
	return ids


## True when the socket's draft differs from what is kept in this set (an unsaved file).
func _is_dirty(socket: int) -> bool:
	if not _drafts.has(socket):
		return false
	var applied := _skills().stored_program(socket)
	var applied_json := JSON.stringify(applied.to_dict() if applied != null else {"rules": []})
	return JSON.stringify((_drafts[socket] as SkillProgram).to_dict()) != applied_json


## Forgets the copy of routines.gd when the character's routines were replaced since it was made
## (Sudo's sandbox takes them away and gives them back). An old copy applied later would wipe them.
func _drop_stale_routines() -> void:
	var sk := _skills()
	if not _routine_draft.is_empty() and (sk == null or sk.routines_version != _routine_version):
		_routine_draft.clear()
		_routine_rename = -1


## The routines being edited: copies of the character's, made on first use, all three slots.
func _routines() -> Array:
	_drop_stale_routines()
	if _routine_draft.is_empty():
		var sk := _skills()
		_routine_version = sk.routines_version if sk != null else -1
		for i in ProgramRoutine.MAX_ROUTINES:
			var have: ProgramRoutine = sk.routines[i] if sk != null and i < sk.routines.size() else null
			_routine_draft.append(have.duplicate_routine() if have != null else ProgramRoutine.make(i))
	return _routine_draft


## True when the routines were edited since they were last applied.
func _routines_dirty() -> bool:
	_drop_stale_routines()
	if _routine_draft.is_empty():
		return false
	var sk := _skills()
	for i in _routine_draft.size():
		var have: ProgramRoutine = sk.routines[i] if i < sk.routines.size() else ProgramRoutine.make(i)
		if JSON.stringify((_routine_draft[i] as ProgramRoutine).to_dict()) != JSON.stringify(have.to_dict()):
			return true
	return false


## True when the player's rank has routines (Engineer, or lent in Sudo's sandbox).
func _routines_unlocked() -> bool:
	var limits := _limits()
	return limits != null and limits.allows("call")


## kernel.gd shows once the Executor reaches the Core (KernelScript.unlocked).
func _kernel_unlocked() -> bool:
	return KernelScript.unlocked(_kernel_qm())


func _kernel_qm() -> QuestManager:
	var sk := _skills()
	var player := sk.get_parent() if sk != null else null
	return player.get("quests") as QuestManager if player != null else null


## kernel.gd, open: a READ-ONLY record of the Null's pull requests (KernelScript). What runs, by
## trigger (your root lines gold, the Null's merged lines violet), then each request's answer.
##   when enemy_spotted:
##       registry.add(target)        # root: the Null's gift (merged)
##     N target.armour += 40%        # the Null's, merged on The Stack Trace
##   # overwritten on Sentinel's Hall: when life_below(50%): mana.drain(25%)
func _kernel_lines() -> void:
	var qm := _kernel_qm()
	var lines: Array = Array(_skills().kernel)
	var running := KernelScript.null_running(qm)
	var editable := Endings.kernel_editable(qm)
	if editable:
		_comment_line("# kernel.gd: yours. You patched AXIOM: up to %d root lines, any you like, and the Null's never run." % Endings.MAX_ROOT_LINES)
		_comment_line("# these lines run on the zone, whatever you cast, in every dungeon")
	else:
		_comment_line("# kernel.gd: read only. The Null asks on every floor down; your answers are written here.")
		_comment_line("# these lines run on the zone, whatever you cast: %s" % (
			"in every dungeon (merged)" if Endings.runs_everywhere(qm) else "every Act V zone past the Core"))
	var any := false
	for trigger in KernelScript.TRIGGERS:
		var mine: Array = lines.filter(func(id: String) -> bool: return KernelScript.LINES.has(id) and KernelScript.LINES[id]["trigger"] == trigger)
		var theirs: Array = running.filter(func(id: String) -> bool: return KernelScript.NULL_LINES[id]["trigger"] == trigger)
		if mine.is_empty() and theirs.is_empty():
			continue
		any = true
		_blank_line(null)
		var head := _code_line(null)
		(head[1] as HBoxContainer).add_child(_tok("when ", COL_KEYWORD))
		(head[1] as HBoxContainer).add_child(_tok(trigger, COL_FN))
		(head[1] as HBoxContainer).add_child(_tok(":", COL_OP))
		for id in mine:
			var parts := _code_line(null)
			var code: HBoxContainer = parts[1]
			code.add_child(_tok("    " + str(KernelScript.LINES[id]["code"]), COL_KERNEL))
			code.add_child(_comment_tok("root: " + _kernel_source(qm, id), str(KernelScript.LINES[id]["tip"])))
			if editable:
				var del := _code_button("del", "Take this line out of kernel.gd.")
				del.pressed.connect(func() -> void:
					_skills().kernel.erase(id)
					Coop.kernel_changed()
					panel._notify("KERNEL: LINE REMOVED")
					_queue_rebuild())
				code.add_child(del)
		for id in theirs:
			var parts := _code_line(null, "N", KernelScript.COL_NULL)
			var code: HBoxContainer = parts[1]
			code.add_child(_tok("    " + str(KernelScript.NULL_LINES[id]["code"]), KernelScript.COL_NULL))
			code.add_child(_comment_tok("the Null's, merged on " + _kernel_floor(id), str(KernelScript.NULL_LINES[id]["tip"])))
	var answered := false
	for id in KernelScript.NULL_LINES:
		var a := KernelScript.answer_of(qm, id)
		if a == "" or a == "merge":
			continue
		if not answered:
			_blank_line(null)
			answered = true
		_comment_line("# %s on %s: %s" % ["overwritten" if a == "overwrite" else "terminated", _kernel_floor(id), KernelScript.code_of(id)])
	if not any and not answered:
		_blank_line(null)
		_comment_line("# empty: the Null's first pull request waits in the Stack Trace.")


## Where a root line came from, for its comment: a merge's gift or an overwrite's pick (older saves
## may hold lines from before the pull requests: just "yours").
func _kernel_source(qm: QuestManager, line_id: String) -> String:
	for id in KernelScript.NULL_LINES:
		var a := KernelScript.answer_of(qm, id)
		if a == "merge" and KernelScript.NULL_LINES[id]["gift"] == line_id:
			return "the Null's gift (merged on %s)" % _kernel_floor(id)
		if a == "overwrite" and line_id in KernelScript.NULL_LINES[id]["offers"]:
			return "yours, over the Null's on %s" % _kernel_floor(id)
	return "yours"


func _kernel_floor(null_id: String) -> String:
	var w := Waypoints.for_scene("res://scenes/map/dungeon/%s.tscn" % KernelScript.NULL_LINES[null_id]["zone"])
	return w.display_name if w != null else str(KernelScript.NULL_LINES[null_id]["zone"])


## SNIPPETS while kernel.gd is open: what the answers mean. After OVERWRITE (Endings), every root
## line instead, to add by hand (up to Endings.MAX_ROOT_LINES, OVERWRITE's reward).
func _kernel_palette() -> void:
	var qm := _kernel_qm()
	if Endings.kernel_editable(qm):
		var lines: Array = Array(_skills().kernel)
		_pal_add(_comment_tok("root lines  (%d/%d)" % [lines.size(), Endings.MAX_ROOT_LINES],
			"root lines\nYou patched AXIOM: kernel.gd is yours. Pick up to %d; they run in every dungeon, whatever you cast.\nNOTE: changes apply at once" % Endings.MAX_ROOT_LINES))
		for id in KernelScript.LINES:
			var d: Dictionary = KernelScript.LINES[id]
			var b := _code_button("when %s: %s" % [d["trigger"], d["code"]], str(d["tip"]))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if id in lines:
				b.disabled = true
				b.tooltip_text += "\nAlready in kernel.gd."
			elif lines.size() >= Endings.MAX_ROOT_LINES:
				b.disabled = true
				b.tooltip_text += "\nkernel.gd is full: take a line out first."
			b.pressed.connect(func() -> void:
				var now: Array[String] = _skills().kernel
				if not id in now and now.size() < Endings.MAX_ROOT_LINES:
					now.append(id)
					Coop.kernel_changed()
					panel._notify("KERNEL: LINE ADDED")
					_queue_rebuild())
			_pal_add(b)
		return
	_pal_add(_comment_tok("read only",
		"kernel.gd is a record\nOn every floor down, the Null submits a pull request: a line it wants to run on the Core.\n"
		+ "MERGE: its line runs, and it gives you a root line.\nOVERWRITE: yours runs instead.\n"
		+ "TERMINATE: neither runs, and a champion comes for you.\nThe answer you gave most is what your kernel leans toward."))
	for a in KernelScript.ANSWERS:
		_pal_add(_comment_tok("%s: %d" % [a, int(KernelScript.tally(_kernel_qm())[a])], ""))


## The file whose knobs a file's lines use: routines use the skill's own.
func _knob_owner(owner_id: String) -> String:
	return "" if owner_id == ROUTINES_FILE else owner_id


## The routine whose body `rule` is (null for a rule of the script).
func _routine_of(rule: ProgramRule) -> ProgramRoutine:
	if rule == null or rule.owner != ROUTINES_FILE:
		return null
	for r in _routines():
		if (r as ProgramRoutine).body == rule:
			return r
	return null


## The skill files whose script (draft, or applied) calls routine `index`, each with how much
## stronger its strongest call makes the routine's knobs ("strike.gd x1.75"), when it does.
func _routine_callers(index: int) -> Array:
	var out: Array = []
	var sk := _skills()
	var routines := _routines()
	var rt: ProgramRoutine = routines[index] if index < routines.size() else null
	for i in sk.sockets.size():
		var sock := sk.sockets[i]
		if sock.gem == null:
			continue
		var p: SkillProgram = _drafts[i] if _drafts.has(i) else sock.program
		if p == null or not (index in p.called_routines()):
			continue
		var text := _file_name(sock.gem.get_display_name())
		var limits := sk.program_limits_for(i)
		var top := 1.0
		if rt != null and not rt.is_empty() and limits != null:
			for r in p.rules:
				var calls := r.effects.filter(func(x: ProgramEffect) -> bool: return x.is_call() and x.op == index)
				if not calls.is_empty():
					top = maxf(top, float(_routine_here(rt, r, limits)["mult"]))
				for bi in r.branches.size():
					if r.branches[bi].effects.any(func(x: ProgramEffect) -> bool: return x.is_call() and x.op == index):
						top = maxf(top, float(_routine_here(rt, r.branch_rule(bi), limits)["mult"]))
		if not is_equal_approx(top, 1.0):
			text += " x%.2f" % top
		out.append(text)
	return out


## Opens the SCRIPTING GUIDE over the tab, on `page` ("" = the last one read), with the open
## skill's numbers (budget, blocks, rules, tiers).
func open_guide(page := "") -> void:
	if _guide == null:
		_guide = ScriptGuide.new()
		_guide.tab = self
		add_child(_guide)
		_guide.build()
	var limits := _limits()
	_guide.open(limits, _bonus_sources() if limits != null else "", page)


func toggle_guide() -> void:
	if guide_open():
		_guide.close()
	else:
		open_guide()


func guide_open() -> bool:
	return _guide != null and _guide.is_open()


## kernel.gd is the file open in the editor (the tutorial's KERNEL.GD lesson).
func kernel_open() -> bool:
	return _owner == KERNEL_FILE


## Called by SkillPanel when the tab is shown or the skills change.
## Controls the tutorial hints can outline (see SkillPanel.tutorial_target).
## ids: script_palette / palette, script_apply / apply, output, skill_file, kernel_file,
##      cond:<condition id>, knob:<knob id> (snippets), rule_line:<condition id>
func tutorial_target(id: String) -> Array[Control]:
	var out: Array[Control] = []
	match id:
		"script_palette", "palette":
			if _palette_box != null:
				out.append(_palette_box)
		"script_apply", "apply":
			if _apply_btn != null:
				out.append(_apply_btn)
		"output":
			if _output_frame != null:
				out.append(_output_frame)
		"guide":
			if guide_open():
				out.append(_guide)
		"guide_button":
			if _guide_btn != null:
				out.append(_guide_btn)
		"skill_file":
			if _skill_file_btn.has(_socket):
				out.append(_skill_file_btn[_socket])
		"kernel_file":
			if is_instance_valid(_kernel_file_btn) and _kernel_file_btn.is_visible_in_tree():
				out.append(_kernel_file_btn)
		"new_rule":
			if _new_rule_ctrl != null and is_instance_valid(_new_rule_ctrl):
				out.append(_new_rule_ctrl)
		"always_line":
			var always := _tutorial_always_rule()
			if always != null and _rule_line.has(always) and is_instance_valid(_rule_line[always]):
				out.append(_rule_line[always])
		_:
			var tab := _tab_of(id)
			if tab != "" and tab != _palette_tab:
				_palette_tab = tab                     # the hint points at a snippet on the other tab
				_build_palette()
			if _snippets.has(id) and is_instance_valid(_snippets[id]):
				_reveal(_snippets[id])                 # in a folded section: unfold it
				out.append(_snippets[id])
			elif id.begins_with("knob_number:"):        # knob_number:<condition id>:<knob id>
				var bits := id.split(":")
				var rule: ProgramRule = _tutorial_rule(bits[1]) if bits.size() == 3 else null
				if rule != null:
					for e in rule.effects:
						if String(e.knob) == bits[2] and _effect_num.has(e) and is_instance_valid(_effect_num[e]):
							out.append(_effect_num[e])
			elif id.begins_with("always_knob_number:"):  # always_knob_number:<knob id>
				var rule := _tutorial_always_rule()
				if rule != null:
					for e in rule.effects:
						if String(e.knob) == id.trim_prefix("always_knob_number:") and _effect_num.has(e) 								and is_instance_valid(_effect_num[e]):
							out.append(_effect_num[e])
			elif id.begins_with("cond_numbers:"):       # cond_numbers:<condition id>
				var rule := _tutorial_rule(id.trim_prefix("cond_numbers:"))
				if rule != null:
					for c in rule.conditions:
						if c.type_id() == id.trim_prefix("cond_numbers:") and _cond_nums.has(c):
							for n in _cond_nums[c]:
								if is_instance_valid(n):
									out.append(n)
			elif id.begins_with("rule_line:"):
				var rule := _tutorial_rule(id.trim_prefix("rule_line:"))
				if rule != null and _rule_line.has(rule) and is_instance_valid(_rule_line[rule]):
					out.append(_rule_line[rule])
	return out


## Where the player is with a rule that uses `condition_id`, for the scripting tutorial.
##   knob_steps  steps of `knob_id` in that rule      params    the condition's values, e.g. [3, 4.0]
##   discount    its "buffs xN" multiplier             points / budget   as OUTPUT shows them
func tutorial_state(condition_id: String, knob_id: StringName = &"damage",
		trade_knob: StringName = &"attack_speed") -> Dictionary:
	var rule := _tutorial_rule(condition_id)
	# The trade-off lesson: an always: rule that lowers a knob to pay for others
	var always := _tutorial_always_rule()
	var limits := _limits()
	if limits != null and limits.get_knob(trade_knob) == null:
		trade_knob = knob_id                     # this skill has no attack speed: trade damage
	var trade_steps := 0
	var trade_line := false                  # the knob's line is in the rule (it stays at 0 steps)
	if always != null:
		for e in always.effects:
			if e.knob == trade_knob:
				trade_steps += e.steps
				trade_line = true
	var knob_steps := 0
	var params: Array = []
	if rule != null:
		for e in rule.effects:
			if e.knob == knob_id:
				knob_steps += e.steps
		for c in rule.conditions:
			if c.type_id() == condition_id:
				for p in c.param_names():
					params.append(c.get(p))
	var v := _validation
	return {
		"knob_steps": knob_steps,
		"params": params,
		"discount": rule.cost_multiplier() if rule != null else 1.0,
		"points": v.buff_points if v != null else 0.0,
		"budget": (v.point_budget + v.drawback_points) if v != null else 0.0,
		"over": v != null and v.buff_points > v.point_budget + v.drawback_points + 0.001,
		"has_socket": _sock() != null and _limits() != null,
		"owner": _owner,
		"rule": rule != null,
		"selected": rule != null and rule == _selected,
		"effects": rule.effects.size() if rule != null else 0,
		"valid": _validation != null and _validation.valid,
		"dirty": _sock() != null and _is_dirty(_socket),
		"any_selected": _selected != null,
		"always_rule": always != null,
		"always_selected": always != null and _selected == always,
		"trade_knob": String(trade_knob),
		"trade_steps": trade_steps,
		"trade_line": trade_line,
		"drawback_points": v.drawback_points if v != null else 0.0,
	}


## The first always: rule (no conditions) of the open skill's own file.
func _tutorial_always_rule() -> ProgramRule:
	if _sock() == null or _limits() == null:
		return null
	for rule in _draft().rules_of(""):
		if rule.is_always() and rule.loop == null:
			return rule
	return null


## The first rule of the open skill's own file that uses `condition_id`.
func _tutorial_rule(condition_id: String) -> ProgramRule:
	if _sock() == null or _limits() == null:
		return null
	for rule in _draft().rules_of(""):
		for c in rule.conditions:
			if c.type_id() == condition_id:
				return rule
	return null


func refresh() -> void:
	var sk := _skills()
	if sk == null:
		return
	if _set_hooked != sk:
		if _set_hooked != null and is_instance_valid(_set_hooked) 				and _set_hooked.script_set_changed.is_connected(_on_set_changed):
			_set_hooked.script_set_changed.disconnect(_on_set_changed)
		_set_hooked = sk
		sk.script_set_changed.connect(_on_set_changed)
	# Forget drafts for sockets that were emptied, drop rules of removed supports
	for i in _drafts.keys():
		if i >= sk.sockets.size() or sk.sockets[i].gem == null:
			_drafts.erase(i)
		else:
			(_drafts[i] as SkillProgram).prune_owners(_support_ids(sk.sockets[i]))
	if _sock() == null or _sock().gem == null:
		_socket = -1
		for i in sk.sockets.size():
			if sk.sockets[i].gem != null:
				_socket = i
				break
		_owner = ""
	if _sock() != null and _owner != "" and not (_owner in [ROUTINES_FILE, KERNEL_FILE]) and not (_owner in _support_ids(_sock())):
		_owner = ""
	_rebuild()


func _select_gem(socket: int, owner_id: String) -> void:
	var same_file := socket == _socket and owner_id == _owner
	_socket = socket
	_owner = owner_id
	_selected = null
	_rebuild()
	if not same_file:
		_editor_scroll.scroll_vertical = 0           # a newly opened tab starts at its top


## The skill's files in the order the editor shows them: the skill, then each scriptable support.
func _file_owners() -> Array:
	var out: Array = [""]
	var s := _sock()
	if s == null:
		return out
	for item in s.supports:
		var def := item.definition.support_gem
		if not def.program_knobs.is_empty() and not (def.id in out):
			out.append(def.id)
	if _routines_unlocked():
		out.append(ROUTINES_FILE)                        # routines.gd: shared by every skill
	if _kernel_unlocked():
		out.append(KERNEL_FILE)                          # kernel.gd: last, about the zone (Act V)
	return out


## Rebuilding frees the control that is handling the current click or drop, so wait a frame.
func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	_rebuild_queued = false
	_validation = null
	_issue_line.clear()
	if _sock() != null and _limits() != null:
		_validation = _skills().preview_program(_socket, _draft(), _routines())
	_build_gem_list()
	_build_file_tabs()
	_build_rules()
	_build_palette()
	_update_status()
	_update_set_buttons()
	_update_library()


# ---------- SCRIPT SETS ----------
func _pick_set(index: int) -> void:
	var why := _skills().switch_script_set(index)
	_set_note.text = why
	_update_set_buttons()


func _copy_set(from: int) -> void:
	_skills().copy_set(from)


## Double-clicking a set's button renames it: a text box takes the button's place.
func _on_set_button_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT \
			and _skills().set_unlocked(index):
		_start_rename(index)


func _start_rename(index: int) -> void:
	_renaming = index
	var b := _set_btns[index]
	_rename_edit.get_parent().move_child(_rename_edit, b.get_index())
	b.visible = false
	_rename_edit.text = _skills().set_label(index)
	_rename_edit.visible = true
	_rename_btn.visible = false
	_rename_edit.grab_focus()
	_rename_edit.select_all()
	_lock_player(true)                      # typing WASD must not walk the character


func _finish_rename() -> void:
	if _renaming < 0:
		return
	var index := _renaming
	_renaming = -1
	_rename_edit.visible = false
	_set_btns[index].visible = true
	_rename_btn.visible = true
	_lock_player(false)
	_skills().rename_set(index, _rename_edit.text)
	_update_set_buttons()


# ---------- SCRIPT LIBRARY ----------
## save_as(): a name box takes the button's place; Enter saves the draft under that name.
func _start_save() -> void:
	if _sock() == null or not _skills().has_library():
		return
	if not _draft().has_rules():
		panel._notify("NOTHING TO SAVE")
		return
	_save_btn.visible = false
	_save_edit.text = _skills().set_label(_skills().script_set)
	_save_edit.visible = true
	_save_edit.grab_focus()
	_save_edit.select_all()
	_lock_player(true)


## Enter (save = true) saves; clicking away just closes the box.
func _finish_save(save: bool) -> void:
	if not _save_edit.visible:
		return
	_save_edit.visible = false
	_save_btn.visible = true
	_lock_player(false)
	if not save:
		return
	var why := _skills().library_save(_socket, _save_edit.text, _draft())
	panel._notify("SAVED TO LIBRARY" if why == "" else why)
	_update_library()


func _toggle_library() -> void:
	_library_open = not _library_open
	_update_library()


## The library buttons (locked below rank ARCHITECT) and, while load() is open, the list of
## scripts saved for this skill: load("NAME") puts one in the editor as a draft; del() drops it.
func _update_library() -> void:
	if _save_btn == null:
		return
	var sk := _skills()
	var unlocked := sk != null and sk.has_library()
	var has_skill := _sock() != null and _limits() != null
	_save_btn.visible = unlocked and not _save_edit.visible       # not shown below the rank
	_load_btn.visible = unlocked
	_save_btn.disabled = not has_skill
	_save_btn.tooltip_text = "Save this script to the library under a name, to load it again later (into another set, or after swapping gems)."
	_load_btn.disabled = not has_skill
	_load_btn.tooltip_text = "Load a script saved for this skill. It opens as a draft: apply() to run it."
	_library_open = _library_open and unlocked and has_skill
	_load_btn.text = "load() v" if _library_open else "load()"
	_clear(_library_box)
	_library_box.visible = _library_open
	if not _library_open:
		return
	var entries := sk.library_for(_socket)
	_library_box.add_child(panel._label("// library: %s  (%d / %d saved)" % [_file_name(_sock().gem.get_display_name()),
			sk.library.size(), SkillComponent.LIBRARY_SIZE], _sz(11), COL_COMMENT))
	if entries.is_empty():
		_library_box.add_child(panel._label("// nothing saved for this skill yet: save_as()", _sz(11), COL_COMMENT))
	for e: Dictionary in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_library_box.add_child(row)
		var rules: Array = e["program"].get("rules", [])
		var b := _code_button('load("%s")' % e["name"], "%d rule%s. Replaces this skill's draft; apply() to run it." % [
				rules.size(), "" if rules.size() == 1 else "s"])
		b.pressed.connect(_load_entry.bind(e))
		row.add_child(b)
		var d := _code_button("del()", "Delete %s from the library." % e["name"])
		d.add_theme_color_override("font_color", COL_DRAW)
		d.pressed.connect(_delete_entry.bind(e))
		row.add_child(d)


func _load_entry(entry: Dictionary) -> void:
	_drafts[_socket] = _skills().library_program(_socket, entry)
	_selected = null
	_library_open = false
	panel._notify("LOADED %s: apply() TO RUN IT" % entry["name"])
	_queue_rebuild()


func _delete_entry(entry: Dictionary) -> void:
	_skills().library_delete(entry)
	_update_library()


## A one-line name box styled like the editor (set names, library names).
func _name_edit(max_len: int, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.visible = false
	e.max_length = max_len
	e.custom_minimum_size.x = 120.0 * _k()
	e.placeholder_text = placeholder
	if panel._font:
		e.add_theme_font_override("font", panel._font)
	e.add_theme_font_size_override("font_size", roundi(_sz(12) * panel.font_scale))
	e.add_theme_color_override("font_color", panel.accent)
	e.add_theme_color_override("caret_color", panel.accent)
	e.add_theme_color_override("selection_color", Color(panel.accent, 0.3))
	var edit_box := _box_style(Color(0.0, 0.02, 0.04, 0.9), panel.accent)
	edit_box.content_margin_left = 6
	edit_box.content_margin_right = 6
	e.add_theme_stylebox_override("normal", edit_box)
	e.add_theme_stylebox_override("focus", edit_box)
	return e


func _lock_player(on: bool) -> void:
	var player := _skills().get_parent()
	if player != null and "input_locked" in player:
		player.input_locked = on


## Swapped (here or with the key in the field): the drafts belonged to the old set.
func _on_set_changed(_index: int) -> void:
	_drafts.clear()
	_selected = null
	_set_note.text = ""
	if is_inside_tree():
		_queue_rebuild()


func _update_set_buttons() -> void:
	var sk := _skills()
	var empty := sk != null and sk.set_is_empty(sk.script_set)
	for i in _copy_btns.size():
		_copy_btns[i].visible = empty and i != sk.script_set and not sk.set_is_empty(i) and sk.set_unlocked(i)
	# Sets above the player's rank aren't shown at all (Ranks.PERKS)
		_copy_btns[i].text = "copy_from(%s)" % sk.set_label(i)
		_copy_btns[i].tooltip_text = "This set is empty. Copy every skill's script from %s into it, then change what you need." % sk.set_label(i)
	for i in _set_btns.size():
		var active := sk != null and sk.script_set == i
		var b := _set_btns[i]
		var label := sk.set_label(i)
		b.text = ("SET " + label) if label == SkillComponent.SET_NAMES[i] else label
		b.tooltip_text = "Script set %s. Every skill keeps one program per set; [%s] swaps sets any time, even mid-fight. Each set starts empty. Double-click to rename it." % [label, GemText.key_label(&"script_set")]
		b.visible = sk.set_unlocked(i) and _renaming != i
		b.add_theme_color_override("font_color", panel.accent if active else COL_GUTTER)
		b.add_theme_color_override("font_disabled_color", Color(COL_GUTTER, 0.35))
		var st := (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
		st.border_color = panel.accent if active else Color(COL_GUTTER, 0.4)
		st.bg_color = Color(panel.accent, 0.15) if active else Color(0, 0, 0, 0)
		b.add_theme_stylebox_override("normal", st)


# ---------- LEFT: EXPLORER ----------
func _build_gem_list() -> void:
	_clear(_gem_list)
	_skill_file_btn.clear()
	var sk := _skills()
	var any := false
	for i in sk.sockets.size():
		var s := sk.sockets[i]
		if s.gem == null:
			continue
		any = true
		var dirty := _is_dirty(i)
		var bad := _error_owners(i)              # files of this skill with errors get a red "!"
		var skill_btn := _file_button(_file_name(s.gem.get_display_name()) + (" *" if dirty else "") \
			+ (" !" if bad.has("") else ""), i, "", SkillPanel.COL_WARN if bad.has("") else SkillPanel.COL_SKILL, 0)
		if bad.has(""):
			skill_btn.tooltip_text += "\nhas errors"
		_gem_list.add_child(skill_btn)
		_skill_file_btn[i] = skill_btn
		for item in s.supports:
			var def := item.definition.support_gem
			var b := _file_button(_file_name(def.display_name) + (" !" if bad.has(def.id) else ""), i, def.id,
				SkillPanel.COL_WARN if bad.has(def.id) else SkillPanel.COL_SUPPORT, 1)
			if bad.has(def.id):
				b.tooltip_text += "\nhas errors"
			if def.program_knobs.is_empty():
				b.disabled = true
				b.tooltip_text = "This support has nothing to script."
			_gem_list.add_child(b)
	if any and _routines_unlocked():                     # routines.gd: one file for every skill
		var bad := false
		for rt in _routines():
			bad = bad or (not (rt as ProgramRoutine).is_empty() and not (rt as ProgramRoutine).problem().is_empty())
		var rb := _file_button("routines.gd" + (" *" if _routines_dirty() else "") + (" !" if bad else ""),
			_socket, ROUTINES_FILE, SkillPanel.COL_WARN if bad else COL_KEYWORD, 0)
		rb.tooltip_text = "Your routines: lines written once, run from any skill with call name() (1 block). Shared by every skill."
		_gem_list.add_child(rb)
	if any and _kernel_unlocked():                       # kernel.gd: root lines about the zone (Act V)
		var running := KernelScript.null_running(_kernel_qm()).size()
		var kb := _file_button(KernelScript.FILE_NAME + (" !" if running > 0 else ""), _socket, KERNEL_FILE,
			KernelScript.COL_NULL if running > 0 else COL_KERNEL, 0)
		kb.tooltip_text = "kernel.gd: the record of the Null's pull requests and your answers (read only). Its lines run on the zone, in every Act V zone past the Core."
		if running > 0:
			kb.tooltip_text += "\nYou merged %d of the Null's lines: they run too." % running
		_gem_list.add_child(kb)
		_kernel_file_btn = kb
	if not any:
		_gem_list.add_child(panel._label("// socket a skill first", _sz(12), COL_COMMENT))


func _file_button(text: String, socket: int, owner_id: String, col: Color, indent: int) -> Button:
	var b := Button.new()
	b.text = "   ".repeat(indent) + ("v " if indent == 0 else "") + text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = text
	if panel._font:
		b.add_theme_font_override("font", panel._font)
	b.add_theme_font_size_override("font_size", roundi(_sz(12) * panel.font_scale))
	b.add_theme_color_override("font_color", Color(col, 0.85))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(col, 0.35))
	var selected := socket == _socket and owner_id == _owner
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(panel.accent, 0.14) if selected else Color(0, 0, 0, 0)
	normal.border_color = panel.accent
	normal.border_width_left = 2 if selected else 0
	normal.content_margin_left = 6
	normal.content_margin_top = 2
	normal.content_margin_bottom = 2
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(panel.accent, 0.2 if selected else 0.08)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", normal)
	b.pressed.connect(_select_gem.bind(socket, owner_id))
	return b


# ---------- MIDDLE: EDITOR ----------
func _build_rules() -> void:
	_clear(_rules_box)
	_line_no = 0
	_rule_line.clear()
	_effect_num.clear()
	_cond_nums.clear()
	_new_rule_ctrl = null
	var s := _sock()
	if s == null:
		_title.text = "no file open"
		_comment_line("# socket a skill first")
		return
	var limits := _limits()
	var skill_file := _file_name(s.gem.get_display_name())
	if limits == null:
		_title.text = skill_file
		_comment_line("# this skill can't be scripted")
		return
	var owners := _file_owners()
	if not (_owner in owners):
		_owner = ""
	if _owner == "":
		_title.text = skill_file
	elif _owner == ROUTINES_FILE:
		_title.text = "routines.gd  (every skill)"
	elif _owner == KERNEL_FILE:
		_title.text = "kernel.gd  (yours: patched)" if Endings.kernel_editable(_kernel_qm()) \
			else "kernel.gd  (read only: the Null's pull requests)"
		_selected = null
		_line_no = 0
		_kernel_lines()
		return
	else:
		var sup: SupportGemDefinition = SkillGemRegistry.get_support_gem(_owner)
		_title.text = "%s / %s" % [skill_file.trim_suffix(".gd"), _file_name(sup.display_name) if sup else _owner]

	# Only the open file (its tab): a selected rule in another file is let go, so a snippet click
	# never lands somewhere out of sight
	var shown: Array = []
	if _owner == ROUTINES_FILE:
		for rt in _routines():
			shown.append((rt as ProgramRoutine).body)
	else:
		shown.append_array(_draft().rules_of(_owner))
	if _selected != null and not (_selected in shown):
		_selected = null
	_line_no = 0
	if _owner == ROUTINES_FILE:
		_routine_lines(limits)
		return
	if _owner == "":
		_comment_line("# points are shared with every file of this skill (its other tabs)")
	elif owners.size() > 1:
		_comment_line("# points are shared with %s and its other tabs" % skill_file)
	for rule in _draft().rules_of(_owner):
		_blank_line(rule)
		_rule_lines(rule, limits)
	_blank_line(null)
	_new_rule_line(_owner)


# ---------- FILE TABS ----------
## One tab per file of the open skill, above the code: the skill's file, each scriptable support,
## then routines.gd. * = unsaved (the skill's script and its supports share one draft), ! = errors.
func _build_file_tabs() -> void:
	_clear(_file_tabs)
	if _sock() == null or _limits() == null:
		_file_tabs.visible = false
		return
	_file_tabs.visible = true
	var bad := _error_owners(_socket)
	for owner_id in _file_owners():
		var text := _owner_file(owner_id)
		var has_error: bool = bad.has(owner_id)
		if owner_id == "" and _is_dirty(_socket):
			text += " *"
		elif owner_id == ROUTINES_FILE:
			if _routines_dirty():
				text += " *"
			for rt in _routines():
				has_error = has_error or (not (rt as ProgramRoutine).is_empty() and not (rt as ProgramRoutine).problem().is_empty())
		if has_error:
			text += " !"
		_file_tabs.add_child(_file_tab(owner_id, text, has_error))


func _file_tab(owner_id: String, text: String, has_error: bool) -> Button:
	var active := owner_id == _owner
	var col: Color = SkillPanel.COL_SKILL if owner_id == "" else (COL_KEYWORD if owner_id == ROUTINES_FILE else SkillPanel.COL_SUPPORT)
	if owner_id == KERNEL_FILE:
		col = COL_KERNEL
	if has_error:
		col = SkillPanel.COL_WARN
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s\nClick to open this file. While dragging a line or snippet, hover a tab to open it." % _owner_file(owner_id)
	if has_error:
		b.tooltip_text += "\nhas errors"
	if panel._font:
		b.add_theme_font_override("font", panel._font)
	b.add_theme_font_size_override("font_size", roundi(_sz(12) * panel.font_scale))
	b.add_theme_color_override("font_color", Color(col, 1.0 if active else 0.6))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(col, 0.16) if active else Color(0.0, 0.02, 0.04, 0.5)
	normal.border_color = Color(col, 0.95 if active else 0.3)
	normal.border_width_top = 2 if active else 1
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 3
	normal.content_margin_bottom = 3
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(col, 0.22 if active else 0.1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(_select_gem.bind(_socket, owner_id))
	# Dragging a line or snippet over a tab opens that file, so it can be dropped there
	b.set_drag_forwarding(Callable(), func(_pos: Vector2, data: Variant) -> bool:
		if data is Dictionary and data.get("src") in ["palette", "rule"] and owner_id != _owner:
			_owner = owner_id
			_selected = null
			_editor_scroll.scroll_vertical = 0
			_queue_rebuild()
		return false, Callable())
	return b


# ---------- ROUTINES (routines.gd) ----------
## routines.gd: the character's three routines, each "def name():" and its lines. Edited like a
## rule (drop knobs, registry writes and if blocks in; no conditions or loops of its own), and run
## from any skill's script with  call name()  (one block; each skill pays for the lines).
func _routine_lines(limits: SkillProgramLimits) -> void:
	_comment_line("# shared by every skill: call name() is 1 block, and each skill pays for the lines")
	var routines := _routines()
	for i in routines.size():
		var rt: ProgramRoutine = routines[i]
		_blank_line(rt.body)
		_routine_header(i, rt)
		if rt.is_empty():
			var parts := _code_line(rt.body)
			var code: HBoxContainer = parts[1]
			code.add_child(_tok("    pass", COL_KEYWORD))
			code.add_child(_comment_tok("drop knobs, registry writes or an if here"))
			_make_line_interactive(parts[0], rt.body, {})
		for e in rt.body.effects:
			_effect_line(rt.body, e, limits, "    ")
		for bi in rt.body.branches.size():
			_branch_lines(rt.body, bi, limits)
	_blank_line(null)


## def cash_in():   # 3/6 blocks, called by strike.gd       [clear]
## The name is a button: click it to rename the routine.
func _routine_header(i: int, rt: ProgramRoutine) -> void:
	var parts := _code_line(rt.body)
	var line: Control = parts[0]
	var code: HBoxContainer = parts[1]
	code.add_child(_tok("def ", COL_KEYWORD))
	if _routine_rename == i:
		var edit := _name_edit(ProgramRoutine.NAME_MAX, "name")
		edit.visible = true
		edit.text = rt.routine_name
		edit.text_submitted.connect(func(_t: String) -> void: _finish_routine_rename(edit, i))
		edit.focus_exited.connect(func() -> void: _finish_routine_rename(edit, i))
		code.add_child(edit)
		edit.grab_focus.call_deferred()
		edit.select_all.call_deferred()
	else:
		var name_btn := _code_button(rt.routine_name, "Click to rename this routine. Calls keep working: they point at the routine, not its name.")
		name_btn.add_theme_color_override("font_color", COL_FN)
		name_btn.pressed.connect(_start_routine_rename.bind(i))
		code.add_child(name_btn)
	code.add_child(_tok("():", COL_OP))
	var problem: Array = rt.problem() if not rt.is_empty() else []
	var note := "%d/%d blocks" % [rt.block_count(), ProgramRoutine.MAX_BLOCKS]
	var echoes := NullEcho.callers_of(get_tree(), i) if is_inside_tree() else 0   # Act IV: copies calling it
	var echo_text := "%d Null Echo%s" % [echoes, "" if echoes == 1 else "es"]
	if not problem.is_empty():
		note = problem[1]
		if echoes > 0:
			note += " (%s call%s it: apply, and they crash)" % [echo_text, "s" if echoes == 1 else ""]
	else:
		var callers := _routine_callers(i)
		if echoes > 0:
			callers.append(echo_text)
		if not callers.is_empty():
			note += ", called by " + ", ".join(callers)
	var tok := _comment_tok(note)
	if not problem.is_empty():
		tok.add_theme_color_override("font_color", SkillPanel.COL_WARN)
	code.add_child(tok)
	var clear_btn := _code_button("clear", "Empty this routine (its name stays). A script that calls it won't compile until it has lines again.")
	clear_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	clear_btn.pressed.connect(func() -> void:
		rt.body.effects.clear()
		rt.body.branches.clear()
		_changed())
	code.add_child(clear_btn)
	line.tooltip_text = "A routine: lines written once, run from any skill with  call %s()  (1 block in that script).\nIt has no conditions of its own: the rule that calls it decides when. Each skill that calls it pays the points for its lines, on its own knobs.\nThe numbers here are the base. A rule that makes its knobs stronger (a Gladiator's every-Nth rule...) makes these stronger too: \"called by strike.gd x1.75\", and the call line shows each value.\nAt most %d blocks, and one level of if." % [
		rt.routine_name, ProgramRoutine.MAX_BLOCKS]
	_make_line_interactive(line, rt.body, {})
	_rule_line[rt.body] = line


func _start_routine_rename(i: int) -> void:
	_routine_rename = i
	_lock_player(true)                          # typing WASD must not walk the character
	_queue_rebuild()


func _finish_routine_rename(edit: LineEdit, i: int) -> void:
	if _routine_rename != i:
		return
	_routine_rename = -1
	_lock_player(false)
	var routines := _routines()
	var wanted := ProgramRoutine.clean_name(edit.text, i)
	for j in routines.size():
		if j != i and (routines[j] as ProgramRoutine).routine_name == wanted:
			panel._notify("ANOTHER ROUTINE IS CALLED %s" % wanted.to_upper())
			_queue_rebuild()
			return
	(routines[i] as ProgramRoutine).routine_name = wanted
	_queue_rebuild()


## call cash_in()   (the name is a button: click / right-click switches routine)
func _call_line(code: HBoxContainer, parts: Array, rule: ProgramRule, e: ProgramEffect, branch: ProgramBranch) -> void:
	var routines := _routines()
	var rt: ProgramRoutine = routines[e.op] if e.op >= 0 and e.op < routines.size() else null
	code.add_child(_tok("call ", COL_KEYWORD))
	var name_tok := _num_tok(rt.routine_name if rt != null else "routine_%d" % (e.op + 1),
		"which routine (click / right-click: the next one)", func(d: int) -> void:
			e.op = posmod(e.op + d, routines.size())
			_changed())
	code.add_child(name_tok)
	_effect_num[e] = name_tok
	code.add_child(_tok("()", COL_OP))
	var calling := rule.branch_rule(rule.branches.find(branch)) if branch != null else rule
	var here := _routine_here(rt, calling, _limits()) if rt != null and not rt.is_empty() else {}
	var note := "1 block" + ("" if here.is_empty() else ", runs %d" % rt.block_count())
	var boosted: bool = not here.is_empty() and not is_equal_approx(float(here["mult"]), 1.0)
	if boosted:
		note += ", knobs %sx%.2f here (%s)" % ["up to " if here["mixed"] else "", here["mult"], here["why"]]
	var note_tok := _comment_tok(note)
	if boosted:
		note_tok.add_theme_color_override("font_color", Color(COL_BUFF, 0.85))
	code.add_child(note_tok)
	var body := "empty" if here.is_empty() else "\n    " + "\n    ".join(here["lines"])
	parts[0].tooltip_text = "Runs %s() here, under this rule's conditions:%s%s\n1 block in this script, whatever the routine holds; this skill pays the points for its lines.\nEdit it in routines.gd. Click the name to switch routine. Drag out or right-click to delete." % [
		rt.routine_name if rt != null else "a routine", body,
		("\nThis rule makes its knobs stronger (%s): the numbers in routines.gd are the base, these are what this call does." % here["why"]) if boosted else ""]
	_make_line_interactive(parts[0], rule, {"kind": "effect", "effect": e}, branch)
	_mark(parts, rule, e)


## A routine's knob lines as the rule `calling` runs them: the rule's multipliers apply to them as
## if they were written there (Gladiator's every-Nth rules, Assassin's per-hit rules, Variable
## Store's charge). A routine's own if adds its conditions to the rule's.
## {"lines": ["damage += 10%  ->  18% here (x1.75)", ...], "mult": strongest multiplier, "why": its source}
func _routine_here(rt: ProgramRoutine, calling: ProgramRule, limits: SkillProgramLimits) -> Dictionary:
	var lines := PackedStringArray()
	var top := 1.0
	var why := ""
	var mults := {}                                   # every multiplier a knob line gets (1.0 too)
	var groups: Array = [[rt.body.effects, calling, ""]]
	for b in rt.body.branches:
		var as_if := ProgramRule.new()
		as_if.owner = calling.owner
		as_if.conditions.assign(calling.conditions + b.conditions)
		groups.append([b.effects, as_if, "if: "])
	for g in groups:
		var r: ProgramRule = g[1]
		for e: ProgramEffect in g[0]:
			if e.is_call():
				continue
			if ScriptRegisters.is_write(e.knob):
				lines.append("%s%s" % [g[2], e.describe_write()])
				continue
			var knob := limits.get_knob(e.knob)
			if knob == null:
				lines.append("%s%s  (not a knob of this skill)" % [g[2], e.knob])
				continue
			var mult := limits.rule_effect_mult(r, not SkillProgramLimits.per_hit_knob(knob))
			mults[snappedf(mult, 0.01)] = true
			var base := _fmt_per_count(knob, e.steps) if e.ramps() else _fmt_knob(knob, e.steps)
			var now := _fmt_per_count(knob, e.steps, mult) if e.ramps() else _fmt_knob(knob, e.steps, mult)
			var text := "%s%s%s%s%s" % [g[2], e.knob, " -= " if e.steps < 0 else " += ",
				(e.ramp_text() + " * ") if e.ramps() else "", base]
			if not is_equal_approx(mult, 1.0):
				text += "  ->  %s here (x%.2f)" % [now, mult]
				if mult > top:
					top = mult
					why = _boost_source(r, limits)
			lines.append(text)
	return {"lines": lines, "mult": top, "why": why, "mixed": mults.size() > 1}


## What makes a rule's knobs stronger, for the hint: "gladiator, every 3rd cast", "charge"...
func _boost_source(rule: ProgramRule, limits: SkillProgramLimits) -> String:
	var parts := PackedStringArray()
	var t := limits.class_trait
	if t != null:
		var n := 0
		for c in rule.conditions:
			if c is EveryNthCastCondition:
				n = maxi(n, (c as EveryNthCastCondition).n)
		if n > 0 and not is_equal_approx(t.nth_effect_mult(rule), 1.0):
			parts.append("%s, every %s cast" % [t.display_name.to_lower(), _ordinal(n)])
		if rule.loop == null and rule.scope() == ProgramCondition.Scope.HIT and not is_equal_approx(t.hit_rule_effect_mult, 1.0):
			parts.append("%s, per-hit rule" % t.display_name.to_lower())
	if VariableStoreSupport.rule_effect_mult(rule) > 1.0:
		parts.append("spent charge")
	return ", ".join(parts) if not parts.is_empty() else "this rule"


static func _ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "%dth" % n
	match n % 10:
		1:
			return "%dst" % n
		2:
			return "%dnd" % n
		3:
			return "%drd" % n
	return "%dth" % n


## Empty space in the editor, `height` px at the original 13 px design size.
func _spacer(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height * _k()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _rule_lines(rule: ProgramRule, limits: SkillProgramLimits) -> void:
	var discount := ""
	if not rule.is_always() and rule.cost_multiplier() < 1.0:
		discount = "buffs x%.2f" % rule.cost_multiplier()
		if rule.spends_marks():
			discount += " (spends its marks%s)" % (", max discount" if rule.is_discount_capped() else "")
		elif rule.is_discount_capped():
			discount += " (max discount)"
	var looping := rule.loop != null
	var is_while := looping and rule.loop.mode == ProgramLoop.Mode.WHILE

	if rule.is_always():
		var parts := _code_line(rule)
		var code: HBoxContainer = parts[1]
		code.add_child(_tok("always", COL_KEYWORD))
		code.add_child(_tok(":", COL_OP))
		code.add_child(_comment_tok(""))
		code.add_child(_delete_rule_button(rule))
		_make_line_interactive(parts[0], rule, {})
		_mark(parts, rule, null)
		_rule_line[rule] = parts[0]
	else:
		for i in rule.conditions.size():
			var c := rule.conditions[i]
			var last := i == rule.conditions.size() - 1
			var parts := _code_line(rule)
			var code: HBoxContainer = parts[1]
			var head := ("while " if is_while else "when ") if i == 0 else " and "
			if c.keyword() != "" and i == 0:
				head = c.keyword() + " "         # except missed:
			code.add_child(_tok(head, COL_KEYWORD))
			_condition_tokens(code, c, last)
			code.add_child(_comment_tok(_cond_note(c, discount if i == 0 else "")))
			if i == 0:
				code.add_child(_delete_rule_button(rule))
			parts[0].tooltip_text = "%s\nCOST: buffs in this rule x%.2f\nDrag out or right-click to delete." % [c.describe(), c.cost_multiplier()]
			_make_line_interactive(parts[0], rule, {"kind": "condition", "condition": c})
			_mark(parts, rule, c)
			if i == 0:
				_mark(parts, rule, null)          # rule-wide problems go on its first line
				_rule_line[rule] = parts[0]

	# Body. A for loop indents everything under it; a while's header is the rule itself.
	var indent := "    "
	if looping and not is_while:
		_loop_line(rule, limits)
		indent = "        "
	if rule.effects.is_empty() and not looping and rule.branches.is_empty():
		var parts := _code_line(rule)
		var code: HBoxContainer = parts[1]
		code.add_child(_tok("    pass", COL_KEYWORD))
		code.add_child(_comment_tok("drop a knob here"))
		_make_line_interactive(parts[0], rule, {})
	for e in rule.effects:
		_effect_line(rule, e, limits, indent)
	if not looping:
		for bi in rule.branches.size():
			_branch_lines(rule, bi, limits)
	else:
		if is_while:
			_loop_line(rule, limits)
		else:
			_cast_line(rule, indent)
		# A loop's if blocks come after the cast: they're checked once it lands
		for bi in rule.branches.size():
			_branch_lines(rule, bi, limits, indent)


## A condition line's comment: a registry[...] check says in words which enemy it means
## ("the nearest", "the 3 lowest-hp"), ahead of the rule's discount.
func _cond_note(c: ProgramCondition, discount: String) -> String:
	var at := c as RegistryPositionCondition
	if at == null:
		return discount
	var says := ScriptRegisters.position_meaning(at.pos, _draft_sort())
	return says if discount == "" else "%s, %s" % [says, discount]


## The order a registry[...] check reads: the draft's first sort line, or oldest first.
func _draft_sort() -> int:
	for r in _draft().rules:
		for e in r.effects:
			if ScriptRegisters.is_sort(e):
				return e.sort_by
		for b in r.branches:
			for e in b.effects:
				if ScriptRegisters.is_sort(e):
					return e.sort_by
	return 0


## A condition's tokens after its keyword: fn(params) for a call, or the parts of a modular block
## (target in registry). `last`: it ends the header, so it gets the ":".
func _condition_tokens(code: HBoxContainer, c: ProgramCondition, last: bool) -> void:
	var call_form := c.keyword() == "" and not c.modular()
	if not c.modular():                          # when [x] [>=] [3]: is all parameters
		code.add_child(_tok(_fn_name(c), COL_GEM if c.required_support() != "" else COL_FN))
	if call_form:
		code.add_child(_tok("(", COL_OP))
	var params := c.param_names()
	for j in params.size():
		var p := params[j]
		if j > 0:
			code.add_child(_tok(" " if c.modular() else ", ", COL_OP))
		var param_num := _num_tok(_fmt_param(c, p), c.param_label(p).to_lower(), func(d: int) -> void:
			c.nudge_param(p, d)
			_changed())
		code.add_child(param_num)
		if not _cond_nums.has(c):
			_cond_nums[c] = []
		_cond_nums[c].append(param_num)
	if call_form:
		code.add_child(_tok("):" if last else ")", COL_OP))
	elif last:
		code.add_child(_tok(":", COL_OP))


## An "if" block inside a rule: its header (one line per condition, "if" then "and"), then its
## lines one step further in. Drops on any of its lines go into the block.
## `indent`: where its "if" starts (deeper inside a for loop). In a loop rule it's checked after
## each cast or repeat lands, and may end in  break.
func _branch_lines(rule: ProgramRule, bi: int, limits: SkillProgramLimits, indent := "    ") -> void:
	var b := rule.branches[bi]
	var inner := indent + "    "
	var as_rule := rule.branch_rule(bi)
	var discount := ""
	if not b.conditions.is_empty() and as_rule.cost_multiplier() < 1.0:
		discount = "buffs x%.2f" % as_rule.cost_multiplier()
		if as_rule.spends_marks():
			discount += " (spends its marks%s)" % (", max discount" if as_rule.is_discount_capped() else "")
		elif as_rule.is_discount_capped():
			discount += " (max discount)"
	var per_hit := as_rule.scope() == ProgramCondition.Scope.HIT
	var head_tip := "if block\nIts lines apply when the rule fires AND its own conditions are true.%s%s\nTIP: fewer blocks than a second rule\nDrop a condition on this line, knobs below it.\nDrag out or right-click to delete the if." % [
		"\nLOOP: checked after each cast or repeat lands · its lines change the next repeat · break stops the loop" if rule.loop != null else "",
		"\nHIT: checked per hit · only damage, leech, barrier, guard and support effects" if per_hit else ""]
	if b.conditions.is_empty():
		var parts := _code_line(rule)
		var code: HBoxContainer = parts[1]
		code.add_child(_tok(indent + "if ", COL_KEYWORD))
		code.add_child(_tok("...:", COL_OP))
		code.add_child(_comment_tok("drop a condition here"))
		parts[0].tooltip_text = head_tip
		_make_line_interactive(parts[0], rule, {"kind": "branch"}, b)
		_mark(parts, rule, b)
	for i in b.conditions.size():
		var c := b.conditions[i]
		var parts := _code_line(rule)
		var code: HBoxContainer = parts[1]
		code.add_child(_tok(indent + ("if " if i == 0 else " and "), COL_KEYWORD))
		_condition_tokens(code, c, i == b.conditions.size() - 1)
		code.add_child(_comment_tok(_cond_note(c, discount if i == 0 else "")))
		if i == 0:
			parts[0].tooltip_text = head_tip
			_make_line_interactive(parts[0], rule, {"kind": "branch"}, b)
			_mark(parts, rule, b)
		else:
			parts[0].tooltip_text = "%s\nPart of the if block above.\nDrag out or right-click to delete." % c.describe()
			_make_line_interactive(parts[0], rule, {"kind": "condition", "condition": c}, b)
		_mark(parts, rule, c)
	if b.effects.is_empty() and not b.breaks:
		var parts := _code_line(rule)
		var code: HBoxContainer = parts[1]
		code.add_child(_tok(inner + "pass", COL_KEYWORD))
		code.add_child(_comment_tok("drop a knob here" if rule.loop == null else "drop a knob or break here"))
		_make_line_interactive(parts[0], rule, {}, b)
	for e in b.effects:
		_effect_line(rule, e, limits, inner, b)
	if b.breaks:
		_break_line(rule, b, inner)


## `branch`: the if block the line is in (null = the rule's own lines). Its numbers (per-hit
## limits, discounts, class bonuses) come from the rule the block means.
func _effect_line(rule: ProgramRule, e: ProgramEffect, limits: SkillProgramLimits, indent := "    ",
		branch: ProgramBranch = null) -> void:
	var owner_rule := rule
	if branch != null:
		rule = owner_rule.branch_rule(owner_rule.branches.find(branch))
	var knob := limits.get_knob(e.knob)
	var cost := _draft().line_cost(knob, e) if knob else 0.0
	if cost > 0.0:
		cost *= limits.buff_cost_mult()                  # class trait discount (Enchanter)
	var marker := "+" if cost > 0.0 else ("-" if cost < 0.0 else "")
	var parts := _code_line(owner_rule, marker, COL_BUFF if cost > 0.0 else COL_DRAW)
	var code: HBoxContainer = parts[1]
	code.add_child(_tok(indent, COL_OP))
	if e.is_call():                                      # call cash_in(): a routine (routines.gd)
		_call_line(code, parts, owner_rule, e, branch)
		return
	if ScriptRegisters.is_sort(e):                       # registry.sort([key=hp]): click to change the order
		code.add_child(_tok("registry.sort(", COL_VAR))
		var key_num := _num_tok(ScriptRegisters.sort_text(e.sort_by), "order", func(d: int) -> void:
			e.sort_by = posmod(e.sort_by + d, ScriptRegisters.SORT_KEYS.size() * 2)
			_changed())
		code.add_child(key_num)
		_effect_num[e] = key_num
		code.add_child(_tok(")", COL_VAR))
		code.add_child(_comment_tok(ScriptRegisters.sort_meaning(e.sort_by)))
		parts[0].tooltip_text = "Puts the registry in order: %s. Then when target is registry[0]: is the first one in that order, registry[-1] the last.
The order holds from this rule's cast on; every cast starts back at oldest first, so a sort in a WHEN only holds while the WHEN does. Free: no points or blocks.
Click the key to change it (each key, then reversed). Drag out or right-click to delete." % ScriptRegisters.sort_meaning(e.sort_by)
		_make_line_interactive(parts[0], owner_rule, {"kind": "effect", "effect": e}, branch)
		_mark(parts, owner_rule, e)
		return
	if ScriptRegisters.is_write(e.knob):                 # [registry.add](target): click to swap add / remove
		var op_num := _num_tok("registry." + e.write_op(), "operation", func(d: int) -> void:
			e.op = posmod(e.op + d, ScriptRegisters.MEMBER_WRITES)
			_changed())
		code.add_child(op_num)
		_effect_num[e] = op_num
		code.add_child(_tok("(target)", COL_OP))
		code.add_child(_comment_tok("repeats only" if rule.loop != null or rule.only_on_repeats() else ""))
		var when := "the enemy being hit" if rule.scope() == ProgramCondition.Scope.HIT \
				else "every enemy this cast hits, as each hit lands"
		var what := "Adds %s to the registry." if e.write_op() == "add" else "Takes %s out of the registry."
		parts[0].tooltip_text = (what % when) + " The registry is a set of enemies: each one is in it or not. It keeps them between casts; an enemy that dies leaves it. Free: no points or blocks.\nClick add / remove to swap. Drag out or right-click to delete."
		_make_line_interactive(parts[0], owner_rule, {"kind": "effect", "effect": e}, branch)
		_mark(parts, owner_rule, e)
		return
	if knob == null:                                     # a routine's line this skill can't use
		code.add_child(_tok(String(e.knob), COL_VAR))
		code.add_child(_tok(" -= " if e.steps < 0 else " += ", COL_OP))
		code.add_child(_tok(str(absi(e.steps)) + " steps", COL_NUM))
		code.add_child(_comment_tok("not a knob of this skill"))
		parts[0].tooltip_text = "This skill has no %s knob: a script on it that calls this routine won't compile.\nDrag out or right-click to delete." % e.knob
		_make_line_interactive(parts[0], owner_rule, {"kind": "effect", "effect": e}, branch)
		_mark(parts, owner_rule, e)
		return
	code.add_child(_tok(String(e.knob), COL_VAR))
	code.add_child(_tok(" -= " if e.steps < 0 else " += ", COL_OP))
	var effect_mult := limits.rule_effect_mult(rule, not SkillProgramLimits.per_hit_knob(knob))
	var grow_tok := func() -> Control:
		return _num_tok(e.ramp_text(), "what this grows with (it stops at the knob's limit)",
			func(d: int) -> void:
				e.ramp = _next_grow_key(e.ramp, d)
				_changed())
	if e.ramps():                                        # damage += registry.size * 1%
		code.add_child(grow_tok.call())
		code.add_child(_tok(" * ", COL_OP))
	var value := str(absi(e.steps))
	if knob:
		value = _fmt_per_count(knob, e.steps, effect_mult) if e.ramps() else _fmt_knob(knob, e.steps, effect_mult)
	var num := _num_tok(value, knob.display_name.to_lower() if knob else String(e.knob), func(d: int) -> void:
		e.steps += d
		_changed())
	code.add_child(num)
	_effect_num[e] = num
	var note := ""
	if cost > 0.0:
		note = "costs %.1f" % cost
		if e.ramps() and knob:
			var room := _draft().growth_room(e, knob)
			note += ", max +%s at %s = %d" % [_fmt_knob(knob, room, effect_mult), e.ramp_text(), ScriptRegisters.ramp_reach(e.steps, room)]
	elif cost < 0.0:
		note = "pays %.1f" % -cost
	if rule.loop != null or rule.only_on_repeats():
		note = ("%s, repeats only" % note) if note != "" else "repeats only"
	var charge_mult := VariableStoreSupport.rule_effect_mult(rule)
	if charge_mult > 1.0:
		var x := "x%.2f charge" % charge_mult                 # Variable Store: spent charge amplifies it
		note = ("%s, %s" % [note, x]) if note != "" else x
	code.add_child(_comment_tok(note))
	if knob and e.ramps():
		parts[0].tooltip_text = "%s grows with registry.size\nOne step per enemy in the registry, up to its limit (less your other %s lines).\nCOST: a higher value grows faster and costs more\nNOTE: needs a registry.add(target) line to grow\nDrag out or right-click to delete." % [
			knob.display_name, e.knob]
	elif knob:
		parts[0].tooltip_text = "%s: %s\n%s\n%s%s%s\nDrag out or right-click to delete." % [
			knob.display_name, knob.describe(e.steps), _step_price_note(knob), _knob_usage_note(knob),
			(_stat_note(knob, limits) if knob.kind == SkillKnob.Kind.STAT else "") + _knob_limits_note(knob),
			"\nLOOP: changes the repeats only" if rule.loop != null or rule.in_loop() or rule.only_on_repeats() else ""]
	_make_line_interactive(parts[0], owner_rule, {"kind": "effect", "effect": e}, branch)
	_mark(parts, owner_rule, e)


## How many steps this script has on the knob and its limit. Conditional rules count as if all of
## them were active at once, the same way the limit is checked (ProgramValidation.knob_ranges).
func _knob_usage_note(knob: SkillKnob) -> String:
	var range_now: Array = _validation.knob_ranges.get(knob.id, [0, 0]) if _validation != null else [0, 0]
	var lo: int = range_now[0]
	var hi: int = range_now[1]
	var have := "%+d steps" % lo if lo == hi else "%+d to %+d steps (every when rule on)" % [lo, hi]
	if lo == 0 and hi == 0:
		have = "0 steps"
	return "LIMIT: %s used, %d to %+d allowed" % [have, knob.min_steps, knob.max_steps]


## Buff steps get pricier the more this script puts on the knob; drawbacks pay back flat.
func _step_price_note(knob: SkillKnob) -> String:
	var n := _draft().buff_steps_on(knob)
	var pay := "drawback steps pay %.1f points" % absf(knob.cost_per_step)
	if n <= 0:
		return "COST: first buff step %.1f points · %s" % [knob.next_step_cost(0), pay]
	return "COST: next buff step %.1f points (x%s the last) · %s" % [
		knob.next_step_cost(n), str(SkillKnob.STEP_COST_GROWTH), pay]


## True when this line can grow with the registry, for a player who has the registry.
func _can_grow(knob: SkillKnob, limits: SkillProgramLimits) -> bool:
	return limits.allows("knob:" + String(ScriptRegisters.WRITE_KNOB)) and ScriptRegisters.can_grow(knob)


## The next choice of what a buff grows with, `d` clicks on: nothing (-1) or registry.size (0).
static func _next_grow_key(ramp: int, d: int) -> int:
	return -1 if (ramp >= 0) != (posmod(d, 2) == 0) else 0


## Where a support knob can't work (see SkillKnob.always_only / first_cast_only).
func _knob_limits_note(knob: SkillKnob) -> String:
	if knob.always_only and knob.kind != SkillKnob.Kind.STAT:
		return "\nNOTE: always: rules only (read before the cast starts)"
	if knob.first_cast_only:
		return "\nNOTE: changes the original cast only, not loop repeats"
	return ""


func _stat_note(knob: SkillKnob, limits: SkillProgramLimits) -> String:
	if limits.per_hit_attack_speed(knob):
		return "\nNOTE: always: rules, or (Assassin) per-hit rules: a hit speeds up your next attack"
	return "\nNOTE: always: rules only"


## Points the rule's loop costs, after the condition discount, class trait and For Loop gem.
func _loop_cost(rule: ProgramRule, limits: SkillProgramLimits) -> float:
	return rule.loop.cost(limits.loop_cost_mult()) * rule.cost_multiplier() * limits.rule_cost_mult(rule) \
		* limits.buff_cost_mult()


## FOR:   for i in range(N):        WHILE:   cast(max=N)
func _loop_line(rule: ProgramRule, limits: SkillProgramLimits) -> void:
	var lp := rule.loop
	var cap := limits.loop_cap()
	var parts := _code_line(rule, "+", COL_BUFF)
	var code: HBoxContainer = parts[1]
	var step := func(d: int) -> void:
		lp.count = clampi(lp.count + d, 1, cap)
		_changed()
	var cost := _loop_cost(rule, limits)
	if lp.mode == ProgramLoop.Mode.FOR:
		code.add_child(_tok("    for ", COL_KEYWORD))
		code.add_child(_tok("i", COL_VAR))
		code.add_child(_tok(" in ", COL_KEYWORD))
		code.add_child(_tok("range", COL_FN))
		code.add_child(_tok("(", COL_OP))
		code.add_child(_num_tok(str(lp.count), "repeats (1 to %d)" % cap, step))
		code.add_child(_tok("):", COL_OP))
		code.add_child(_comment_tok("%d repeat%s, costs %.1f" % [lp.count, "" if lp.count == 1 else "s", cost]))
	else:
		code.add_child(_tok("    cast", COL_FN))
		code.add_child(_tok("(", COL_OP))
		code.add_child(_tok("max=", COL_OP))
		code.add_child(_num_tok(str(lp.count), "most repeats (1 to %d)" % cap, step))
		code.add_child(_tok(")", COL_OP))
		code.add_child(_comment_tok("repeats while true, costs %.1f" % cost))
	parts[0].tooltip_text = _loop_tip(lp.mode, limits) + "\nClick the number to change the repeats.\nDrag out or right-click to delete the loop."
	_make_line_interactive(parts[0], rule, {"kind": "loop"})
	_mark(parts, rule, rule.loop)


## The  cast()  line at the end of a for loop's body.
func _cast_line(rule: ProgramRule, indent: String) -> void:
	var parts := _code_line(rule)
	var code: HBoxContainer = parts[1]
	code.add_child(_tok(indent + "cast", COL_FN))
	code.add_child(_tok("()", COL_OP))
	code.add_child(_comment_tok("the skill again"))
	_make_line_interactive(parts[0], rule, {})


## break  at the end of an if block in a loop rule: the loop stops when that if is true.
func _break_line(rule: ProgramRule, b: ProgramBranch, indent: String) -> void:
	var parts := _code_line(rule, "-", COL_DRAW)
	var code: HBoxContainer = parts[1]
	code.add_child(_tok(indent + "break", COL_KEYWORD))
	code.add_child(_comment_tok("stops the loop. loop costs x%.2f" % ProgramLoop.BREAK_COST_MULT))
	parts[0].tooltip_text = "break\nStops the loop when this if is true.\nLOOP: checked after each cast or repeat lands\nCOST: the loop costs x%.2f\nDrag out or right-click to delete." % ProgramLoop.BREAK_COST_MULT
	_make_line_interactive(parts[0], rule, {"kind": "break"}, b)
	_mark(parts, rule, b)


func _loop_tip(mode: ProgramLoop.Mode, limits: SkillProgramLimits) -> String:
	var head := "for range(N)\nRepeats the skill N times after it lands." if mode == ProgramLoop.Mode.FOR \
		else "while ...: cast(max=N)\nRepeats while the rule's conditions stay true, up to N.\nNOTE: needs a condition that changes mid-cast"
	var per := ProgramLoop.FOR_COST if mode == ProgramLoop.Mode.FOR else ProgramLoop.WHILE_COST
	return "%s\nCOST: %.1f points per %s · each repeat uses %d%% of the skill's mana\nLOOP: each repeat deals x%.2f damage · at most %d per cast · the rule's lines only change the repeats\nTIP: add  if hit_nothing:  break  to stop early" % [
		head, per * limits.loop_cost_mult(), "repeat" if mode == ProgramLoop.Mode.FOR else "max repeat",
		roundi(ProgramLoop.MANA_FRACTION * limits.repeat_mana_mult() * 100.0), ProgramLoop.FALLOFF, limits.loop_cap()]


func _new_rule_line(owner_id: String) -> void:
	var parts := _code_line(null, "+", COL_OK)
	var line: Control = parts[0]
	var code: HBoxContainer = parts[1]
	var hint := _comment_tok("drop a snippet here to start a new rule")
	hint.add_theme_color_override("font_color", Color(COL_OK, 0.85))
	code.add_child(hint)
	# Green, so it's plain where snippets go; brighter while the mouse (or a drag) is over it
	var sb := line.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = Color(COL_OK, 0.07)
		sb.border_color = Color(COL_OK, 0.55)
		sb.border_width_left = 2
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		line.mouse_entered.connect(func() -> void:
			sb.bg_color = Color(COL_OK, 0.18)
			sb.border_color = COL_OK)
		line.mouse_exited.connect(func() -> void:
			sb.bg_color = Color(COL_OK, 0.07)
			sb.border_color = Color(COL_OK, 0.55))
	if owner_id == _owner or _new_rule_ctrl == null:
		_new_rule_ctrl = line                # the tutorial points at the open file's
	line.set_drag_forwarding(Callable(), _can_drop_new_rule, _drop_new_rule.bind(owner_id))
	line.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_selected = null                 # the next snippet click starts a new rule
			_owner = owner_id                # ...in this file
			_queue_rebuild())


func _comment_line(text: String) -> void:
	var parts := _code_line(null)
	(parts[1] as HBoxContainer).add_child(_comment_tok(text.trim_prefix("# ")))


## An empty line. After a rule it still belongs to that rule, so drops on it land there.
func _blank_line(rule: ProgramRule) -> void:
	var parts := _code_line(rule)
	(parts[1] as HBoxContainer).add_child(_tok(" ", COL_OP))
	if rule != null:
		_make_line_interactive(parts[0], rule, {})


## One editor line: [line number][gutter marker][code...]. Returns [line, code HBox].
func _code_line(rule: ProgramRule, marker := "", marker_col := Color.WHITE) -> Array:
	_line_no += 1
	var selected := rule != null and rule == _selected
	var line := PanelContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(panel.accent, 0.08) if selected else Color(0, 0, 0, 0)
	sb.border_color = panel.accent
	sb.border_width_left = 2 if selected else 0
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	line.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 0)
	line.add_child(row)

	var num := _tok(str(_line_no), COL_GUTTER)
	num.custom_minimum_size.x = 26.0 * _k()
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(num)
	var mark := _tok(marker, marker_col)
	mark.custom_minimum_size.x = 16.0 * _k()
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(mark)
	var code := HBoxContainer.new()
	code.mouse_filter = Control.MOUSE_FILTER_PASS
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.add_theme_constant_override("separation", 0)
	row.add_child(code)
	_rules_box.add_child(line)
	return [line, code]


## Lines of a rule: drops go to the rule, a click selects it, and lines with `info`
## (a condition, an effect, an if block...) can be dragged away or right-clicked to delete them.
## `branch`: the if block the line belongs to; drops on it go into the block.
func _make_line_interactive(line: Control, rule: ProgramRule, info: Dictionary, branch: ProgramBranch = null) -> void:
	var drag_func := Callable()
	if branch != null:
		info["branch"] = branch
	if info.has("kind"):
		info["src"] = "rule"
		info["rule"] = rule
		drag_func = func(_pos: Vector2) -> Variant:
			line.set_drag_preview(_drag_preview(line))
			return info
	line.set_drag_forwarding(drag_func, _can_drop_on_rule.bind(rule), _drop_on_rule.bind(rule, info))
	line.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton):
			return
		if ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed and not get_viewport().gui_is_dragging():
			if _selected != rule or _owner != rule.owner:
				_selected = rule
				_owner = rule.owner              # its file is the open one (its knobs in SNIPPETS)
				_queue_rebuild()
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed and info.has("kind"):
			_remove_block(info)
			line.accept_event())


func _delete_rule_button(rule: ProgramRule) -> Button:
	var b := _code_button("del", "Delete this whole rule.")
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.pressed.connect(func() -> void:
		_draft().rules.erase(rule)
		_changed())
	return b


# ---------- TOKENS ----------
func _tok(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if panel._font:
		l.add_theme_font_override("font", panel._font)
	l.add_theme_font_size_override("font_size", roundi(_sz(CODE_SIZE) * panel.font_scale))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A trailing "# comment" that fills the rest of the line and is cut with "..." if too long.
## Hovering it shows `tip`, or (no tip) the whole comment while it is cut (ScriptTooltip.CUT_META).
func _comment_tok(text: String, tip := "") -> Label:
	var l := _tok(("  # " + text) if text != "" else "", COL_COMMENT)
	_shrinkable(l)
	if text != "":
		l.mouse_filter = Control.MOUSE_FILTER_PASS   # drags and clicks still reach the line
		if tip != "":
			l.tooltip_text = tip
		else:
			l.set_meta(ScriptTooltip.CUT_META, true)
	return l


## An editable number: click = one step up, right-click = down, mouse wheel = up / down.
func _num_tok(text: String, what: String, on_step: Callable) -> Control:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.tooltip_text = "%s\nclick: up   right-click: down   wheel: up / down" % what
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COL_NUM, 0.10)
	sb.border_color = Color(COL_NUM, 0.55)
	sb.border_width_bottom = 1
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	box.add_theme_stylebox_override("panel", sb)
	box.add_child(_tok(text, COL_NUM))
	box.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton):
			return
		var step := 0
		if ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed and not get_viewport().gui_is_dragging():
			step = 1
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			step = -1
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			step = 1
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			step = -1
		elif ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			box.accept_event()                  # keep the press from selecting the line twice
			return
		if step != 0:
			on_step.call(step)
			box.accept_event())
	return box


func _code_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	if panel._font:
		b.add_theme_font_override("font", panel._font)
	b.add_theme_font_size_override("font_size", roundi(_sz(12) * panel.font_scale))
	b.add_theme_color_override("font_color", COL_FN)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(COL_GUTTER, 0.7))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(COL_FN, 0.06)
	normal.border_color = Color(COL_FN, 0.35)
	normal.set_border_width_all(1)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(COL_FN, 0.18)
	hover.border_color = COL_FN
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0, 0, 0, 0)
	disabled.border_color = Color(COL_GUTTER, 0.3)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	return b


# ---------- RIGHT: SNIPPETS ----------
## SNIPPETS, in the order a rule is built, one foldable section each (folds are remembered,
## Settings "layout/snippet_folds"):
##   KNOBS        what changes: the open file's knobs, "any rule" then "always: only"
##   CONDITIONS   when: "per cast", "per hit", then each socketed support's own blocks
##   LOOPS & IF   for, while, if, break and the conditions about repeats (killed, hit_nothing...)
##   REGISTRY     its pieces (Strategist)
##   ROUTINES     call name() (Engineer)
## Each snippet shows its key number on the right (a knob's step, a condition's discount), and
## what can't go into the selected rule is faded, with the reason in its hint.
func _build_palette() -> void:
	_clear(_palette_box)
	_snippets.clear()
	_pal_into = null
	var limits := _limits()
	if limits == null:
		return
	if _owner == KERNEL_FILE:
		_kernel_palette()
		return
	_update_tab_buttons()
	var defense := _palette_tab == "defense"
	var sel: ProgramRule = _selected if _selected != null and is_instance_valid(_selected) else null

	# --- KNOBS ---
	var knobs := limits.knobs_for(_knob_owner(_owner)).filter(func(k: SkillKnob) -> bool:
		return k.defensive == defense and k.kind != SkillKnob.Kind.VARIABLE)
	_section("knobs", "KNOBS  %s" % _owner_file(_owner), knobs.size())
	if knobs.is_empty():
		_pal_add(_comment_tok("nothing to change" if not defense else "no defensive knobs here"))
	var any_rule := knobs.filter(func(k: SkillKnob) -> bool: return not _always_only(k, limits))
	var only_always := knobs.filter(func(k: SkillKnob) -> bool: return _always_only(k, limits))
	for group in [["any rule", any_rule, "any rule\nThese knobs work in always: and when rules, and in loops.\nHIT: in a per-hit rule only damage, leech, barrier, guard and support knobs work"],
			["always: only", only_always, "always: only\nRead before the cast starts, so they only work in an always: rule without a loop.\n    always:\n        attack_speed += 5%"]]:
		if (group[1] as Array).is_empty():
			continue
		if not any_rule.is_empty() and not only_always.is_empty():
			_pal_add(_comment_tok(group[0], group[2]))
		for knob: SkillKnob in group[1]:
			var tip := "%s\n+1 step: %s\n%s\n%s" % [
				knob.display_name, knob.describe(1), _step_price_note(knob), _knob_usage_note(knob)]
			if knob.kind == SkillKnob.Kind.STAT:
				tip += _stat_note(knob, limits)
			tip += _knob_limits_note(knob)
			var knob_snippet := _snippet(String(knob.id), COL_VAR,
				{"src": "palette", "kind": "effect", "knob": knob.id}, tip,
				knob.describe(1).trim_prefix(knob.display_name).strip_edges() + "/step",
				_knob_misfit(knob, sel, limits))
			_snippets["knob:" + String(knob.id)] = knob_snippet
			_pal_add(knob_snippet)

	# --- CONDITIONS ---
	var per_cast: Array[String] = []
	var per_hit: Array[String] = []
	var loop_conds: Array[String] = []
	var by_gem := {}                                   # support id -> [condition type ids]
	for type_id in ProgramConditions.TYPES.keys():
		var sample := ProgramConditions.create(type_id)
		if sample.defensive() != defense or not limits.allows("cond:" + type_id):
			continue                                   # wrong tab, or above the player's rank
		if sample.modular():
			continue                                   # listed under REGISTRY
		var gem_id := sample.required_support()
		if gem_id != "":
			if limits.support_ids.has(gem_id):
				if not by_gem.has(gem_id):
					by_gem[gem_id] = []
				by_gem[gem_id].append(type_id)
			continue                                   # not socketed: not offered
		if sample.needs_loop():
			loop_conds.append(type_id)                 # listed under LOOPS & IF
		elif sample.scope() == ProgramCondition.Scope.HIT:
			per_hit.append(type_id)
		else:
			per_cast.append(type_id)
	var gem_count := 0
	for g in by_gem:
		gem_count += (by_gem[g] as Array).size()
	if per_cast.size() + per_hit.size() + gem_count > 0:
		_section("conditions", "CONDITIONS", per_cast.size() + per_hit.size() + gem_count)
		for group in [["per cast", per_cast, "per cast\nChecked once, when you use the skill. If true, the whole cast gets the rule's lines.\n    when enemies_nearby(3, 4.0m):\n        radius += 1.0m"],
				["per hit", per_hit, "per hit\nChecked on each enemy the skill hits. Only the hits where it's true get the rule's lines.\nHIT: only damage, leech, barrier, guard and support effects\n    when target_life_below(30%):\n        damage += 20%"]]:
			if (group[1] as Array).is_empty():
				continue
			_pal_add(_comment_tok(group[0], group[2]))
			for type_id in group[1]:
				var cond_snippet := _condition_snippet(type_id, ProgramConditions.create(type_id), COL_FN, "")
				_snippets["cond:" + type_id] = cond_snippet
				_pal_add(cond_snippet)
		for gem_id in limits.support_ids:              # one group per socketed support, in socket order
			if not by_gem.has(gem_id):
				continue
			var def: SupportGemDefinition = SkillGemRegistry.get_support_gem(gem_id)
			var gem_name := def.display_name.trim_suffix(" Support") if def != null else gem_id
			_pal_add(_gem_header(gem_name))
			for type_id in by_gem[gem_id]:
				var gem_snippet := _condition_snippet(type_id, ProgramConditions.create(type_id), COL_GEM, gem_name)
				_snippets["cond:" + type_id] = gem_snippet
				_pal_add(gem_snippet)

	# --- LOOPS & IF ---
	var loops := not defense and limits.allows("loop")
	var ifs := limits.allows("if")
	if loops or ifs:
		_section("loops", "LOOPS & IF" if loops else "IF", (3 + loop_conds.size() if loops else 0) + (1 if ifs else 0))
		if loops:
			_pal_add(_snippet("for range()", COL_KEYWORD, {"src": "palette", "kind": "loop", "mode": ProgramLoop.Mode.FOR},
				_loop_tip(ProgramLoop.Mode.FOR, limits) + "\nDrag into a rule, or click to add.",
				"%.1f pt/repeat" % (ProgramLoop.FOR_COST * limits.loop_cost_mult())))
			_pal_add(_snippet("while", COL_KEYWORD, {"src": "palette", "kind": "loop", "mode": ProgramLoop.Mode.WHILE},
				_loop_tip(ProgramLoop.Mode.WHILE, limits) + "\nDrag into a rule with a condition, or click to add.",
				"%.1f pt/repeat" % (ProgramLoop.WHILE_COST * limits.loop_cost_mult()),
				"" if sel == null or not sel.is_always() else "the selected rule has no condition: a while needs one"))
		if ifs:
			_pal_add(_snippet("if", COL_KEYWORD, {"src": "palette", "kind": "branch"},
				"if block\nLines that apply only when the rule fires AND the if is true.\n    when every_nth_cast(3):\n        if enemies_nearby(3, 4.0m):\n            radius += 1.0m\nTIP: fewer blocks than a second rule\nLOOP: checked after each repeat lands · can hold break\nDrop it on a rule, then a condition on its if line, then knobs below.",
				"nested"))
		if loops:
			_pal_add(_snippet("break", COL_KEYWORD, {"src": "palette", "kind": "break"},
				"break\nStops a loop early when its if is true.\n    if hit_nothing:\n        break\nCOST: the loop costs x%.2f\nDrop it on an if line in a loop rule (on the rule itself: starts a new if)." % ProgramLoop.BREAK_COST_MULT,
				"loop x%.2f" % ProgramLoop.BREAK_COST_MULT,
				"" if sel == null or sel.loop != null else "the selected rule has no loop"))
			if not loop_conds.is_empty():
				_pal_add(_comment_tok("about repeats", "about repeats\nThese read how the last cast or repeat went, so they only work in a loop rule's if.\n    for range(3):\n        if hit_nothing:\n            break\nLOOP: checked after each cast or repeat lands"))
				for type_id in loop_conds:
					var lc := _condition_snippet(type_id, ProgramConditions.create(type_id), COL_FN, "")
					_snippets["cond:" + type_id] = lc
					_pal_add(lc)

	# --- REGISTRY ---
	if limits.allows("knob:" + String(ScriptRegisters.WRITE_KNOB)):   # on both tabs: my_life_below() can count too
		_section("registry", "REGISTRY", -1)
		_add_variable_snippets()

	# --- ROUTINES ---
	if limits.allows("call") and _owner != ROUTINES_FILE:
		var rts := _routines()
		_section("routines", "ROUTINES", rts.size())
		for i in rts.size():
			var rt: ProgramRoutine = rts[i]
			var what := "empty: write it in routines.gd" if rt.is_empty() else rt.body.describe(limits).trim_prefix("ALWAYS -> ")
			var call_snippet := _snippet("call %s()" % rt.routine_name, COL_KEYWORD, {"src": "palette", "kind": "call", "routine": i},
				"Runs %s() where you drop it: %s\n1 block, whatever it holds; this skill pays for its lines.\nDrop it in a rule of the skill's own file (or its if), or click to add." % [rt.routine_name, what],
				"1 block")
			_snippets["call:%d" % i] = call_snippet
			_pal_add(call_snippet)
	_pal_into = null


## Adds to the SNIPPETS section being filled (or the list itself).
func _pal_add(c: Control) -> void:
	(_pal_into if _pal_into != null and is_instance_valid(_pal_into) else _palette_box).add_child(c)


## Starts a foldable SNIPPETS section: a header "v TITLE (count)" (count < 0: none shown) that
## folds it on click, remembered in Settings "layout/snippet_folds". Later _pal_add calls fill it.
func _section(key: String, title: String, count: int) -> void:
	_pal_into = null
	var folds: Dictionary = Settings.get_value("layout", "snippet_folds")
	var folded := bool(folds.get(key, false)) if folds != null else false
	if _palette_box.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 6.0 * _k()
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_palette_box.add_child(gap)
	var head := Button.new()
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.clip_text = true                          # a long file name can't widen the list
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.custom_minimum_size.x = 1.0
	head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if panel._font:
		head.add_theme_font_override("font", panel._font)
	head.add_theme_font_size_override("font_size", roundi(_sz(12) * panel.font_scale))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		head.add_theme_color_override(state, panel.accent if state == "font_color" else Color.WHITE)
	var line := StyleBoxFlat.new()
	line.bg_color = Color(panel.accent, 0.08)
	line.border_color = Color(panel.accent, 0.45)
	line.border_width_bottom = 1
	line.content_margin_left = 4
	for st in ["normal", "hover", "pressed"]:
		head.add_theme_stylebox_override(st, line)
	var label := "%s%s" % [title, ("  (%d)" % count) if count >= 0 else ""]
	head.text = ("> " if folded else "v ") + label
	head.tooltip_text = "Click to fold or unfold this section."
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	body.visible = not folded
	body.set_meta(&"section_head", head)
	body.set_meta(&"section_key", key)
	body.set_meta(&"section_label", label)
	head.pressed.connect(func() -> void: _fold(body, body.visible))
	_palette_box.add_child(head)
	_palette_box.add_child(body)
	_pal_into = body


## Folds (or unfolds) a SNIPPETS section and remembers it.
func _fold(body: Control, fold: bool) -> void:
	body.visible = not fold
	var head := body.get_meta(&"section_head") as Button
	if head != null:
		head.text = ("> " if fold else "v ") + String(body.get_meta(&"section_label", ""))
	var folds: Dictionary = (Settings.get_value("layout", "snippet_folds") as Dictionary).duplicate() \
			if Settings.get_value("layout", "snippet_folds") is Dictionary else {}
	folds[String(body.get_meta(&"section_key", ""))] = fold
	Settings.set_value("layout", "snippet_folds", folds)


## Unfolds the section a snippet is in (a tutorial hint is pointing at it).
func _reveal(snippet: Control) -> void:
	var n := snippet.get_parent()
	while n != null and n != _palette_box:
		if n.has_meta(&"section_key") and not (n as Control).visible:
			_fold(n as Control, false)
		n = n.get_parent()


## True for a knob that only works in an always: rule (read before the cast starts).
static func _always_only(knob: SkillKnob, limits: SkillProgramLimits) -> bool:
	return knob.always_only or (knob.kind == SkillKnob.Kind.STAT and not limits.per_hit_attack_speed(knob))


## Why `knob` can't go into the selected rule ("" = it can, or nothing is selected).
func _knob_misfit(knob: SkillKnob, sel: ProgramRule, limits: SkillProgramLimits) -> String:
	if sel == null:
		return ""
	if _always_only(knob, limits) and (not sel.is_always() or sel.loop != null):
		return "only works in an always: rule without a loop, and the selected rule isn't one"
	if sel.scope() == ProgramCondition.Scope.HIT and knob.kind != SkillKnob.Kind.DAMAGE \
			and not SkillProgramLimits.per_hit_knob(knob) and not limits.per_hit_any_knob() \
			and not limits.per_hit_attack_speed(knob):
		return "the selected rule is per hit: it can only change damage, leech, barrier, guard and support effects"
	return ""


## The registry pieces: add and remove, the membership checks, and the size with what it can be
## compared with. Every piece makes or changes a whole line, so a script is never left
## half-written (_add_counter_piece).
func _add_variable_snippets() -> void:
	_pal_add(_comment_tok("a set of enemies", "registry\nA set of enemies your script remembers between casts.\nAdd enemies with registry.add(target), then check them with target in registry or registry.size.\nNOTE: free: no points or blocks"))
	var free := "\nFree: no points or blocks. It keeps enemies between casts, and clears %d seconds after a fight; an enemy that dies leaves it." % int(ScriptRegisters.CLEAR_AFTER)
	_add_piece_row([
		["registry.add(target)", {"src": "palette", "kind": "set_write", "op": 0},
			"Adds enemies to the registry. In always: or a WHEN, every enemy the cast hits; in a per-hit rule, the enemy being hit.\nDrop on a registry line to make it add." + free],
		["registry.remove(target)", {"src": "palette", "kind": "set_write", "op": 1},
			"Takes enemies out of the registry, the same way add puts them in.\nDrop on a registry line to make it remove." + free],
	])
	var member_tip := "%s\nChecked per hit, against the enemy being hit, so this rule's buffs only land on those hits (per-hit rules can change damage, leech, barrier, guard and support effects that happen on that hit or kill: explosions, breakpoints, tremors, charge, error damage, forks. Barrier and guard come once per cast when a hit lands). A hit sees the registry from before it landed.\n%s Drop on a registry check to change it."
	var in_cost := "Buffs in this rule cost x%.2f if your script spends marks with registry.remove(target): each mark pays out once. Without a remove a mark lasts all fight, so they cost x%.2f." % [
		VarCondition.COST_SPENT, VarCondition.COST_KEPT]
	_add_piece_row([
		["target in registry", {"src": "palette", "kind": "member", "op": 0},
			member_tip % ["When the enemy being hit is in the registry.", in_cost]],
		["target not in registry", {"src": "palette", "kind": "member", "op": 1},
			member_tip % ["When the enemy being hit is not in the registry yet.", "Buffs in this rule cost x%.2f." % VarCondition.COST_MULT]],
	])
	var size_pieces: Array = [["registry.size", {"src": "palette", "kind": "size"},
		"How many enemies are in the registry. Checked per cast, and it grows as hits land, so while registry.size < 3: stops itself.\nDrop on a knob's value to make that buff grow with it. Anywhere else it adds when registry.size >= 3."]]
	for i in ScriptRegisters.OPS.size():
		size_pieces.append([ScriptRegisters.OPS[i], {"src": "palette", "kind": "compare_op", "op": i},
			"%s\nAdds when registry.size %s 3, or changes the operator of the registry check you drop it on. Buffs in this rule cost x%.2f." % [
				ScriptRegisters.OPS[i], ScriptRegisters.OPS[i], VarCondition.COST_MULT]])
	_add_piece_row(size_pieces)
	var limits := _limits()
	if limits == null or not limits.allows("sort"):
		return
	_pal_add(_comment_tok("sorting", "sorting\nPuts the registry in order, then picks a place in it.\nPlaces count from 0: registry[0] is the first, registry[1] the second, registry[-1] the last, registry[:3] the first three.\nWithout a sort the registry is oldest first.\nNOTE: free: no points or blocks"))
	var sort_pieces: Array = []
	for k in ScriptRegisters.SORT_KEYS.size():
		var order := k * 2
		sort_pieces.append(["sort(key=%s)" % ScriptRegisters.SORT_KEYS[k], {"src": "palette", "kind": "sort", "order": order},
			"registry.sort(key=%s): puts the registry in order, %s. Click the key on the line to reverse it.
Then registry[0] is the first in that order. Without a sort the registry is oldest first.
Drop on a sort line to change its key. Free: no points or blocks." % [
				ScriptRegisters.SORT_KEYS[k], ScriptRegisters.sort_meaning(order)]])
	_add_piece_row(sort_pieces)
	var pos_pieces: Array = []
	for p in ScriptRegisters.POSITIONS.size():
		var sample := RegistryPositionCondition.new()
		sample.pos = p
		var place: String = ScriptRegisters.POSITIONS[p]
		pos_pieces.append(["%s %s" % [place, ScriptRegisters.POSITION_WORDS[place]], {"src": "palette", "kind": "position", "pos": p},
			"%s
Places count from 0, so [0] is the first. With registry.sort(key=hp), this is %s.
Checked per hit, against the enemy being hit, in the registry's order (registry.sort, or oldest first). %s Buffs in this rule cost x%.2f.
Drop on a registry[...] check to change it." % [
				sample.describe().trim_prefix("WHEN "),
				ScriptRegisters.position_meaning(p, 2),
				"One of the first few." if ScriptRegisters.is_slice(p) else "Only that one place.",
				sample.cost_multiplier()]])
	_add_piece_row(pos_pieces)


## Small snippets side by side: each entry is [text, drag data, tooltip]. A piece longer than
## PIECE_FLOW_CHARS gets a list row of its own (cut with "..." when narrow): side by side it would
## set the list's minimum width and push every snippet's right side out of view.
const PIECE_FLOW_CHARS := 11

func _add_piece_row(pieces: Array) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 3)
	row.add_theme_constant_override("v_separation", 2)
	for piece in pieces:
		var block := _snippet(piece[0], COL_VAR, piece[1], piece[2])
		_snippets["piece:%s:%s" % [piece[1]["kind"], piece[0]]] = block
		if (piece[0] as String).length() > PIECE_FLOW_CHARS:
			_pal_add(block)
			continue
		var l := block.get_child(0) as Label        # as wide as its text: there's no list row to fill
		l.clip_text = false
		l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		l.custom_minimum_size.x = 0
		row.add_child(block)
	if row.get_child_count() > 0:
		_pal_add(row)
	else:
		row.free()


func _set_palette_tab(tab_name: String) -> void:
	if _palette_tab == tab_name:
		return
	_palette_tab = tab_name
	_queue_rebuild()


func _update_tab_buttons() -> void:
	for tab_name in _tab_btns:
		var b: Button = _tab_btns[tab_name]
		var active: bool = tab_name == _palette_tab
		b.add_theme_color_override("font_color", panel.accent if active else COL_GUTTER)
		var st := (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
		st.border_color = panel.accent if active else Color(COL_GUTTER, 0.4)
		st.bg_color = Color(panel.accent, 0.15) if active else Color(0, 0, 0, 0)
		b.add_theme_stylebox_override("normal", st)


## The tab a snippet id ("cond:<type>" / "knob:<id>") is listed under, or "" if unknown.
func _tab_of(snippet_id: String) -> String:
	if snippet_id.begins_with("cond:"):
		var c := ProgramConditions.create(snippet_id.trim_prefix("cond:"))
		return "" if c == null else ("defense" if c.defensive() else "offense")
	if snippet_id.begins_with("knob:"):
		var limits := _limits()
		var k := limits.get_knob(StringName(snippet_id.trim_prefix("knob:"))) if limits != null else null
		return "" if k == null else ("defense" if k.defensive else "offense")
	return ""

func _condition_snippet(type_id: String, sample: ProgramCondition, col: Color, gem_name: String) -> Control:
	var label := (sample.keyword() + " " + _fn_name(sample)) if sample.keyword() != "" else _fn_name(sample) + "()"
	var tip := "%s\nCOST: buffs x%.2f · rarer is cheaper\nDrag into a rule, or click to add." % [sample.describe(), sample.cost_multiplier()]
	if sample.modular():
		label = sample.describe().trim_prefix("WHEN ")
		tip = "Reads the registry\nHIT: target in registry is checked per hit · registry.size per cast\nCOST: buffs x%.2f\nDrag into a rule, or click to add. Click its parts to change them." % sample.cost_multiplier()
	if gem_name != "":
		tip = "From the %s gem.\n%s" % [gem_name, tip]
	return _snippet(label, col, {"src": "palette", "kind": "condition", "type": type_id}, tip,
		"x%.2f" % sample.cost_multiplier())


## A support gem's section title in the snippets list: a gem marker, its name and a rule.
func _gem_header(gem_name: String) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4.0 * _k()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(gap)
	var title := _tok("<> " + gem_name.to_lower().replace(" ", "_") + ".gd", COL_GEM)
	title.add_theme_font_size_override("font_size", roundi(_sz(12) * panel.font_scale))
	_shrinkable(title)
	box.add_child(title)
	var rule := ColorRect.new()
	rule.color = Color(COL_GEM, 0.45)
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	return box


## `side`: a short note at its right (a knob's step, a condition's discount). `misfit`: why it
## can't go into the selected rule ("" = it can); it is faded and its hint says why.
func _snippet(text: String, col: Color, data: Dictionary, tip: String, side := "", misfit := "") -> Control:
	var block := PanelContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_STOP
	block.mouse_default_cursor_shape = Control.CURSOR_DRAG
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.07)
	sb.border_color = Color(col, 0.6)
	sb.border_width_left = 2
	if col == COL_GEM:                              # gem blocks: outlined all round
		sb.set_border_width_all(1)
		sb.border_width_left = 3
		sb.bg_color = Color(col, 0.12)
	sb.content_margin_left = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	block.add_theme_stylebox_override("panel", sb)
	var l := _tok(text, col)
	_shrinkable(l)
	# NEW: a block a rank just unlocked, until its hint is read or it is used (NewBlocks)
	var unlocked := NewBlocks.block_of(data)
	var is_new := NewBlocks.is_new(get_tree(), unlocked, text)
	if side != "" and not is_new:                   # the NEW badge takes that spot while it shows
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", roundi(4 * _k()))
		row.add_child(l)
		var sl := _tok(side, COL_COMMENT)
		sl.add_theme_font_size_override("font_size", roundi(_sz(9) * panel.font_scale))
		sl.size_flags_horizontal = Control.SIZE_SHRINK_END
		sb.content_margin_right = 4
		row.add_child(sl)
		block.add_child(row)
	else:
		block.add_child(l)
	block.set_meta(&"snippet", text)
	if misfit != "":
		block.modulate.a = 0.42
		var nl := tip.find("\n")
		tip = (tip + "\nNOTE: " + misfit) if nl < 0 else tip.substr(0, nl) + "\nNOTE: " + misfit + tip.substr(nl)
	block.tooltip_text = tip
	var seen := func() -> void: pass
	if is_new:
		seen = _add_new_badge(block, l, sb, unlocked, text)
	block.set_drag_forwarding(
		func(_pos: Vector2) -> Variant:
			seen.call()
			block.set_drag_preview(_drag_preview(block))
			return data,
		_can_drop_on_palette, _drop_on_palette)
	# A click (press + release without dragging) adds the snippet to the selected rule
	block.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT \
				and not get_viewport().gui_is_dragging():
			seen.call()
			_add_from_palette(data, _selected))
	return block


## Puts a NEW badge at the right of a snippet, and returns what takes it off for good: called on
## a click or a drag, and by itself once the pointer has rested on the snippet long enough for its
## hint to show.
func _add_new_badge(block: Control, label: Label, sb: StyleBoxFlat, unlocked: String, text: String) -> Callable:
	var k := _k()
	var badge := Label.new()
	badge.text = "NEW"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", roundi(_sz(9) * panel.font_scale))
	badge.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
	var pill := StyleBoxFlat.new()
	pill.bg_color = COL_NEW
	pill.set_corner_radius_all(roundi(3 * k))
	pill.content_margin_left = 3 * k
	pill.content_margin_right = 3 * k
	badge.add_theme_stylebox_override("normal", pill)
	var w := 30.0 * k
	var old_margin := sb.content_margin_right
	sb.content_margin_right = old_margin + w + 4.0 * k        # room at the right, so it never covers the text
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.anchor_top = 0.5
	badge.anchor_bottom = 0.5
	badge.offset_left = 4.0 * k
	badge.offset_right = 4.0 * k + w
	badge.offset_top = -7.0 * k
	badge.offset_bottom = 7.0 * k
	label.add_child(badge)
	var done := [false]
	var seen := func() -> void:
		if done[0]:
			return
		done[0] = true
		NewBlocks.mark_seen(get_tree(), unlocked, text)
		if is_instance_valid(badge):
			badge.queue_free()
		sb.content_margin_right = old_margin
	var hovering := [false]
	block.mouse_exited.connect(func() -> void: hovering[0] = false)
	block.mouse_entered.connect(func() -> void:
		hovering[0] = true
		var wait := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5)) + 0.6
		get_tree().create_timer(wait).timeout.connect(func() -> void:
			if hovering[0] and is_instance_valid(block) and block.is_visible_in_tree():
				seen.call()))                  # rested on it: the hint has been up a moment
	return seen


## The snippet texts, in order (for tests and debugging).
func palette_items() -> Array[String]:
	var out: Array[String] = []
	for c in _palette_box.find_children("*", "PanelContainer", true, false):
		if c.has_meta(&"snippet"):
			out.append(String(c.get_meta(&"snippet")))
	return out


# ---------- DRAG AND DROP ----------
func _can_drop_on_rule(_pos: Vector2, data: Variant, _rule: ProgramRule) -> bool:
	return data is Dictionary and data.get("src") in ["palette", "rule"]


## `line`: what the drop landed on ({"kind": "condition" / "effect", ...}, empty for a rule's head).
func _drop_on_rule(_pos: Vector2, data: Variant, rule: ProgramRule, line: Dictionary = {}) -> void:
	if data.get("src") == "palette":
		_add_from_palette(data, rule, line)
	elif data.get("rule") != rule or data.get("branch") != line.get("branch"):
		_move_block(data, rule, line)


func _can_drop_new_rule(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("src") in ["palette", "rule"]


func _drop_new_rule(_pos: Vector2, data: Variant, owner_id: String) -> void:
	_owner = owner_id                        # the new rule goes in the file it was dropped in
	if data.get("src") == "palette":
		_add_from_palette(data, null)
	else:
		_move_block(data, null)


func _can_drop_on_palette(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("src") == "rule"


func _drop_on_palette(_pos: Vector2, data: Variant) -> void:
	_remove_block(data)


func _drag_preview(source: Control) -> Control:
	var p := source.duplicate(0) as Control
	p.modulate.a = 0.8
	p.custom_minimum_size.x = minf(source.size.x, 320.0 * _k())
	return p


# ---------- EDITING THE DRAFT ----------
func _new_rule() -> ProgramRule:
	var r := ProgramRule.new()
	r.owner = _owner
	_draft().rules.append(r)
	_selected = r
	return r


## Adds a snippet to `rule` (or to a new rule when null). The same knob twice adds a step.
func _add_from_palette(data: Dictionary, rule: ProgramRule, line: Dictionary = {}) -> void:
	if _sock() == null or _limits() == null:
		return
	if rule == null and _owner == ROUTINES_FILE:         # routines.gd open: into the selected routine
		rule = _selected if _routine_of(_selected) != null else (_routines()[0] as ProgramRoutine).body
	if _routine_of(rule) != null:
		var why := _routine_refusal(data, line, _box(rule, line) != rule)
		if why != "":
			panel._notify(why)
			return
	if data["kind"] == "call" and (rule.owner if rule != null else _owner) != "":
		panel._notify("CALL ROUTINES FROM THE SKILL'S OWN FILE")
		return
	if data["kind"] in ["set_write", "member", "size", "compare_op", "sort", "position"]:
		_add_counter_piece(data, rule, line)
		return
	if data["kind"] == "break" and (rule == null or rule.loop == null):
		panel._notify("ADD A FOR OR WHILE LOOP FIRST")
		return
	if data["kind"] == "effect" and not _knob_fits(data["knob"], rule.owner if rule != null else _owner):
		return
	if rule == null:
		rule = _new_rule()
	var box: Object = _box(rule, line)                 # the rule, or the if block dropped on
	if data["kind"] == "branch":
		rule.branches.append(ProgramBranch.new())
	elif data["kind"] == "condition":
		var c := ProgramConditions.create(data["type"])
		if c != null:
			box.conditions.append(c)
	elif data["kind"] == "loop":
		if rule.loop == null:
			rule.loop = ProgramLoop.make(data["mode"])
		elif rule.loop.mode == data["mode"]:
			rule.loop.count = mini(rule.loop.count + 1, _limits().loop_cap())
		else:
			rule.loop.mode = data["mode"]
	elif data["kind"] == "break":
		_add_break(rule, box as ProgramBranch)
	elif data["kind"] == "call":
		box.effects.append(ProgramEffect.make_call(int(data["routine"])))
	else:
		var existing: ProgramEffect = null
		for e in box.effects:
			if e.knob == data["knob"]:
				existing = e
		if existing != null:
			existing.steps += 1
		else:
			box.effects.append(ProgramEffect.make(data["knob"], 1))
	_selected = rule
	_changed()


## break into `branch` (an if block of `rule`), or into a new if block of `rule` when dropped on
## the rule's own lines: that if's condition comes next.
func _add_break(rule: ProgramRule, branch: ProgramBranch) -> void:
	if branch == null:
		branch = ProgramBranch.new()
		rule.branches.append(branch)
	branch.breaks = true


## Why a snippet can't go into a routine ("" = it can): a routine takes knobs, registry writes and
## if blocks; conditions only inside its if, and no loops or calls.
static func _routine_refusal(data: Dictionary, line: Dictionary, in_if: bool) -> String:
	match data.get("kind"):
		"call":
			return "A ROUTINE CAN'T CALL A ROUTINE"
		"loop", "break":
			return "A ROUTINE CAN'T LOOP: PUT THE LOOP ON THE RULE THAT CALLS IT"
		"condition", "member", "compare_op", "position":
			if not in_if:
				return "A ROUTINE HAS NO CONDITIONS: PUT THEM ON THE RULE THAT CALLS IT, OR IN AN IF"
		"size":
			if not in_if and line.get("effect") == null:
				return "A ROUTINE HAS NO CONDITIONS: PUT THEM ON THE RULE THAT CALLS IT, OR IN AN IF"
	return ""


## Where a drop on `line` of `rule` goes: the if block the line is in, or the rule itself. Both
## have `conditions` and `effects`.
static func _box(rule: ProgramRule, line: Dictionary) -> Object:
	var b: ProgramBranch = line.get("branch") as ProgramBranch
	return b if b != null and rule != null and b in rule.branches else rule


## A registry piece from SNIPPETS. Dropped on a line it fits, it changes that line:
##   add / remove on a registry line swaps the operation; a check on a registry check replaces it;
##   registry.size on a knob's line makes that buff grow with it
## Anywhere else it adds a whole line of its own, so a script is never left half-written.
func _add_counter_piece(data: Dictionary, rule: ProgramRule, line: Dictionary) -> void:
	var limits := _limits()
	var read: VarCondition = line.get("condition") as VarCondition
	var effect: ProgramEffect = line.get("effect") as ProgramEffect
	var write: ProgramEffect = effect if effect != null and ScriptRegisters.is_write(effect.knob) else null
	var branch: ProgramBranch = _box(rule, line) as ProgramBranch
	match data["kind"]:
		"set_write":
			if write != null:
				write.op = data["op"]
			else:
				rule = _add_write(rule, ScriptRegisters.WRITE_OPS[data["op"]], branch)
		"member":
			if read != null:
				read.key = 0
				read.op = data["op"]
			else:
				if rule == null:
					rule = _new_rule()
				_box(rule, line).conditions.append(VarCondition.make("target", ScriptRegisters.MEMBER_OPS[data["op"]]))
		"size":
			if read != null:
				read.key = 1
				read.op = ScriptRegisters.OPS.find(">=")
			elif effect != null and write == null:
				var knob := limits.get_knob(effect.knob)
				if not _can_grow(knob, limits):
					panel._notify("%s CAN'T GROW WITH THE REGISTRY" % String(effect.knob).to_upper())
					return
				effect.ramp = 0
			else:
				if rule == null:
					rule = _new_rule()
				_box(rule, line).conditions.append(VarCondition.make("size", ">=", 3))
		"compare_op":
			if read != null:
				read.key = 1
				read.op = data["op"]
			else:
				if rule == null:
					rule = _new_rule()
				_box(rule, line).conditions.append(VarCondition.make("size", ScriptRegisters.OPS[data["op"]], 3))
		"sort":
			if write != null and ScriptRegisters.is_sort(write):
				write.sort_by = data["order"]
			else:
				if not _knob_fits(ScriptRegisters.WRITE_KNOB, rule.owner if rule != null else _owner):
					return
				if rule == null:
					rule = _new_rule()
				(branch if branch != null else rule).effects.append(ProgramEffect.make_sort(data["order"]))
		"position":
			var at: RegistryPositionCondition = line.get("condition") as RegistryPositionCondition
			if at != null:
				at.pos = data["pos"]
			else:
				if rule == null:
					rule = _new_rule()
				var c := RegistryPositionCondition.new()
				c.pos = data["pos"]
				_box(rule, line).conditions.append(c)
	if rule == null:
		return                                         # a write that doesn't fit this file
	_selected = rule
	_changed()


## Adds registry.add / remove(target) to `rule` (null = a new rule), or to its if block `branch`.
## Returns the rule, null if this file can't.
func _add_write(rule: ProgramRule, op_text: String, branch: ProgramBranch = null) -> ProgramRule:
	if not _knob_fits(ScriptRegisters.WRITE_KNOB, rule.owner if rule != null else _owner):
		return null
	if rule == null:
		rule = _new_rule()
	(branch if branch != null else rule).effects.append(ProgramEffect.make_write(op_text))
	return rule


## False (with a message) when `knob_id` isn't one of `owner_id`'s file's knobs: every file is
## on screen now, so a knob can be dropped into another file's rule.
func _knob_fits(knob_id: StringName, owner_id: String) -> bool:
	var limits := _limits()
	if limits == null:
		return false
	for k in limits.knobs_for(_knob_owner(owner_id)):
		if (k as SkillKnob).id == knob_id:
			return true
	panel._notify("%s ISN'T A KNOB OF %s" % [String(knob_id).to_upper(), _owner_file(owner_id).to_upper()])
	return false


func _detach(info: Dictionary) -> void:
	var from: ProgramRule = info["rule"]
	var box: Object = _box(from, info)
	match info["kind"]:
		"condition":
			box.conditions.erase(info["condition"])
		"effect":
			box.effects.erase(info["effect"])
		"branch":
			from.branches.erase(info.get("branch"))
		"loop":
			from.loop = null
		"break":
			if box is ProgramBranch:
				(box as ProgramBranch).breaks = false
	var b := box as ProgramBranch
	if b != null and b.conditions.is_empty() and b.effects.is_empty() and not b.breaks:
		from.branches.erase(b)                       # an empty if block goes with its last line
	if from.conditions.is_empty() and from.effects.is_empty() and from.loop == null and from.branches.is_empty():
		_draft().rules.erase(from)


## `line`: what the drop landed on, so a line can go into (or out of) an if block of `to`.
func _move_block(info: Dictionary, to: ProgramRule, line: Dictionary = {}) -> void:
	var src: ProgramRule = info["rule"]
	var moved_loop: ProgramLoop = src.loop
	if info["kind"] == "break" and (to == null or to.loop == null):
		panel._notify("ADD A FOR OR WHILE LOOP FIRST")
		return
	var dest_owner := to.owner if to != null else _owner
	if _routine_of(to) != null:
		var into_if := line.get("branch") != null
		if info["kind"] in ["loop", "break"] or (info["kind"] == "condition" and not into_if) \
				or (info["kind"] == "effect" and (info["effect"] as ProgramEffect).is_call()):
			panel._notify("A ROUTINE ONLY TAKES KNOBS, REGISTRY WRITES AND IF BLOCKS")
			return
	if info["kind"] == "effect" and (info["effect"] as ProgramEffect).is_call():
		if dest_owner != "":
			panel._notify("CALL ROUTINES FROM THE SKILL'S OWN FILE")
			return
	elif info["kind"] == "effect" and not _knob_fits((info["effect"] as ProgramEffect).knob, dest_owner):
		return
	var moved_branch: ProgramBranch = info.get("branch") as ProgramBranch
	var dest_branch: ProgramBranch = line.get("branch") as ProgramBranch
	if info["kind"] == "branch" and dest_branch == moved_branch:
		return                                       # dropped on itself
	_detach(info)
	if to == null:
		to = _new_rule()
	var box: Object = dest_branch if dest_branch != null and dest_branch in to.branches else to
	match info["kind"]:
		"condition":
			box.conditions.append(info["condition"])
		"effect":
			box.effects.append(info["effect"])
		"branch":
			to.branches.append(moved_branch)
		"loop":
			to.loop = moved_loop
		"break":
			_add_break(to, box as ProgramBranch)
	_selected = to
	_changed()


func _remove_block(info: Dictionary) -> void:
	_detach(info)
	_changed()


func _changed() -> void:
	_queue_rebuild()


# ---------- TIPS ----------
## The tip line at the top of OUTPUT: "# tip: ...", a button to the guide page that explains it,
## and x to dismiss it. Hidden until a tip shows (ScriptTips).
func _build_tip_row() -> HBoxContainer:
	_tip_row = HBoxContainer.new()
	_tip_row.add_theme_constant_override("separation", 6)
	_tip_row.visible = false
	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_label.custom_minimum_size.x = 1.0
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label.add_theme_color_override("font_color", Color(COL_PENDING, 0.9))
	if panel._font:
		_tip_label.add_theme_font_override("font", panel._font)
	_tip_label.add_theme_font_size_override("font_size", roundi(_sz(12) * panel.font_scale))
	_tip_row.add_child(_tip_label)
	_tip_page_btn = _code_button("guide()", "Read more about this in the SCRIPTING GUIDE.")
	_tip_page_btn.pressed.connect(func() -> void:
		if not _tip_shown.is_empty():
			open_guide(_tip_shown["page"]))
	_tip_row.add_child(_tip_page_btn)
	var close_btn := _code_button("x", "Hide this tip. Tips can be turned off in SETTINGS > GAMEPLAY.")
	close_btn.pressed.connect(_hide_tip)
	_tip_row.add_child(close_btn)
	return _tip_row


## Shows the first new tip this draft triggers (each shows once per character). The tip on
## screen stays until a newer one replaces it or the player hides it.
func _update_tip(draft: SkillProgram, v: ProgramValidation, limits: SkillProgramLimits) -> void:
	if _tip_row == null:
		return
	if not ScriptTips.enabled():
		_hide_tip()
		return
	if _tip_hold:
		_tip_hold = false                      # apply()'s tip survives the rebuild after it
		return
	var next := ScriptTips.next_tip(draft, v, limits)
	if not next.is_empty():
		_show_tip(next)


func _show_tip(t: Dictionary) -> void:
	if _tip_row == null:
		return
	_tip_shown = t
	ScriptTips.mark_seen(t["id"])
	_tip_label.text = "# tip: " + String(t["text"])
	var page := 0
	for i in ScriptGuide.PAGES.size():
		if ScriptGuide.PAGES[i][0] == t["page"]:
			page = i + 1
	_tip_page_btn.text = "guide() p.%d" % page if page > 0 else "guide()"
	_tip_row.visible = true


func _hide_tip() -> void:
	_tip_shown = {}
	if _tip_row != null:
		_tip_row.visible = false


## The tip on screen ({} for none), for tests and the tutorial.
func current_tip() -> Dictionary:
	return _tip_shown


# ---------- OUTPUT / APPLY ----------
func _update_status() -> void:
	var s := _sock()
	var limits := _limits()
	var enabled := s != null and limits != null
	for b in [_apply_btn, _revert_btn, _clear_btn]:
		b.disabled = not enabled
	_state = ""
	if not enabled:
		_console.text = _c("// nothing to compile", COL_COMMENT)
		_errors_console.text = _c("// nothing to compile", COL_COMMENT)
		_set_output_alert(0)
		return
	if _owner == KERNEL_FILE:
		_kernel_status()                         # the Null's requests, not the skill's points
		return

	var draft := _draft()
	var v := _validation if _validation != null else _skills().preview_program(_socket, draft, _routines())
	_update_tip(draft, v, limits)
	var lines: Array[String] = []

	# points  [########........]  6.0 / 12.0
	var paid := v.drawback_points + v.point_budget
	var over := v.buff_points > paid + 0.001
	var cap := maxf(maxf(paid, v.buff_points), 1.0)
	var filled := clampi(roundi(16.0 * v.buff_points / cap), 0, 16)
	var bar := "#".repeat(filled) + ".".repeat(16 - filled)
	lines.append("%s points  [lb]%s[rb]  %s" % [_c(">", COL_GUTTER), _c(bar, SkillPanel.COL_WARN if over else COL_OK),
		_c("%.1f / %.1f" % [v.buff_points, paid], SkillPanel.COL_WARN if over else SkillPanel.COL_TEXT)])
	if limits.bonus_steps > 0:
		lines.append("%s knobs   %s %s" % [_c(">", COL_GUTTER), _c("+%d step%s" % [limits.bonus_steps, "" if limits.bonus_steps == 1 else "s"], COL_OK),
			_c("// every knob goes further: " + _step_sources(), COL_COMMENT)])
	if limits.bonus_points > 0.0:
		lines.append("%s bonus   %s %s" % [_c(">", COL_GUTTER), _c("+%s points" % String.num(limits.bonus_points, 1), COL_OK),
			_c("// " + _bonus_sources(), COL_COMMENT)])
	lines.append("%s blocks  %d/%d   rules %d/%d%s" % [_c(">", COL_GUTTER), v.actions_used, v.max_actions,
		draft.rules.size(), limits.max_rules,
		("   " + _c("+%d violet rule: merged" % limits.bonus_rules, COL_VIOLET)) if limits.bonus_rules > 0 else ""])
	if limits.class_trait != null:
		lines.append("%s trait   %s %s" % [_c(">", COL_GUTTER), _c(limits.class_trait.display_name.to_lower(), COL_KEYWORD),
			_c("// " + ", ".join(limits.class_trait.summary()), COL_COMMENT)])

	var has_loop := false
	for rule in draft.rules:
		has_loop = has_loop or rule.loop != null
	if has_loop:
		lines.append("%s loops   %s %s" % [_c(">", COL_GUTTER), _c("max %d repeats" % limits.loop_cap(), COL_KEYWORD),
			_c("// each repeat x%.2f damage, %d%% mana" % [ProgramLoop.FALLOFF,
				roundi(ProgramLoop.MANA_FRACTION * limits.repeat_mana_mult() * 100.0)], COL_COMMENT)])

	if not draft.has_rules():
		lines.append(_c("// add a rule to start. fewer blocks earn an efficiency bonus", COL_COMMENT))
	elif v.tier != null:
		var t := "%s tier    %s %s" % [_c(">", COL_GUTTER), _c(v.tier.display_name.to_lower(), COL_KEYWORD),
			_c("// " + v.tier.description, COL_COMMENT)]
		if v.next_tier != null:
			t += _c("  (%d fewer -> %s)" % [v.actions_to_next_tier, v.next_tier.display_name.to_lower()], COL_COMMENT)
		lines.append(t)
	elif v.next_tier != null:
		lines.append("%s tier    none %s" % [_c(">", COL_GUTTER),
			_c("// %d fewer blocks -> %s" % [v.actions_to_next_tier, v.next_tier.display_name.to_lower()], COL_COMMENT)])

	var dirty := _is_dirty(_socket) or _routines_dirty()
	if _routines_dirty():
		lines.append(_c("// routines.gd changed: apply() saves it for every skill that calls it", COL_PENDING))
	var err_lines: Array[String] = []
	if not v.valid:
		_state = "invalid"
		var count := v.error_count()
		lines.append(_c("x %d error%s: see ERRORS, fix %s to apply()" % [count, "" if count == 1 else "s",
			"it" if count == 1 else "them"], SkillPanel.COL_WARN))
		err_lines.append(_c("x %d error%s: fix %s to apply()" % [count, "" if count == 1 else "s",
			"it" if count == 1 else "them"], SkillPanel.COL_WARN))
		for i in v.issues.size():
			var issue: Dictionary = v.issues[i]
			if issue["kind"] != "error" or issue["dup"]:
				continue
			err_lines.append(_c("  error ", SkillPanel.COL_WARN) + _c(_where(issue, i), COL_FN)
				+ _c(_esc(issue["text"]), SkillPanel.COL_TEXT))
			if issue["hint"] != "":
				err_lines.append(_c("        fix: ", COL_GUTTER) + _c(_esc(issue["hint"]), COL_OK))
	else:
		err_lines.append(_c("// no errors", COL_COMMENT))
	if not v.valid:
		pass                                    # the errors are on the ERRORS tab
	elif dirty:
		_state = "pending"
		lines.append(_c("ok: ", COL_PENDING) + _c("compiles. apply() to run it", Color(COL_PENDING, 0.85)))
	elif draft.has_rules():
		_state = "applied"
		lines.append(_c("ok: ", COL_OK) + _c("running", Color(COL_OK, 0.85)))
	_console.text = "\n".join(lines)
	_errors_console.text = "\n".join(err_lines)
	_apply_btn.disabled = not dirty or not v.valid
	_revert_btn.disabled = not dirty
	_set_output_alert(0 if v.valid else v.error_count())
	_apply_btn.tooltip_text = "Run this program on the skill." if v.valid \
		else "Fix the errors in OUTPUT first (red lines in the code)."


## OUTPUT with kernel.gd open: the Null's pull requests and your answers, instead of the skill's
## points. Nothing is edited here, so there's nothing to apply(), revert() or clear().
##   > requests  3/4 answered   merge 1  overwrite 1  terminate 1
##   > running   2 root lines, 1 of the Null's
##   > leans     merge  // the answer you gave most (a tie: the deepest)
func _kernel_status() -> void:
	var qm := _kernel_qm()
	var lines: Array = Array(_skills().kernel)
	var t := KernelScript.tally(qm)
	var answered := int(t["merge"]) + int(t["overwrite"]) + int(t["terminate"])
	var out: Array[String] = []
	out.append("%s requests  %s   %s  %s  %s" % [_c(">", COL_GUTTER),
		_c("%d/%d answered" % [answered, KernelScript.NULL_LINES.size()], SkillPanel.COL_TEXT),
		_c("merge %d" % int(t["merge"]), KernelScript.COL_NULL), _c("overwrite %d" % int(t["overwrite"]), COL_KERNEL),
		_c("terminate %d" % int(t["terminate"]), KernelScript.COL_TERMINATE)])
	out.append("%s running   %s %s" % [_c(">", COL_GUTTER),
		_c("%d root line%s, %d of the Null's" % [lines.size(), "" if lines.size() == 1 else "s", KernelScript.null_running(qm).size()], SkillPanel.COL_TEXT),
		_c("// in every %s" % ("dungeon" if Endings.runs_everywhere(qm) else "Act V zone past the Core"), COL_COMMENT)])
	var ending := Endings.current(qm)
	if ending != "":
		out.append("%s ending    %s %s" % [_c(">", COL_GUTTER), _c(str(Endings.TITLES[ending]).to_lower(), Endings.COLOURS[ending]),
			_c("// the Last Log can show the others", COL_COMMENT)])
	else:
		out.append("%s leans     %s %s" % [_c(">", COL_GUTTER), _c(KernelScript.lean(qm) if answered > 0 else "nothing yet", COL_KEYWORD),
			_c("// the answer you gave most (a tie: the deepest). The Last Log reads it back", COL_COMMENT)])
	var editable := Endings.kernel_editable(qm)
	out.append(_c("ok: ", COL_OK) + _c("yours to edit: up to %d root lines, they apply at once" % Endings.MAX_ROOT_LINES if editable
		else "read only. answer the Null on each floor down", Color(COL_OK, 0.85)))
	_console.text = "\n".join(out)
	_errors_console.text = _c("// no errors", COL_COMMENT)
	_apply_btn.disabled = true
	_revert_btn.disabled = true
	_clear_btn.disabled = not editable or lines.is_empty()
	_apply_btn.tooltip_text = "kernel.gd's lines apply as soon as they're added." if editable \
		else "kernel.gd is a record: answer the Null's pull requests on each floor down."
	_set_output_alert(0)


## Marks an editor line that has problems: red background and border, "!" in the gutter, the
## problem in place of the line's comment, and the fix at the top of its tooltip.
## part = the condition / effect / loop on that line, or null for the rule's first line.
func _mark(parts: Array, rule: ProgramRule, part: Object) -> void:
	if _validation == null:
		return
	var texts: Array[String] = []
	var hints: Array[String] = []
	var is_error := false
	for i in _validation.issues.size():
		var issue: Dictionary = _validation.issues[i]
		if issue["rule"] != rule or issue["part"] != part:
			continue
		if not _issue_line.has(i):
			_issue_line[i] = _line_no
		is_error = is_error or issue["kind"] == "error"
		texts.append(issue["text"])
		if issue["hint"] != "" and not (issue["hint"] in hints):
			hints.append(issue["hint"])
	if texts.is_empty():
		return
	var col := SkillPanel.COL_WARN if is_error else COL_PENDING
	var line: PanelContainer = parts[0]
	var sb := line.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = Color(col, 0.14)
		sb.border_color = col
		sb.border_width_left = 3
	var mark := line.get_child(0).get_child(1) as Label
	mark.text = "!"
	mark.add_theme_color_override("font_color", col)
	# Put the problem where the line's "# comment" was (the cost note is still in the tooltip)
	var note := "  # %s: %s" % ["error" if is_error else "note", "; ".join(texts)]
	var code: HBoxContainer = parts[1]
	var replaced := false
	for child in code.get_children():
		if child is Label and (child as Label).get_theme_color("font_color") == COL_COMMENT:
			(child as Label).text = note
			(child as Label).add_theme_color_override("font_color", col)
			replaced = true
			break
	if not replaced:
		var tok := _tok(note, col)
		_shrinkable(tok)
		code.add_child(tok)
	var head := "%s: %s" % ["ERROR" if is_error else "NOTE", "\n".join(texts)]
	for h in hints:
		head += "\nfix: " + h
	line.tooltip_text = head + ("\n\n" + line.tooltip_text if line.tooltip_text != "" else "")


## "line 7: " for errors in the open file, "in cleave.gd: " for another file of this skill.
func _where(issue: Dictionary, index: int) -> String:
	var rule: ProgramRule = issue["rule"]
	if rule == null:
		return ""
	if _issue_line.has(index):
		return "line %d: " % _issue_line[index]          # in the open tab
	return "in %s: " % _owner_file(rule.owner)       # another tab of this skill


func _owner_file(owner_id: String) -> String:
	if owner_id == ROUTINES_FILE:
		return "routines.gd"
	if owner_id == KERNEL_FILE:
		return KernelScript.FILE_NAME
	if owner_id == "":
		return _file_name(_sock().gem.get_display_name()) if _sock() != null else "skill"
	var def: SupportGemDefinition = SkillGemRegistry.get_support_gem(owner_id)
	return _file_name(def.display_name) if def != null else owner_id + ".gd"


## owner id -> true for each file of a socket's skill that has errors ("" = the skill's own file;
## errors about the whole program, like going over budget, also count against it).
func _error_owners(socket: int) -> Dictionary:
	var v: ProgramValidation = null
	if socket == _socket and _validation != null:
		v = _validation
	else:
		var program: SkillProgram = _drafts[socket] if _drafts.has(socket) else _skills().stored_program(socket)
		if program == null or _skills().program_limits_for(socket) == null:
			return {}
		v = _skills().preview_program(socket, program, _routines())
	var out := {}
	for issue in v.issues:
		if issue["kind"] == "error":
			var rule: ProgramRule = issue["rule"]
			out[rule.owner if rule != null else ""] = true
	return out


## Red OUTPUT frame and "OUTPUT  x 2 ERRORS" title while the program has errors.
func _set_output_alert(errors: int) -> void:
	if _output_frame == null:
		return
	var border := Color(SkillPanel.COL_WARN, 0.9) if errors > 0 else Color(panel.accent, 0.3)
	_output_frame.add_theme_stylebox_override("panel", _box_style(Color(0, 0, 0, 0.5), border))
	# A new error opens ERRORS; once it compiles, back to OUTPUT
	if errors > _last_errors:
		_out_tab = "errors"
	elif errors == 0:
		_out_tab = "output"
	_last_errors = errors
	_update_out_tabs(errors)


func _apply() -> void:
	if _routines_dirty():                        # routines first: this script's calls run them
		_skills().set_routines(_routines())
		_routine_draft.clear()
		if not _is_dirty(_socket):
			panel._notify("ROUTINES SAVED")
			_queue_rebuild()
			return
	var draft := _draft()
	if not draft.has_rules():
		_skills().set_program(_socket, null)
		_drafts.erase(_socket)
		panel._notify("PROGRAM REMOVED")
		return
	var result := _skills().set_program(_socket, draft.duplicate_program())
	if result.valid:
		_drafts.erase(_socket)                  # the next draft starts from what was applied
		panel._notify("PROGRAM APPLIED")
		if ScriptTips.enabled() and not ScriptTips.seen("applied"):
			_show_tip(ScriptTips.tip("applied"))
			_tip_hold = true
	else:
		panel._notify(result.errors[0].to_upper() if not result.errors.is_empty() else "INVALID PROGRAM")
	_queue_rebuild()


func _revert() -> void:
	_drafts.erase(_socket)
	_routine_draft.clear()                       # routines.gd goes back to what was saved too
	_routine_rename = -1
	_selected = null
	_queue_rebuild()


func _clear_gem() -> void:
	if _owner == KERNEL_FILE:                    # a record: nothing to clear, until OVERWRITE makes it yours
		if Endings.kernel_editable(_kernel_qm()):
			_skills().kernel.clear()
			Coop.kernel_changed()
			panel._notify("KERNEL: LINES REMOVED")
			_queue_rebuild()
		return
	if _owner == ROUTINES_FILE:                  # clear() in routines.gd empties every routine
		for rt in _routines():
			(rt as ProgramRoutine).body.effects.clear()
			(rt as ProgramRoutine).body.branches.clear()
		_selected = null
		_changed()
		return
	var draft := _draft()
	for r in draft.rules_of(_owner):
		draft.rules.erase(r)
	_selected = null
	_changed()


# ---------- FORMATTING ----------
## "Many Projectiles Support" -> "many_projectiles.gd"
static func _file_name(display_name: String) -> String:
	var n := display_name.trim_suffix(" Support").trim_suffix(" Gem").strip_edges().to_lower()
	return n.replace(" ", "_") + ".gd"


## "MY LIFE BELOW" -> "my_life_below"
static func _fn_name(c: ProgramCondition) -> String:
	return c.palette_name().to_lower().replace(" ", "_")


static func _fmt_param(c: ProgramCondition, p: String) -> String:
	if c.param_text(p) != "":
		return c.param_text(p)
	var v = c.get(p)
	if p == "fraction":
		return "%d%%" % roundi(float(v) * 100.0)
	if p == "radius":
		return "%.1fm" % float(v)
	return str(v)


## The size of a change without its sign (the sign is shown by += / -=).
static func _fmt_knob(knob: SkillKnob, steps: int, mult: float = 1.0) -> String:
	var v := absf(knob.value_for(steps) * mult)
	match knob.unit:
		"%":
			return "%d%%" % roundi(v * 100.0)
		"m":
			return "%.2fm" % v
		"deg":
			return "%d°" % roundi(v)
	if is_equal_approx(v, roundf(v)):
		return str(roundi(v))
	return "%.1f" % v


## What one count of the registry adds: the maximum shared out over the counts that reach it.
static func _fmt_per_count(knob: SkillKnob, steps: int, mult: float = 1.0) -> String:
	var v := absf(knob.value_for(steps) * mult) / ScriptRegisters.RAMP_PER_STEP
	match knob.unit:
		"%":
			var percent := v * 100.0
			return "%d%%" % roundi(percent) if is_equal_approx(percent, roundf(percent)) else "%.1f%%" % percent
		"m":
			return "%.2fm" % v
		"deg":
			return "%.1f°" % v
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## Colour a piece of console text.
static func _c(text: String, col: Color) -> String:
	return "[color=#%s]%s[/color]" % [col.to_html(false), text]


static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


# ---------- SMALL HELPERS ----------
func _box_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.content_margin_left = 4
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


## Lets a label get narrower than its text (cut with "...") instead of widening the panel.
func _shrinkable(l: Label) -> void:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 1.0


## How much bigger than the original 13 px design the tab is (SkillPanel.script_font_size).
func _k() -> float:
	return float(panel.script_font_size) / CODE_SIZE


## A font size from the original design, scaled to SkillPanel.script_font_size.
func _sz(base: int) -> int:
	return roundi(base * _k())


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

## Where the bonus script points come from, e.g. "rank +2, exam grades +1, 3 areas cleared +3".
func _bonus_sources() -> String:
	var owner_node := _skills().get_parent()
	var b := ScriptBudget.breakdown(owner_node.get("quests") as QuestManager)
	var parts: Array[String] = []
	if b["rank"] > 0.0:
		parts.append("rank +%s" % String.num(b["rank"], 1))
	if b["grades"] > 0.0:
		parts.append("exam grades +%s" % String.num(b["grades"], 1))
	if b["areas"] > 0:
		parts.append("%d area%s cleared +%s" % [b["areas"], "" if b["areas"] == 1 else "s", String.num(b["clears"], 1)])
	return ", ".join(parts)

## Where the extra knob steps come from, e.g. "2 DISTINCTIONs +2, 1 act boss +1".
func _step_sources() -> String:
	var b := ScriptBudget.breakdown(_skills().get_parent().get("quests") as QuestManager)
	var parts: Array[String] = []
	if b["distinctions"] > 0:
		parts.append("%d DISTINCTION%s +%d" % [b["distinctions"], "" if b["distinctions"] == 1 else "s",
				b["distinctions"] * ScriptBudget.STEPS_PER_DISTINCTION])
	if b["bosses"] > 0:
		parts.append("%d act boss%s +%d" % [b["bosses"], "" if b["bosses"] == 1 else "es",
				b["bosses"] * ScriptBudget.STEPS_PER_ACT_BOSS])
	return ", ".join(parts)
