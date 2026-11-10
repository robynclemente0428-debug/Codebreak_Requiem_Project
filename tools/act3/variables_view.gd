extends Node
## A look at variables in the real SCRIPTING tab. Run this scene from the editor (F6). Boots main.tscn
## with NO character slot loaded (nothing is saved), lends variables, sockets Slam with the registry
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
	var count := ProgramRule.new()                             # always: registry.add(target)
	count.effects.append(ProgramEffect.make_write("add"))
	var growing := ProgramEffect.make(&"damage", 1)             # damage += registry.size * 1%
	growing.ramp = 0
	count.effects.append(growing)
	var spend := ProgramRule.new()                             # when target in registry: damage, remove
	spend.conditions.append(VarCondition.make("target", "in"))
	spend.effects.append(ProgramEffect.make(&"leech", 1))
	spend.effects.append(ProgramEffect.make_write("remove"))
	var sized := ProgramRule.new()                             # when registry.size >= 3: damage
	sized.conditions.append(VarCondition.make("size", ">=", 3))
	sized.effects.append(ProgramEffect.make(&"radius", 1))
	program.rules = [count, spend, sized] as Array[ProgramRule]
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
		if "registry" in text or text in ["target", "(target)", ">=", "<", "3"]:
			labels.append(text)
	lines.append("labels: %s" % " | ".join(labels))
	var scroller := tab._effect_num[tab._draft().rules[0].effects[-1]].get_parent() as Control
	while scroller != null and not scroller is ScrollContainer:
		scroller = scroller.get_parent() as Control
	if scroller != null:
		(scroller as ScrollContainer).ensure_control_visible(tab._effect_num[tab._draft().rules[0].effects[-1]])
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


## Every way a registry piece can land, through the same call a real drop makes.
func _try_pieces(tab: SkillScriptTab) -> PackedStringArray:
	var out := PackedStringArray()
	var check := func(what: String, ok: bool) -> void:
		out.append("%s  %s" % ["ok  " if ok else "FAIL", what])
	var set_write := func(i: int) -> Dictionary: return {"src": "palette", "kind": "set_write", "op": i}
	var member := func(i: int) -> Dictionary: return {"src": "palette", "kind": "member", "op": i}
	var size := {"src": "palette", "kind": "size"}
	var compare := func(i: int) -> Dictionary: return {"src": "palette", "kind": "compare_op", "op": i}
	var drop := func(data: Dictionary, rule: ProgramRule, line: Dictionary) -> void:
		tab._drop_on_rule(Vector2.ZERO, data, rule, line)
	var rules := tab._draft().rules
	var count: ProgramRule = rules[0]
	var spend: ProgramRule = rules[1]
	var write: ProgramEffect = count.effects[0]
	var read: VarCondition = spend.conditions[0]
	var leech: ProgramEffect = spend.effects[0]

	drop.call(set_write.call(1), count, {"kind": "effect", "effect": write})
	check.call("remove on add: %s" % write.describe_write(), write.describe_write() == "registry.remove(target)")
	drop.call(set_write.call(0), count, {"kind": "effect", "effect": write})
	check.call("add on remove: %s" % write.describe_write(), write.describe_write() == "registry.add(target)")
	drop.call(member.call(1), spend, {"kind": "condition", "condition": read})
	check.call("not in on in: %s" % read.describe(), read.describe() == "WHEN target not in registry")
	drop.call(compare.call(5), spend, {"kind": "condition", "condition": read})
	check.call("!= on a check makes it a size check: %s" % read.describe(), read.describe() == "WHEN registry.size != 3")
	drop.call(member.call(0), spend, {"kind": "condition", "condition": read})
	check.call("in on it again: %s" % read.describe(), read.describe() == "WHEN target in registry")
	drop.call(size, spend, {"kind": "effect", "effect": leech})
	check.call(".size on leech: it grows (%s)" % leech.ramp_text(), leech.ramp == 0)

	var before := spend.effects.size()
	drop.call(set_write.call(0), spend, {})
	check.call("add on a rule adds a line", spend.effects.size() == before + 1 and (spend.effects[-1] as ProgramEffect).describe_write() == "registry.add(target)")
	var conds := count.conditions.size()
	drop.call(size, count, {})
	check.call(".size on a rule adds a check: %s" % (count.conditions[-1] as ProgramCondition).describe(), count.conditions.size() == conds + 1 and (count.conditions[-1] as ProgramCondition).describe() == "WHEN registry.size >= 3")

	var speed := ProgramEffect.make(&"attack_speed", 1)
	spend.effects.append(speed)
	drop.call(size, spend, {"kind": "effect", "effect": speed})
	check.call(".size on attack_speed: refused", speed.ramp == -1)
	spend.effects.erase(speed)

	var count_rules := tab._draft().rules.size()
	tab._add_from_palette(compare.call(3), null)
	check.call(">= with no rule starts a new one", tab._draft().rules.size() == count_rules + 1)
	tab._add_from_palette(set_write.call(0), null)
	check.call("add with no rule starts a new one", tab._draft().rules.size() == count_rules + 2)
	tab._draft().rules.resize(count_rules)
	tab._changed()
	return out

func _wheel_up() -> InputEventMouseButton:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	return wheel
