class_name SkillScriptTab
extends VBoxContainer
## The SCRIPTING tab of the skills menu (SkillPanel), styled like a small code editor.
## Players build a SkillProgram by dragging snippets into the code; nothing is typed.
##
##  - EXPLORER (left): one "file" per socketed skill and per scriptable support. A skill and its
##                     supports share one point budget, so they are checked together.
##  - EDITOR (middle): the selected file's rules as code, with line numbers:
##                         always:
##                     +       damage += 20%          # costs 8.0
##                     -       attack_speed -= 20%    # pays 10.0
##                         when enemies_nearby(3, 4.0m):   # buffs x0.60
##                     +       range_bonus += 1.00m   # costs 8.0
##                     Loops repeat the skill:
##                         when every_nth_cast(3):
##                     +       for i in range(2):         # 2 repeats, costs 3.6
##                                 cast()
##                     The +/- in the gutter marks buffs (cost points) and drawbacks (pay points).
##                     Numbers are buttons: click = up, right-click = down, mouse wheel = both.
##                     Drag a line onto another rule to move it, or onto SNIPPETS to delete it.
##                     Right-click a line to delete it. Click a line to select its rule.
##  - SNIPPETS (right): conditions and the selected file's knobs. Drag one into the editor, or
##                     click it to add it to the selected rule (or start a new rule).
##  - OUTPUT (bottom): points, blocks, tier and compile errors. apply() runs the program.
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
const CODE_SIZE := 13

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
var _output_title: Label
## Check result for the open socket's draft, made at the start of each rebuild so the editor
## can mark the lines with errors while it draws them.
var _validation: ProgramValidation
var _issue_line: Dictionary = {}  # index in _validation.issues -> editor line number
# For the tutorial hints: the controls they can outline
var _rule_line: Dictionary = {}    # ProgramRule -> its first editor line
var _snippets: Dictionary = {}     # "cond:<type id>" / "knob:<knob id>" -> snippet in SNIPPETS
var _skill_file_btn: Dictionary = {}  # socket -> the skill's file button in the explorer
var _effect_num: Dictionary = {}   # ProgramEffect -> its editable number
var _cond_nums: Dictionary = {}    # ProgramCondition -> [its editable numbers]
var _apply_btn: Button
var _revert_btn: Button
var _clear_btn: Button


# ---------- BUILDING ----------
func build() -> void:
	add_theme_constant_override("separation", 6)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	add_child(body)

	# Left: explorer
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 150.0 * _k()
	body.add_child(left)
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
	mid.add_theme_constant_override("separation", 6)
	body.add_child(mid)
	_title = panel._label("", _sz(14), panel.accent)
	_shrinkable(_title)
	mid.add_child(_title)
	var editor := PanelContainer.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.add_theme_stylebox_override("panel", _box_style(Color(0.0, 0.02, 0.04, 0.6), Color(panel.accent, 0.3)))
	mid.add_child(editor)
	var mid_scroll := _scroll()
	editor.add_child(mid_scroll)
	_rules_box = VBoxContainer.new()
	_rules_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_box.add_theme_constant_override("separation", 0)
	mid_scroll.add_child(_rules_box)
	mid.add_child(_build_output())

	# Right: snippets. Dropping a code line here deletes it.
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 170.0 * _k()
	body.add_child(right)
	right.add_child(panel._label("SNIPPETS", _sz(13), SkillPanel.COL_DIM))
	var right_scroll := _scroll()
	right.add_child(right_scroll)
	_palette_box = VBoxContainer.new()
	_palette_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette_box.add_theme_constant_override("separation", 2)
	right_scroll.add_child(_palette_box)
	right_scroll.set_drag_forwarding(Callable(), _can_drop_on_palette, _drop_on_palette)
	_palette_box.set_drag_forwarding(Callable(), _can_drop_on_palette, _drop_on_palette)

	var hint := panel._label("// DRAG SNIPPETS INTO THE CODE  |  DRAG A LINE OUT OR RIGHT-CLICK IT: DELETE  |  NUMBERS: CLICK UP, RIGHT-CLICK DOWN",
		_sz(11), COL_COMMENT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 1.0
	add_child(hint)


func _build_output() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box_style(Color(0, 0, 0, 0.5), Color(panel.accent, 0.3)))
	_output_frame = frame
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	frame.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	var title := panel._label("OUTPUT", _sz(12), SkillPanel.COL_DIM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_output_title = title
	_apply_btn = _code_button("apply()", "Run this program on the skill.")
	_apply_btn.pressed.connect(_apply)
	head.add_child(_apply_btn)
	_revert_btn = _code_button("revert()", "Throw away changes since the last apply().")
	_revert_btn.pressed.connect(_revert)
	head.add_child(_revert_btn)
	_clear_btn = _code_button("clear()", "Delete every rule in this file.")
	_clear_btn.pressed.connect(_clear_gem)
	head.add_child(_clear_btn)

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
	box.add_child(_console)
	return frame


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


## The program being edited for the current socket. Starts as a copy of the applied one.
func _draft() -> SkillProgram:
	if not _drafts.has(_socket):
		var applied := _skills().get_program(_socket)
		_drafts[_socket] = applied.duplicate_program() if applied != null else SkillProgram.new()
	return _drafts[_socket]


func _support_ids(s: SkillComponent.Socket) -> Array:
	var ids: Array = []
	for item in s.supports:
		ids.append(item.definition.support_gem.id)
	return ids


## True when the socket's draft differs from what is applied (an unsaved file).
func _is_dirty(socket: int) -> bool:
	if not _drafts.has(socket):
		return false
	var applied := _skills().get_program(socket)
	var applied_json := JSON.stringify(applied.to_dict() if applied != null else {"rules": []})
	return JSON.stringify((_drafts[socket] as SkillProgram).to_dict()) != applied_json


## Called by SkillPanel when the tab is shown or the skills change.
## Controls the tutorial hints can outline (see SkillPanel.tutorial_target).
## ids: script_palette / palette, script_apply / apply, output, skill_file,
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
		"skill_file":
			if _skill_file_btn.has(_socket):
				out.append(_skill_file_btn[_socket])
		_:
			if _snippets.has(id) and is_instance_valid(_snippets[id]):
				out.append(_snippets[id])
			elif id.begins_with("knob_number:"):        # knob_number:<condition id>:<knob id>
				var bits := id.split(":")
				var rule: ProgramRule = _tutorial_rule(bits[1]) if bits.size() == 3 else null
				if rule != null:
					for e in rule.effects:
						if String(e.knob) == bits[2] and _effect_num.has(e) and is_instance_valid(_effect_num[e]):
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
func tutorial_state(condition_id: String, knob_id: StringName = &"damage") -> Dictionary:
	var rule := _tutorial_rule(condition_id)
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
	}


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
	if _sock() != null and _owner != "" and not (_owner in _support_ids(_sock())):
		_owner = ""
	_rebuild()


func _select_gem(socket: int, owner_id: String) -> void:
	_socket = socket
	_owner = owner_id
	_selected = null
	_rebuild()


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
		_validation = _skills().preview_program(_socket, _draft())
	_build_gem_list()
	_build_rules()
	_build_palette()
	_update_status()


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
	if _owner == "":
		_title.text = skill_file
	else:
		var sup: SupportGemDefinition = SkillGemRegistry.get_support_gem(_owner)
		_title.text = "%s / %s" % [skill_file.trim_suffix(".gd"), _file_name(sup.display_name) if sup else _owner]

	_comment_line("# points are shared with every file of this skill")
	var rules := _draft().rules_of(_owner)
	if _selected != null and not (_selected in rules):
		_selected = null
	for rule in rules:
		_blank_line(rule)
		_rule_lines(rule, limits)
	_blank_line(null)
	_new_rule_line()


func _rule_lines(rule: ProgramRule, limits: SkillProgramLimits) -> void:
	var discount := ""
	if not rule.is_always() and rule.cost_multiplier() < 1.0:
		discount = "buffs x%.2f" % rule.cost_multiplier()
		if rule.is_discount_capped():
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
			code.add_child(_tok(_fn_name(c), COL_GEM if c.required_support() != "" else COL_FN))
			if c.keyword() == "":
				code.add_child(_tok("(", COL_OP))
			var params := c.param_names()
			for j in params.size():
				var p := params[j]
				if j > 0:
					code.add_child(_tok(", ", COL_OP))
				var param_num := _num_tok(_fmt_param(c, p), c.param_label(p).to_lower(), func(d: int) -> void:
					c.nudge_param(p, d)
					_changed())
				code.add_child(param_num)
				if not _cond_nums.has(c):
					_cond_nums[c] = []
				_cond_nums[c].append(param_num)
			if c.keyword() == "":
				code.add_child(_tok("):" if last else ")", COL_OP))
			elif last:
				code.add_child(_tok(":", COL_OP))
			code.add_child(_comment_tok(discount if i == 0 else ""))
			if i == 0:
				code.add_child(_delete_rule_button(rule))
			parts[0].tooltip_text = "%s\nBuffs in this rule cost x%.2f.\nDrag out or right-click to delete." % [c.describe(), c.cost_multiplier()]
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
	if rule.effects.is_empty() and not looping:
		var parts := _code_line(rule)
		var code: HBoxContainer = parts[1]
		code.add_child(_tok("    pass", COL_KEYWORD))
		code.add_child(_comment_tok("drop a knob here"))
		_make_line_interactive(parts[0], rule, {})
	for e in rule.effects:
		_effect_line(rule, e, limits, indent)
	if looping:
		if is_while:
			_loop_line(rule, limits)
		else:
			_cast_line(rule, indent)
		if rule.loop.break_on != ProgramLoop.Break.NONE:
			_break_line(rule, indent)


func _effect_line(rule: ProgramRule, e: ProgramEffect, limits: SkillProgramLimits, indent := "    ") -> void:
	var knob := limits.get_knob(e.knob)
	var cost := knob.cost_for(e.steps) if knob else 0.0
	if cost > 0.0:
		cost *= limits.buff_cost_mult()                  # class trait discount (Enchanter)
	var marker := "+" if cost > 0.0 else ("-" if cost < 0.0 else "")
	var parts := _code_line(rule, marker, COL_BUFF if cost > 0.0 else COL_DRAW)
	var code: HBoxContainer = parts[1]
	code.add_child(_tok(indent, COL_OP))
	code.add_child(_tok(String(e.knob), COL_VAR))
	code.add_child(_tok(" -= " if e.steps < 0 else " += ", COL_OP))
	var value := _fmt_knob(knob, e.steps, limits.rule_effect_mult(rule)) if knob else str(absi(e.steps))
	var num := _num_tok(value, knob.display_name.to_lower() if knob else String(e.knob), func(d: int) -> void:
		e.steps += d
		_changed())
	code.add_child(num)
	_effect_num[e] = num
	var note := ""
	if cost > 0.0:
		note = "costs %.1f" % cost
	elif cost < 0.0:
		note = "pays %.1f" % -cost
	if rule.loop != null or rule.only_on_repeats():
		note = ("%s, repeats only" % note) if note != "" else "repeats only"
	code.add_child(_comment_tok(note))
	if knob:
		parts[0].tooltip_text = "%s: %s\n%+.1f points per step. Limits: %d to %+d steps.%s%s\nDrag out or right-click to delete." % [
			knob.display_name, knob.describe(e.steps), knob.cost_per_step, knob.min_steps, knob.max_steps,
			_stat_note(knob, limits) if knob.kind == SkillKnob.Kind.STAT else "",
			"\nIn a loop rule this only changes the repeats." if rule.loop != null else
			("\nThis rule's condition is about loop repeats, so this only changes the repeats." if rule.only_on_repeats() else "")]
	_make_line_interactive(parts[0], rule, {"kind": "effect", "effect": e})
	_mark(parts, rule, e)


func _stat_note(knob: SkillKnob, limits: SkillProgramLimits) -> String:
	if limits.per_hit_attack_speed(knob):
		return "\nWorks in an always: rule, or (Assassin) a per-hit rule: a qualifying hit makes your next attack faster."
	return "\nOnly works in an always: rule."


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
	parts[0].tooltip_text = _loop_tip(lp.mode, limits) + "\nDrag out or right-click to delete the loop."
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


## if killed: break   (the word is a button: click switches killed / missed)
func _break_line(rule: ProgramRule, indent: String) -> void:
	var lp := rule.loop
	var parts := _code_line(rule, "-", COL_DRAW)
	var code: HBoxContainer = parts[1]
	code.add_child(_tok(indent + "if ", COL_KEYWORD))
	code.add_child(_num_tok(lp.break_word(), "killed: stop once a repeat kills\nmissed: stop once one hits nothing",
		func(_d: int) -> void:
			lp.break_on = ProgramLoop.Break.MISS if lp.break_on == ProgramLoop.Break.KILL else ProgramLoop.Break.KILL
			_changed()))
	code.add_child(_tok(": ", COL_OP))
	code.add_child(_tok("break", COL_KEYWORD))
	code.add_child(_comment_tok("loop costs x%.2f" % ProgramLoop.BREAK_COST_MULT))
	parts[0].tooltip_text = "Stops this loop early: %s.\nThe loop costs x%.2f points.\nDrag out or right-click to delete." % [
		"once a cast or repeat kills something" if lp.break_on == ProgramLoop.Break.KILL else "once a cast or repeat hits nothing",
		ProgramLoop.BREAK_COST_MULT]
	_make_line_interactive(parts[0], rule, {"kind": "break"})


func _loop_tip(mode: ProgramLoop.Mode, limits: SkillProgramLimits) -> String:
	var head := "FOR: the skill repeats exactly N times after it lands (if the rule's conditions are true).\n%.1f points per repeat." % (ProgramLoop.FOR_COST * limits.loop_cost_mult()) \
		if mode == ProgramLoop.Mode.FOR else \
		"WHILE: the skill repeats as long as the rule's conditions stay true, up to max.\nNeeds a condition that can change mid-cast. %.1f points per max repeat." % (ProgramLoop.WHILE_COST * limits.loop_cost_mult())
	return "%s\nEach repeat deals x%.2f the damage of the one before and costs %d%% of the skill's mana.\nAt most %d repeats per cast; other effects in the rule only change the repeats.\nRepeats don't trigger echoes, holograms or on-kill effects." % [
		head, ProgramLoop.FALLOFF, roundi(ProgramLoop.MANA_FRACTION * limits.repeat_mana_mult() * 100.0), limits.loop_cap()]


func _new_rule_line() -> void:
	var parts := _code_line(null, "+", Color(panel.accent, 0.6))
	var line: Control = parts[0]
	var code: HBoxContainer = parts[1]
	code.add_child(_comment_tok("drop a snippet here to start a new rule"))
	line.set_drag_forwarding(Callable(), _can_drop_new_rule, _drop_new_rule)
	line.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_selected = null                 # the next snippet click starts a new rule
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
## (a condition or an effect) can be dragged away or right-clicked to delete them.
func _make_line_interactive(line: Control, rule: ProgramRule, info: Dictionary) -> void:
	var drag_func := Callable()
	if not info.is_empty():
		info["src"] = "rule"
		info["rule"] = rule
		drag_func = func(_pos: Vector2) -> Variant:
			line.set_drag_preview(_drag_preview(line))
			return info
	line.set_drag_forwarding(drag_func, _can_drop_on_rule.bind(rule), _drop_on_rule.bind(rule))
	line.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton):
			return
		if ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed and not get_viewport().gui_is_dragging():
			if _selected != rule:
				_selected = rule
				_queue_rebuild()
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed and not info.is_empty():
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
func _comment_tok(text: String) -> Label:
	var l := _tok(("  # " + text) if text != "" else "", COL_COMMENT)
	_shrinkable(l)
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
func _build_palette() -> void:
	_clear(_palette_box)
	_snippets.clear()
	var limits := _limits()
	if limits == null:
		return
	# Core blocks first; blocks a support gem adds get a section of their own (below)
	var by_gem := {}                                   # support id -> [condition type ids]
	_palette_box.add_child(_comment_tok("conditions"))
	for type_id in ProgramConditions.TYPES.keys():
		var sample := ProgramConditions.create(type_id)
		var gem_id := sample.required_support()
		if gem_id != "":
			if limits.support_ids.has(gem_id):
				if not by_gem.has(gem_id):
					by_gem[gem_id] = []
				by_gem[gem_id].append(type_id)
			continue                                   # not socketed: not offered
		var cond_snippet := _condition_snippet(type_id, sample, COL_FN, "")
		_snippets["cond:" + type_id] = cond_snippet
		_palette_box.add_child(cond_snippet)
	_palette_box.add_child(_comment_tok("loops"))
	_palette_box.add_child(_snippet("for range()", COL_KEYWORD, {"src": "palette", "kind": "loop", "mode": ProgramLoop.Mode.FOR},
		_loop_tip(ProgramLoop.Mode.FOR, limits) + "\nDrag into a rule, or click to add."))
	_palette_box.add_child(_snippet("while", COL_KEYWORD, {"src": "palette", "kind": "loop", "mode": ProgramLoop.Mode.WHILE},
		_loop_tip(ProgramLoop.Mode.WHILE, limits) + "\nDrag into a rule with a condition, or click to add."))
	_palette_box.add_child(_snippet("break", COL_KEYWORD, {"src": "palette", "kind": "break"},
		"Stops a loop early, once a repeat kills (click the word to switch to: once one hits nothing).\nThe loop costs x%.2f points.\nDrag into a rule that has a loop." % ProgramLoop.BREAK_COST_MULT))
	# One section per socketed support gem that adds blocks, in socket order
	for gem_id in limits.support_ids:
		if not by_gem.has(gem_id):
			continue
		var def: SupportGemDefinition = SkillGemRegistry.get_support_gem(gem_id)
		var gem_name := def.display_name.trim_suffix(" Support") if def != null else gem_id
		_palette_box.add_child(_gem_header(gem_name))
		for type_id in by_gem[gem_id]:
			_palette_box.add_child(_condition_snippet(type_id, ProgramConditions.create(type_id),
				COL_GEM, gem_name))
	_palette_box.add_child(_comment_tok("knobs"))
	var knobs := limits.knobs_for(_owner)
	if knobs.is_empty():
		_palette_box.add_child(_comment_tok("nothing to change"))
	for knob in knobs:
		var tip := "%s\n+1 step: %s for %+.1f points.\nLimits: %d to %+d steps." % [
			knob.display_name, knob.describe(1), knob.cost_for(1), knob.min_steps, knob.max_steps]
		if knob.kind == SkillKnob.Kind.STAT:
			tip += _stat_note(knob, limits)
		var knob_snippet := _snippet(String(knob.id), COL_VAR,
			{"src": "palette", "kind": "effect", "knob": knob.id}, tip)
		_snippets["knob:" + String(knob.id)] = knob_snippet
		_palette_box.add_child(knob_snippet)


func _condition_snippet(type_id: String, sample: ProgramCondition, col: Color, gem_name: String) -> Control:
	var label := (sample.keyword() + " " + _fn_name(sample)) if sample.keyword() != "" else _fn_name(sample) + "()"
	var tip := "%s\nRarer conditions make buffs cheaper.\nDrag into a rule, or click to add." % sample.describe()
	if gem_name != "":
		tip = "From the %s gem.\n%s" % [gem_name, tip]
	return _snippet(label, col, {"src": "palette", "kind": "condition", "type": type_id}, tip)


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


func _snippet(text: String, col: Color, data: Dictionary, tip: String) -> Control:
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
	block.add_child(l)
	block.tooltip_text = tip
	block.set_drag_forwarding(
		func(_pos: Vector2) -> Variant:
			block.set_drag_preview(_drag_preview(block))
			return data,
		_can_drop_on_palette, _drop_on_palette)
	# A click (press + release without dragging) adds the snippet to the selected rule
	block.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT \
				and not get_viewport().gui_is_dragging():
			_add_from_palette(data, _selected))
	return block


## The snippet texts, in order (for tests and debugging).
func palette_items() -> Array[String]:
	var out: Array[String] = []
	for c in _palette_box.get_children():
		if c is PanelContainer:
			out.append((c.get_child(0) as Label).text)
	return out


# ---------- DRAG AND DROP ----------
func _can_drop_on_rule(_pos: Vector2, data: Variant, _rule: ProgramRule) -> bool:
	return data is Dictionary and data.get("src") in ["palette", "rule"]


func _drop_on_rule(_pos: Vector2, data: Variant, rule: ProgramRule) -> void:
	if data.get("src") == "palette":
		_add_from_palette(data, rule)
	elif data.get("rule") != rule:
		_move_block(data, rule)


func _can_drop_new_rule(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("src") in ["palette", "rule"]


func _drop_new_rule(_pos: Vector2, data: Variant) -> void:
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
func _add_from_palette(data: Dictionary, rule: ProgramRule) -> void:
	if _sock() == null or _limits() == null:
		return
	if data["kind"] == "break" and (rule == null or rule.loop == null):
		panel._notify("ADD A FOR OR WHILE LOOP FIRST")
		return
	if rule == null:
		rule = _new_rule()
	if data["kind"] == "condition":
		var c := ProgramConditions.create(data["type"])
		if c != null:
			rule.conditions.append(c)
	elif data["kind"] == "loop":
		if rule.loop == null:
			rule.loop = ProgramLoop.make(data["mode"])
		elif rule.loop.mode == data["mode"]:
			rule.loop.count = mini(rule.loop.count + 1, _limits().loop_cap())
		else:
			rule.loop.mode = data["mode"]
	elif data["kind"] == "break":
		rule.loop.break_on = ProgramLoop.Break.MISS if rule.loop.break_on == ProgramLoop.Break.KILL \
			else ProgramLoop.Break.KILL
	else:
		var existing: ProgramEffect = null
		for e in rule.effects:
			if e.knob == data["knob"]:
				existing = e
		if existing != null:
			existing.steps += 1
		else:
			rule.effects.append(ProgramEffect.make(data["knob"], 1))
	_selected = rule
	_changed()


func _detach(info: Dictionary) -> void:
	var from: ProgramRule = info["rule"]
	match info["kind"]:
		"condition":
			from.conditions.erase(info["condition"])
		"effect":
			from.effects.erase(info["effect"])
		"loop":
			from.loop = null
		"break":
			if from.loop != null:
				from.loop.break_on = ProgramLoop.Break.NONE
	if from.conditions.is_empty() and from.effects.is_empty() and from.loop == null:
		_draft().rules.erase(from)


func _move_block(info: Dictionary, to: ProgramRule) -> void:
	var src: ProgramRule = info["rule"]
	var moved_loop: ProgramLoop = src.loop
	var moved_break := moved_loop.break_on if moved_loop != null else ProgramLoop.Break.NONE
	if info["kind"] == "break" and (to == null or to.loop == null):
		panel._notify("ADD A FOR OR WHILE LOOP FIRST")
		return
	_detach(info)
	if to == null:
		to = _new_rule()
	match info["kind"]:
		"condition":
			to.conditions.append(info["condition"])
		"effect":
			to.effects.append(info["effect"])
		"loop":
			to.loop = moved_loop
		"break":
			to.loop.break_on = moved_break
	_selected = to
	_changed()


func _remove_block(info: Dictionary) -> void:
	_detach(info)
	_changed()


func _changed() -> void:
	_queue_rebuild()


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
		_set_output_alert(0)
		return

	var draft := _draft()
	var v := _validation if _validation != null else _skills().preview_program(_socket, draft)
	var lines: Array[String] = []

	# points  [########........]  6.0 / 12.0
	var paid := v.drawback_points + v.point_budget
	var over := v.buff_points > paid + 0.001
	var cap := maxf(maxf(paid, v.buff_points), 1.0)
	var filled := clampi(roundi(16.0 * v.buff_points / cap), 0, 16)
	var bar := "#".repeat(filled) + ".".repeat(16 - filled)
	lines.append("%s points  [lb]%s[rb]  %s" % [_c(">", COL_GUTTER), _c(bar, SkillPanel.COL_WARN if over else COL_OK),
		_c("%.1f / %.1f" % [v.buff_points, paid], SkillPanel.COL_WARN if over else SkillPanel.COL_TEXT)])
	lines.append("%s blocks  %d/%d   rules %d/%d" % [_c(">", COL_GUTTER), v.actions_used, v.max_actions,
		draft.rules.size(), limits.max_rules])
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

	var dirty := _is_dirty(_socket)
	if not v.valid:
		_state = "invalid"
		var count := v.error_count()
		lines.append(_c("x %d error%s: fix %s to apply()" % [count, "" if count == 1 else "s",
			"it" if count == 1 else "them"], SkillPanel.COL_WARN))
		var shown := 0
		for i in v.issues.size():
			var issue: Dictionary = v.issues[i]
			if issue["kind"] != "error" or issue["dup"]:
				continue
			if shown == 5:
				lines.append(_c("  ... %d more: hover the red lines for details" % (count - shown), SkillPanel.COL_WARN))
				break
			shown += 1
			lines.append(_c("  error ", SkillPanel.COL_WARN) + _c(_where(issue, i), COL_FN)
				+ _c(_esc(issue["text"]), SkillPanel.COL_TEXT))
			if issue["hint"] != "":
				lines.append(_c("        fix: ", COL_GUTTER) + _c(_esc(issue["hint"]), COL_OK))
	elif dirty:
		_state = "pending"
		lines.append(_c("ok: ", COL_PENDING) + _c("compiles. apply() to run it", Color(COL_PENDING, 0.85)))
	elif draft.has_rules():
		_state = "applied"
		lines.append(_c("ok: ", COL_OK) + _c("running", Color(COL_OK, 0.85)))
	_console.text = "\n".join(lines)
	_apply_btn.disabled = not dirty or not v.valid
	_revert_btn.disabled = not dirty
	_set_output_alert(0 if v.valid else v.error_count())
	_apply_btn.tooltip_text = "Run this program on the skill." if v.valid \
		else "Fix the errors in OUTPUT first (red lines in the code)."


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
	if rule.owner != _owner:
		return "in %s: " % _owner_file(rule.owner)
	if _issue_line.has(index):
		return "line %d: " % _issue_line[index]
	return ""


func _owner_file(owner_id: String) -> String:
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
		var program: SkillProgram = _drafts[socket] if _drafts.has(socket) else _skills().get_program(socket)
		if program == null or _skills().program_limits_for(socket) == null:
			return {}
		v = _skills().preview_program(socket, program)
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
	_output_title.text = "OUTPUT  x %d ERROR%s" % [errors, "" if errors == 1 else "S"] if errors > 0 else "OUTPUT"
	_output_title.add_theme_color_override("font_color", SkillPanel.COL_WARN if errors > 0 else SkillPanel.COL_DIM)


func _apply() -> void:
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
	else:
		panel._notify(result.errors[0].to_upper() if not result.errors.is_empty() else "INVALID PROGRAM")
	_queue_rebuild()


func _revert() -> void:
	_drafts.erase(_socket)
	_selected = null
	_queue_rebuild()


func _clear_gem() -> void:
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
