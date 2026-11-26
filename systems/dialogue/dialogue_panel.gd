class_name DialoguePanel
extends Control

signal line_advanced
signal choice_picked(entry)

@export var panel_width: float = 860.0
@export var panel_height: float = 300.0
@export var vertical_offset: float = 120.0       # pushes the box below screen centre
@export_range(0.0, 1.0, 0.01) var bg_opacity: float = 0.92
@export var font: Font
@export var accent := Color("#00E5FF")
@export var text_size: int = 20
@export var chars_per_second: float = 60.0
@export var max_distance: float = 6.0            # walking this far from the NPC closes it
## The box grows upward to fit long lines and many choices, up to this height.
## Past it, the choice list scrolls.
@export var max_panel_height: float = 640.0

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const CHAMFER := 24.0
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_WARN := Color(1.0, 0.30, 0.37)
const HINT_LINE := "[ CLICK / SPACE / E ] CONTINUE   |   [ ESC ] LEAVE"
const HINT_CHOICE := "[ 1-9 ] OR CLICK TO CHOOSE   |   [ ESC ] LEAVE"

var _font: Font
var _built := false
var _open := false
var _tween: Tween
var _type_tween: Tween
var _typing := false
var _waiting_choice := false
var _current_choices: Array = []
var _opened_frame := -1
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _changed_mouse_mode := false

var _nodes: Dictionary = {}
var _npc: DialogueNPC
var _player: Node3D
var _quests: QuestManager
var _wallet: CurrencyComponent
var _reach := 0.0                   # opened from the NPC card: walk this far before it closes

var _speaker: Label
var _text: Label
var _choice_box: VBoxContainer
var _choice_scroll: ScrollContainer
var _margin: MarginContainer
var _hint: Label


func _enter_tree() -> void:
	add_to_group("dialogue_panel")


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
	offset_top = -panel_height * 0.5 + vertical_offset
	offset_bottom = panel_height * 0.5 + vertical_offset
	resized.connect(queue_redraw)
	_build_ui()
	_built = true
	visible = false
	modulate.a = 0.0


# ---------- PUBLIC ----------
func is_open() -> bool:
	return _open


## start_label: the node to begin at ("start" unless the NPC card jumps straight to a quest).
## reach: how far you may be from the NPC before it closes (0 = max_distance). The NPC card
## passes your current distance, so you can talk from where you clicked.
func open_dialogue(npc: DialogueNPC, player: Node3D, start_label: String = "start", reach: float = 0.0) -> void:
	if _open or not _built or npc.dialogue == null:
		return
	_nodes = npc.dialogue.get_nodes()
	if not _nodes.has("start"):
		push_warning("Dialogue has no '~ start' node")
		return
	if not _nodes.has(start_label):
		start_label = "start"
	_reach = reach
	_npc = npc
	_player = player
	npc.engage(player)                         # turn to face whoever is talking to it
	_quests = player.get("quests")
	_wallet = player.get("currency")

	_open = true
	_opened_frame = Engine.get_process_frames()
	if "input_locked" in _player:
		_player.input_locked = true
	var mode := Input.mouse_mode
	if mode == Input.MOUSE_MODE_CAPTURED or mode == Input.MOUSE_MODE_HIDDEN \
			or mode == Input.MOUSE_MODE_CONFINED_HIDDEN:
		_prev_mouse_mode = mode
		_changed_mouse_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	_fade(1.0)
	_run(start_label)


func close() -> void:
	if not _open:
		return
	_open = false
	_waiting_choice = false
	if _type_tween:
		_type_tween.kill()
	# wake any waiting coroutine so it can exit
	line_advanced.emit()
	choice_picked.emit(null)
	if _player and is_instance_valid(_player) and "input_locked" in _player:
		_player.input_locked = false
	_npc = null
	if _changed_mouse_mode:
		Input.mouse_mode = _prev_mouse_mode
		_changed_mouse_mode = false
	_fade(0.0)

func _hint_line() -> String:
	return "[ CLICK / SPACE / %s ] CONTINUE   |   [ ESC ] LEAVE" % Interactable.key_name()

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
	if _open and _npc != null and _player != null and is_instance_valid(_player):
		if _player.global_position.distance_to(_npc.global_position) > maxf(max_distance, _reach):
			close()


# ---------- INPUT ----------
func _unhandled_input(event: InputEvent) -> void:
	if not _open or Engine.get_process_frames() == _opened_frame:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif _waiting_choice:
		var n: int = event.keycode - KEY_1
		if n >= 0 and n < _current_choices.size():
			_pick(n)
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.is_action_pressed("interact"):
		_advance_pressed()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if _open and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_advance_pressed()
		accept_event()


func _advance_pressed() -> void:
	if _waiting_choice:
		return
	if _typing:                                  # first press finishes the typing
		if _type_tween:
			_type_tween.kill()
		_text.visible_ratio = 1.0
		_typing = false
		return
	line_advanced.emit()


# ---------- RUNNING THE SCRIPT ----------
func _run(start_label: String) -> void:
	var label := start_label
	var hops := 0
	while label != "" and label != "end" and _open and hops < 200:
		hops += 1
		label = await _run_node(label)
	close()


## Runs one node. Returns the label to go to next, or "" to finish.
func _run_node(label: String) -> String:
	if not _nodes.has(label):
		push_warning("Dialogue: no node called '%s'" % label)
		return ""
	var choices: Array = []
	for e in _nodes[label]:
		if not _open:
			return ""
		match e["t"]:
			"jump":
				if e["cond"] == "" or _check(e["cond"]):
					return e["goto"]
			"act":
				var next: String = await _do(e)
				if next != "":
					return next
			"line":
				await _say(e["speaker"], e["text"])
			"choice":
				if e["cond"] == "" or _check(e["cond"]):
					choices.append(e)
	if choices.is_empty() or not _open:
		return ""
	var picked = await _choose(choices)
	if picked == null or not _open:
		return ""
	return picked["goto"]


func _say(speaker: String, text: String) -> void:
	_clear_choices()
	_hint.text = _hint_line()
	_speaker.text = (speaker if speaker != "" else _npc.npc_name).to_upper()
	_speaker.add_theme_color_override("font_color", COL_WARN if speaker == "SYSTEM" else accent)
	_text.text = text
	_text.visible_ratio = 0.0
	_fit.call_deferred()                    # a long line can make the box taller
	_typing = true
	if _type_tween:
		_type_tween.kill()
	_type_tween = create_tween()
	_type_tween.tween_property(_text, "visible_ratio", 1.0,
			maxf(0.15, text.length() / chars_per_second))
	_type_tween.finished.connect(func() -> void: _typing = false)
	await line_advanced


func _choose(choices: Array):
	_clear_choices()
	_current_choices = choices
	_waiting_choice = true
	_hint.text = HINT_CHOICE
	for i in choices.size():
		var b := _button("%d.  %s" % [i + 1, choices[i]["text"]], 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART    # long choices wrap instead of widening the box
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_pick.bind(i))
		_choice_box.add_child(b)
	_fit.call_deferred()
	var picked = await choice_picked
	_waiting_choice = false
	_clear_choices()
	return picked


func _pick(i: int) -> void:
	if _waiting_choice and i >= 0 and i < _current_choices.size():
		choice_picked.emit(_current_choices[i])


func _clear_choices() -> void:
	for child in _choice_box.get_children():
		_choice_box.remove_child(child)
		child.queue_free()
	_fit.call_deferred()


## Resizes the box to its content: it keeps its bottom edge and grows upward, never shorter
## than panel_height and never taller than max_panel_height (the choice list scrolls past that).
func _fit() -> void:
	if not _built:
		return
	var rows := _choice_box.get_combined_minimum_size().y
	_choice_scroll.visible = _choice_box.get_child_count() > 0
	_choice_scroll.custom_minimum_size.y = 0.0
	var without_choices := _margin.get_combined_minimum_size().y
	var room := maxf(max_panel_height - without_choices, 80.0)
	_choice_scroll.custom_minimum_size.y = minf(rows, room)
	var height := clampf(_margin.get_combined_minimum_size().y, panel_height, max_panel_height)
	offset_top = offset_bottom - height
	queue_redraw()


# ---------- CONDITIONS AND ACTIONS ----------
func _check(cond: String) -> bool:
	var negate := cond.begins_with("!")
	if negate:
		cond = cond.substr(1).strip_edges()
	var parts := cond.split(":", true, 1)
	var arg := parts[1].strip_edges() if parts.size() > 1 else ""
	var result := false
	if _quests != null:
		match parts[0]:
			"quest_active":
				result = _quests.is_active(arg)
			"quest_ready":
				var s := _quests.get_state(arg)
				result = s != null and s.status == QuestState.Status.READY_TO_TURN_IN
			"quest_done":
				result = _quests.is_completed(arg)
			"can_start":
				result = _quests.can_start(_quests.get_def(arg))
			"recovered":                          # a quest item or event (QuestItems id)
				result = _quests.has_recovered(arg)
			"exam_ungraded":                      # @ exam_ungraded:defragmenter: the rank's exam quest is
				# done but no sandbox grade was ever recorded: passed before the exam was a sandbox one
				result = _quests.is_completed("exam_" + arg) and _quests.exam_grade(arg) < 0
			"kernel_leans":                       # @ kernel_leans:merge: the answer given most (KernelScript.lean)
				result = KernelScript.lean(_quests) == arg   # (KernelScript.lean)
			"kernel_overwrites":                  # @ kernel_overwrites:2: at least that many pull requests overwritten
				result = int(KernelScript.tally(_quests)["overwrite"]) >= int(arg)
			"kernel_kept":                        # @ kernel_kept:2: at least that many pull requests merged (running)
				result = KernelScript.null_running(_quests).size() >= int(arg)
			"crate_news":                         # @ crate_news:CargoD: a Yard Sweep deleted it, and
				result = YardCrates.has_news(_quests, arg)   # its owner hasn't said so yet (YardCrates)
			"crate_deleted":                      # @ crate_deleted:CargoB: deleted, not brought back
				result = YardCrates.is_deleted(_quests, arg)
			"crate_restored":                     # @ crate_restored:CargoB: back from C-0's queue
				result = YardCrates.was_restored(_quests, arg)
			"deed":                               # @ deed:ending:merge, or @ deed:ending:any
				var d := arg.split(":", true, 1)
				if d.size() == 2 and d[1] == "any":
					for k in _quests.deeds:
						if str(k).begins_with(d[0] + ":"):
							result = true
				elif d.size() == 2:
					result = _quests.deed_count(d[0], d[1]) > 0
	if parts[0] == "here":                     # @ here:act_4_the_fray: the area's scene file name
		var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
		result = am != null and am.current_area != null \
				and am.current_area.scene_file_path.get_file().get_basename() == arg
	if parts[0] == "has_credits" and _wallet != null:
		result = _wallet.amount >= int(arg)
	return result != negate


## Returns "" to carry on, or a label ("end" to stop).
func _do(e: Dictionary) -> String:
	var args: PackedStringArray = e["args"]
	match e["name"]:
		"start_quest":
			if _quests and args.size() > 0:
				_quests.start_by_id(args[0])
		"turn_in":
			if _quests and args.size() > 0:
				var err := _quests.turn_in(args[0])
				if err != "":
					await _say("SYSTEM", err)
					return "end"
		"give_credits":
			if _wallet and args.size() > 0:
				_wallet.add(int(args[0]))
		"report":
			if args.size() > 0:
				GameEvents.report(args[0], args[1] if args.size() > 1 else "")
		"recover":                               # > recover quarantine_lifted: a QuestItems event
			if _quests and args.size() > 0:
				_quests.recover(args[0])
		"census":                                # > census: the Registrar reads what Hardfault kept (YardCrates)
			for line in YardCrates.census_lines(_quests):
				if not _open:
					return "end"
				await _say("", line)
		"exam":                                  # > exam operator: into Sudo's sandbox
			if args.size() > 0:
				close()
				ExamChamber.enter(get_tree(), args[0])
			return "end"
		"ending":                                # > ending merge: the ending card (EndingCard)
			if args.size() > 0:
				var chosen := Endings.choose(_quests, args[0])   # final: refused once one is chosen
				close()
				if chosen:
					load("res://scenes/ui/ending/ending_card.gd").show_ending(get_tree(), args[0])
			return "end"
		"epilogue":                              # > epilogue: the chosen ending's card, read again
			close()
			if Endings.current(_quests) != "":
				load("res://scenes/ui/ending/ending_card.gd").show_ending(get_tree(), Endings.current(_quests))
			return "end"
		"open_shop":
			if _npc is ShopNPC:
				var shop_panel := get_tree().get_first_node_in_group("shop_panel") as ShopPanel
				var shop_npc := _npc as ShopNPC
				var who := _player
				var reach := _reach
				close()                          # releases the lock and the mouse
				if shop_panel:
					shop_panel.open_shop(shop_npc, who, reach)
			return "end"
		_:
			push_warning("Dialogue: unknown action '%s'" % e["name"])
	return ""


# ---------- BUILDING THE UI ----------
func _draw() -> void:
	var w := size.x
	var h := size.y
	var c := CHAMFER
	var pts := PackedVector2Array([
		Vector2(c, 0), Vector2(w, 0), Vector2(w, h - c),
		Vector2(w - c, h), Vector2(0, h), Vector2(0, c)])
	draw_colored_polygon(pts, Color(0.02, 0.06, 0.09, bg_opacity))
	var line := pts.duplicate()
	line.append(pts[0])
	draw_polyline(line, accent, 2.0)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	_margin = margin
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 16)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	_speaker = _label("", 22, accent)
	col.add_child(_speaker)
	col.add_child(_rule())

	_text = _label("", text_size, COL_TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size.y = 90
	col.add_child(_text)

	_choice_scroll = ScrollContainer.new()
	_choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_scroll.visible = false
	col.add_child(_choice_scroll)
	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 6)
	_choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_scroll.add_child(_choice_box)

	_hint = _label(_hint_line(), 13, COL_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)


# ---------- STYLING HELPERS ----------
func _label(text: String, size_px: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", colour)
	if _font:
		l.add_theme_font_override("font", _font)
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size.y = 1
	r.color = Color(accent, 0.35)
	return r


func _flat(bg: Color, border: Color, border_px: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_px)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _button(text: String, size_px: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size_px)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", accent)
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_stylebox_override("normal", _flat(Color(0, 0, 0, 0.25), Color(accent, 0.35), 1))
	b.add_theme_stylebox_override("hover", _flat(Color(accent, 0.12), accent, 1))
	b.add_theme_stylebox_override("pressed", _flat(Color(accent, 0.25), accent, 1))
	return b
