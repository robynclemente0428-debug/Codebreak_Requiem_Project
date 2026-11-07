extends Node
## A look at variables in the real SCRIPTING tab. Run this scene from the editor (F6). Boots main.tscn
## with NO character slot loaded (nothing is saved), lends variables, sockets Slam with a counter
## on it and opens the tab. Then it adds a block from the snippets the way a click does, to show
## that path works, and writes what it found to variables_view_results.txt (gitignored).

const MAIN := "res://scenes/map/main.tscn"
const YARD := "res://scenes/map/town/act_3_quarantine_yard.tscn"
const RESULTS := "res://tools/act3/variables_view_results.txt"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var main: Node = load(MAIN).instantiate()
	for n in main.find_children("*", "", true, false):
		if n is AreaManager:
			n.start_area = YARD
	reparent(get_tree().root)
	var old := get_tree().current_scene
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	if old != null and old != self:
		old.queue_free()
	while get_tree().get_first_node_in_group("players") == null:
		await get_tree().process_frame
	await get_tree().create_timer(3.0, true).timeout
	var player := get_tree().get_first_node_in_group("players")
	var skills: SkillComponent = player.get("skills")
	Ranks.lent = PackedStringArray(["variables"])
	skills.refresh_rank()
	var gem := ItemInstance.new()
	gem.definition = load("res://data/items/gem/slam_gem.tres")
	skills.socket_skill(0, gem)
	var program := SkillProgram.new()
	var count := ProgramRule.new()
	count.conditions.append(ProgramConditions.create("hit_recently"))
	count.effects.append(ProgramEffect.make_write("x", "+=", 1))
	program.rules.append(count)
	var spend := ProgramRule.new()
	spend.conditions.append(VarCondition.make("x", ">=", 3))
	spend.effects.append(ProgramEffect.make(&"damage", 1))
	spend.effects.append(ProgramEffect.make_write("x", "=", 0))
	program.rules.append(spend)
	var trip := ProgramRule.new()                               # a one-way switch: nothing lowers y
	trip.conditions.append(ProgramConditions.create("caster_life_below"))
	trip.effects.append(ProgramEffect.make_write("y", "=", 1))
	program.rules.append(trip)
	var latched := ProgramRule.new()
	latched.conditions.append(VarCondition.make("y", "==", 1))
	latched.effects.append(ProgramEffect.make_write("y", "=", 0))
	var growing := ProgramEffect.make(&"damage", 1)             # damage += x * 1%
	growing.ramp = 0
	count.effects.append(growing)
	program.rules.append(latched)
	program.rules = [latched, trip, count, spend] as Array[ProgramRule]   # the note in view
	var v := skills.set_program(0, program)
	var panel := main.find_children("*", "SkillPanel", true, false)[0] as SkillPanel
	panel.open()
	panel.show_tab("scripting")
	await get_tree().create_timer(1.0, true).timeout

	var tab := panel._script_page
	var lines := PackedStringArray()
	lines.append("valid: %s  blocks: %d  tier: %s" % [v.valid, v.actions_used, v.tier.display_name if v.tier != null else "none"])
	lines.append("palette: %s" % ", ".join(tab.palette_items()))
	var labels := PackedStringArray()
	for l in tab.find_children("*", "Label", true, false):
		var text: String = (l as Label).text
		if text in ["x", "y", "=", "+=", "-=", ">=", "<", "3", "1", "0"] or "x +=" in text or "x >=" in text:
			labels.append(text)
	lines.append("labels: %s" % " | ".join(labels))
	var scroller := tab._effect_num[tab._draft().rules[2].effects[-1]].get_parent() as Control
	while scroller != null and not scroller is ScrollContainer:
		scroller = scroller.get_parent() as Control
	if scroller != null:
		(scroller as ScrollContainer).ensure_control_visible(tab._effect_num[tab._draft().rules[2].effects[-1]])
	await get_tree().create_timer(10.0, true).timeout   # time for a screenshot of the growing lines
	lines.append_array(_try_pieces(tab))
	tab._set_palette_tab("defense")
	tab._build_palette()
	var defense_list := PackedStringArray()
	for item in tab.palette_items():
		defense_list.append(item)
	lines.append("defense tab: %s" % ", ".join(defense_list))
	tab._set_palette_tab("offense")
	tab._build_palette()
	var order := PackedStringArray()
	for c in tab._palette_box.get_children():
		order.append(c.text.strip_edges() if c is Label else "*")
	lines.append("snippets, * being a block: %s" % " ".join(order))
	var f := FileAccess.open(RESULTS, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\nDONE\n")


## Every way a counter piece can land, through the same call a real drop makes.
func _try_pieces(tab: SkillScriptTab) -> PackedStringArray:
	var out := PackedStringArray()
	var check := func(what: String, ok: bool) -> void:
		out.append("%s  %s" % ["ok  " if ok else "FAIL", what])
	var counter := func(i: int) -> Dictionary: return {"src": "palette", "kind": "counter", "reg": i}
	var assign := func(i: int) -> Dictionary: return {"src": "palette", "kind": "assign_op", "op": i}
	var compare := func(i: int) -> Dictionary: return {"src": "palette", "kind": "compare_op", "op": i}
	var drop := func(data: Dictionary, rule: ProgramRule, line: Dictionary) -> void:
		tab._drop_on_rule(Vector2.ZERO, data, rule, line)
	var rules := tab._draft().rules
	var latched: ProgramRule = rules[0]
	var count: ProgramRule = rules[2]
	var spend: ProgramRule = rules[3]
	var damage: ProgramEffect = spend.effects[0]
	var write: ProgramEffect = count.effects[0]
	var read: VarCondition = spend.conditions[0]

	drop.call(counter.call(1), spend, {"kind": "effect", "effect": damage})
	check.call("y on damage: it grows with y (%s)" % damage.ramp_text(), damage.ramp == 1 and damage.steps == 1)
	drop.call(counter.call(0), spend, {"kind": "effect", "effect": damage})
	check.call("x on damage: now it grows with x (%s)" % damage.ramp_text(), damage.ramp == 0)
	drop.call(counter.call(1), count, {"kind": "effect", "effect": write})
	check.call("y on x += 1: %s" % write.describe_write(), write.describe_write() == "y += 1")
	drop.call(assign.call(2), count, {"kind": "effect", "effect": write})
	check.call("-= on that line: %s" % write.describe_write(), write.describe_write() == "y -= 1")
	drop.call(counter.call(1), spend, {"kind": "condition", "condition": read})
	drop.call(compare.call(5), spend, {"kind": "condition", "condition": read})
	check.call("y and != on x >= 3: %s" % read.describe(), read.describe() == "WHEN y != 3")

	var before := spend.effects.size()
	drop.call(assign.call(0), spend, {})
	var added: ProgramEffect = spend.effects[-1]
	check.call("= on a rule adds a line: %s" % added.describe_write(), spend.effects.size() == before + 1 and added.describe_write() == "x = 0")
	drop.call(counter.call(1), spend, {})
	check.call("y on a rule adds a line: %s" % (spend.effects[-1] as ProgramEffect).describe_write(), (spend.effects[-1] as ProgramEffect).describe_write() == "y += 1")
	var conds := latched.conditions.size()
	drop.call(compare.call(0), latched, {})
	check.call("< on a rule adds a read: %s" % (latched.conditions[-1] as ProgramCondition).describe(), latched.conditions.size() == conds + 1 and (latched.conditions[-1] as ProgramCondition).describe() == "WHEN x < 3")
	drop.call(assign.call(0), latched, {"kind": "condition", "condition": latched.conditions[0]})
	check.call("= on a WHEN line adds a write, not a broken read", ScriptRegisters.is_write((latched.effects[-1] as ProgramEffect).knob))

	var speed := ProgramEffect.make(&"attack_speed", 1)
	latched.effects.append(speed)
	drop.call(counter.call(0), latched, {"kind": "effect", "effect": speed})
	check.call("x on attack_speed: refused", speed.ramp == -1)
	latched.effects.erase(speed)

	var value_line: ProgramEffect = tab._draft().rules[2].effects[0]
	for _i in 9:
		(tab._effect_num[value_line] as Control).gui_input.emit(_wheel_up())
	check.call("clicking a counter line's value stops at %d (%s)" % [ScriptRegisters.WRITE_MAX, value_line.describe_write()], value_line.steps == ScriptRegisters.WRITE_MAX)

	var count_rules := tab._draft().rules.size()
	tab._add_from_palette(compare.call(3), null)
	check.call(">= with no rule starts a new one", tab._draft().rules.size() == count_rules + 1)
	tab._add_from_palette(assign.call(1), null)
	check.call("+= with no rule starts a new one", tab._draft().rules.size() == count_rules + 2)
	tab._draft().rules.resize(count_rules)
	tab._changed()
	return out


func _wheel_up() -> InputEventMouseButton:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	return wheel
