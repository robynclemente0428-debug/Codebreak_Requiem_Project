class_name ScriptGuide
extends PanelContainer
## The SCRIPTING GUIDE: a reference window over the SCRIPTING tab, opened with guide() (top of
## the editor) and once by itself when Warden Brack's scripting lesson starts (TutorialHints).
## Pages on the left, the open page on the right. Close with close(), [ESC] or guide() again.
##
## Seven short pages in plain words: the basics, always vs when, points, cheaper rules, blocks,
## fixing and applying, unlocks. Each starts with a one-line summary. The numbers on them
## (budget, block and rule limits, tiers) are read from the open skill when the guide opens
## (SkillScriptTab.open_guide), so they match what the player has; without a skill it explains
## the same ideas without the numbers.

const PAGES := [
	["start", "1. The basics"],
	["when", "2. always vs when"],
	["points", "3. Points"],
	["cheaper", "4. Cheaper rules"],
	["blocks", "5. Blocks"],
	["apply", "6. Fixing and applying"],
	["later", "7. Unlocks"],
]


var tab: SkillScriptTab
var _page := "start"
var _limits: SkillProgramLimits
var _bonus := ""                           # where the bonus points come from ("" = none)
var _page_btns := {}                       # page id -> its button
var _text: RichTextLabel
var _scroll: ScrollContainer


func build() -> void:
	top_level = true                       # laid over the tab, not inside its layout
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.04, 0.06, 0.97)
	sb.border_color = Color(tab.panel.accent, 0.8)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(roundi(10.0 * tab._k()))
	add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := tab.panel._label("// SCRIPTING GUIDE //", tab._sz(16), tab.panel.accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := tab._code_button("close()", "Close the guide [ESC]. guide() opens it again.")
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", roundi(10.0 * tab._k()))
	col.add_child(body)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.custom_minimum_size.x = 170.0 * tab._k()
	body.add_child(list)
	for p in PAGES:
		var b := tab._code_button(p[1], "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(show_page.bind(p[0]))
		list.add_child(b)
		_page_btns[p[0]] = b

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size.x = 1.0
	_text.add_theme_color_override("default_color", SkillPanel.COL_TEXT)
	if tab.panel._font:
		for f in ["normal_font", "bold_font", "italics_font", "mono_font"]:
			_text.add_theme_font_override(f, tab.panel._font)
	for f in ["normal_font_size", "bold_font_size", "italics_font_size", "mono_font_size"]:
		_text.add_theme_font_size_override(f, tab._sz(13))
	_scroll.add_child(_text)


## Opens the guide over the tab. `limits`: the open skill's (null = no skill socketed).
## `bonus`: where its bonus points come from, e.g. "3 areas cleared +3".
func open(limits: SkillProgramLimits, bonus: String, page := "") -> void:
	_limits = limits
	_bonus = bonus
	visible = true
	_fit()
	show_page(page if page != "" else _page)


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func show_page(id: String) -> void:
	_page = id
	for p in _page_btns:
		var b: Button = _page_btns[p]
		b.add_theme_color_override("font_color", Color.WHITE if p == id else SkillScriptTab.COL_FN)
	_text.text = _page_text(id)
	_scroll.scroll_vertical = 0


func _process(_delta: float) -> void:
	if visible:
		if not tab.is_visible_in_tree():
			close()                            # the menu closed or another tab opened
		else:
			_fit()


## Covers the whole SCRIPTING tab.
func _fit() -> void:
	var r := tab.get_global_rect()
	global_position = r.position
	size = r.size


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ---------- THE PAGES ----------
## Each page: a title, an "in short" line, then a few short points and one example.
## Written for players: plain words, one idea per page, numbers from the open skill.
func _page_text(id: String) -> String:
	match id:
		"start":
			return _h("The basics") \
				+ _short("A script makes your skill react to the fight.") \
				+ _tip("In a hurry? Press [ESC] and start building: tips show in OUTPUT as you go.") + "\n\n" \
				+ "A script is made of [b]rules[/b]. A rule has two parts:\n" \
				+ _point("a [b]header[/b]: WHEN it's on") \
				+ _point("[b]lines[/b] under it: WHAT it changes") \
				+ "\n" + _code([
					_kw("when ") + _fn("enemies_nearby") + _op("(") + _num("3") + _op(", ") + _num("4.0m") + _op("):") + _cm("   # when 3+ enemies are close"),
					"    " + _var("damage") + _op(" += ") + _num("10%") + _cm("        # hit 10% harder"),
				]) \
				+ _h2("How to build one") \
				+ _point("[b]Click a snippet[/b] on the right to add it.") \
				+ _point("[b]Click an orange number[/b] to raise it. Right-click lowers it.") \
				+ _point("[b]Right-click a line[/b] to delete it.") \
				+ _point("Press [b]apply()[/b] when you're done. Until then it's only a draft.") \
				+ "\n" + _tip("Change one thing, apply(), try it. That's the fastest way to learn.")
		"when":
			return _h("always vs when") \
				+ _short("always: is on all the time. when: is on only sometimes, so it's cheaper.") \
				+ _h2("always:") \
				+ _point("Always on.") \
				+ _point("Full price.") \
				+ _point("The only place for some lines, like attack speed.") \
				+ "\n" + _h2("when ...:") \
				+ _point("On only while its condition is true.") \
				+ _point("Cheaper: the rarer it is, the less it costs.") \
				+ "\n" + _code([
					_kw("always:"),
					"    " + _var("attack_speed") + _op(" -= ") + _num("10%") + _cm("   # a bit slower..."),
					_kw("when ") + _fn("enemies_nearby") + _op("(") + _num("3") + _op(", ") + _num("4.0m") + _op("):"),
					"    " + _var("damage") + _op(" += ") + _num("20%") + _cm("        # ...for a big hit when crowded"),
				]) \
				+ _tip("Hover a condition in SNIPPETS to see when it's true.")
		"points":
			var t := _h("Points") \
				+ _short("Buffs cost points. Drawbacks give points back. Stay within your budget.")
			if _limits != null:
				t += "This skill has [b]%s points[/b] to spend.\n\n" % _n(_limits.point_budget)
			t += _point(_c("+", SkillScriptTab.COL_BUFF) + " lines make the skill better. They [b]cost[/b] points.") \
				+ _point(_c("-", SkillScriptTab.COL_DRAW) + " lines make it worse. They [b]give points back[/b].") \
				+ _point("The more you raise one line, the more each step costs.") \
				+ _point("Each line shows its price in the # note on its right.") \
				+ "\n" + _h2("One rule to remember") \
				+ "Points given back by a [b]when[/b] rule only pay for that same rule. To pay for other rules, put your drawbacks in [b]always:[/b].\n\n" \
				+ _h2("Over budget?") \
				+ _point("Lower a + line.") \
				+ _point("Make a when rule rarer.") \
				+ _point("Add a - line in always:.") \
				+ "\n" + _h2("Getting more points") \
				+ _point("Clear every enemy in an area: [b]+1[/b] (once per area).") \
				+ _point("Pass exams with MERIT or DISTINCTION.") \
				+ _point("Reach higher ranks.")
			return t
		"cheaper":
			return _h("Cheaper rules") \
				+ _short("A rule that's rarely on costs less. The header shows by how much.") \
				+ "Look at the grey note on a when line:\n\n" \
				+ _code([
					_kw("when ") + _fn("enemies_nearby") + _op("(") + _num("3") + _op(", ") + _num("4.0m") + _op("):") + _cm("   # buffs x0.60"),
				]) \
				+ "[b]x0.60[/b] means its buffs cost 60% of the normal price.\n\n" \
				+ _h2("Make it rarer, make it cheaper") \
				+ _point("Needing [b]more enemies[/b] makes it rarer.") \
				+ _point("[b]every_nth_cast(3)[/b] is on 1 cast in 3.") \
				+ _point("Two conditions in one header (when A [b]and[/b] B) are even rarer.") \
				+ "\n" + _h2("But...") \
				+ "A cheap rule that never turns on does nothing. Pick conditions that happen in your fights.\n\n" \
				+ _tip("Click a condition's numbers and watch the price change.")
		"blocks":
			var t := _h("Blocks") \
				+ _short("Short scripts get a bonus. Each condition and each line is one block.") \
				+ _code([
					_kw("always:") + _cm("                  # free"),
					"    " + _var("damage") + _op(" += ") + _num("10%") + _cm("       # 1 block"),
					_kw("when ") + _fn("every_nth_cast") + _op("(") + _num("3") + _op("):") + _cm(" # 1 block"),
					"    " + _var("radius") + _op(" += ") + _num("1.0m") + _cm("      # 1 block"),
				]) \
				+ "That's [b]3 blocks[/b].\n\n"
			if _limits != null:
				t += "This skill can hold [b]%d blocks[/b] in [b]%d rules[/b].\n\n" % [_limits.max_actions, _limits.max_rules]
			t += _h2("Bonus for short scripts")
			if _limits != null and not _limits.tiers.is_empty():
				for tier in _limits.tiers:
					t += _point("%s  %s" % [_c(tier.display_name.to_upper(), SkillScriptTab.COL_OK), tier.description])
			else:
				t += _point("%s  3 blocks or fewer: 12%% more damage." % _c("ELEGANT", SkillScriptTab.COL_OK)) \
					+ _point("%s  6 blocks or fewer: 6%% more damage." % _c("LEAN", SkillScriptTab.COL_OK))
			t += "\n" + _tip("A few strong lines beat many small ones.")
			return t
		"apply":
			return _h("Fixing and applying") \
				+ _short("Red means something's wrong. Hover it to see how to fix it.") \
				+ _h2("At the bottom") \
				+ _point("[b]OUTPUT[/b]: your points, blocks and bonus.") \
				+ _point("[b]ERRORS[/b]: what's wrong and how to fix it. It opens by itself.") \
				+ "\n" + _h2("The buttons") \
				+ _point("[b]apply()[/b]: use this script on your skill.") \
				+ _point("[b]revert()[/b]: undo everything since the last apply().") \
				+ _point("[b]clear()[/b]: delete every rule in this file.") \
				+ _point("[b]guide()[/b]: open this guide.") \
				+ "\n" + _tip("A when rule only shows off when its condition happens. Test it in the right fight.")
		"later":
			var r := _limits.rank if _limits != null else 0
			return _h("Unlocks") \
				+ _short("Pass rank exams with Examiner Sudo (in town) to unlock more.") \
				+ _rank_line(r, 1, "OPERATOR", "a second script set to swap to") \
				+ _rank_line(r, 2, "ARCHITECT", "loops: repeat your skill, if blocks, and break") \
				+ _rank_line(r, 3, "STRATEGIST", "the Registry (remember enemies)") \
				+ _rank_line(r, 4, "ENGINEER", "more rules and more points") \
				+ "\n" + _tip("Better exam grades give more points. You can retake an exam.")
	return ""


## The page's one-line summary, under its title.
func _short(text: String) -> String:
	return "[b]%s[/b]\n\n" % _c(text, Color.WHITE)


## One bullet point.
func _point(text: String) -> String:
	return "  • %s\n" % text


func _rank_line(have: int, need: int, rank_name: String, what: String) -> String:
	var mark := _c("[lb]ok[rb]", SkillScriptTab.COL_OK) if have >= need else _c("[lb]--[rb]", SkillScriptTab.COL_GUTTER)
	return "%s %s  %s\n" % [mark, _c(rank_name, SkillScriptTab.COL_PENDING), what]


# ---------- TEXT HELPERS ----------
static func _c(text: String, col: Color) -> String:
	return SkillScriptTab._c(text, col)


func _h(text: String) -> String:
	return "[font_size=%d]%s[/font_size]\n\n" % [tab._sz(17), _c(text.to_upper(), tab.panel.accent)]


func _h2(text: String) -> String:
	return _c(text, SkillScriptTab.COL_PENDING) + "\n"


func _tip(text: String) -> String:
	return _c("# tip: " + text, SkillScriptTab.COL_COMMENT)


## A block of example code, one string per line, on a dark band.
func _code(lines: Array) -> String:
	return "[bgcolor=#00000088]" + "\n".join(lines) + "[/bgcolor]\n\n"


static func _kw(t: String) -> String:
	return _c(t, SkillScriptTab.COL_KEYWORD)


static func _fn(t: String) -> String:
	return _c(t, SkillScriptTab.COL_FN)


static func _var(t: String) -> String:
	return _c(t, SkillScriptTab.COL_VAR)


static func _num(t: String) -> String:
	return _c(t, SkillScriptTab.COL_NUM)


static func _op(t: String) -> String:
	return _c(t, SkillScriptTab.COL_OP)


static func _cm(t: String) -> String:
	return _c(t, SkillScriptTab.COL_COMMENT)


static func _n(v: float) -> String:
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
