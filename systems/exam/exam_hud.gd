class_name ExamHud
extends CanvasLayer
## The exam's screens, over the sandbox (ExamChamber makes one):
##   brief    the spec card on the left: what the test asks, and how to start it
##   run      the same card turned into live stats: wave, clock, rule fires, health lost
##   result   a panel in the middle: the grade, the numbers, Sudo's debrief, RETRY / RETURN
## Messages (a refused script, the countdown) show big in the middle for a moment.

const FONT_PATH := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const ACCENT := Color("#00E5FF")
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_GOOD := Color(0.25, 1.0, 0.55)
const COL_WARN := Color(1.0, 0.35, 0.35)
const COL_GOLD := Color(1.0, 0.82, 0.30)
const GRADE_COLORS := [Color(0.85, 0.96, 1.0), Color(0.25, 1.0, 0.55), Color(1.0, 0.82, 0.30)]

var chamber: ExamChamber
var _font: Font
var _card: PanelContainer
## The card sits under the HUD (20), so the skills menu and inventory open over it. The result
## panel stays on this layer (21) so its buttons work.
const CARD_LAYER := 19
var _card_box: VBoxContainer
var _result: PanelContainer
var _result_box: VBoxContainer
var _flash: Label
var _flash_tween: Tween


func _ready() -> void:
	layer = 21                                    # over the HUD, so the result's buttons work
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var card_layer := CanvasLayer.new()
	card_layer.layer = CARD_LAYER
	add_child(card_layer)
	_card = _panel()
	_card.custom_minimum_size.x = 440
	_card.position = Vector2(24, 190)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_layer.add_child(_card)
	_card_box = _vbox(6)
	_card.add_child(_card_box)

	_result = _panel()
	_result.custom_minimum_size.x = 620
	_result.visible = false
	root.add_child(_result)
	_result_box = _vbox(8)
	_result.add_child(_result_box)

	_flash = _label("", 30, ACCENT)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_flash.offset_top = 260
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flash.custom_minimum_size.x = 900
	_flash.offset_left = -450
	_flash.offset_right = 450
	_flash.modulate.a = 0.0
	root.add_child(_flash)


# ---------- BRIEF ----------
func show_brief() -> void:
	_result.visible = false
	_card.visible = true
	_clear(_card_box)
	var spec := chamber.spec
	if spec == null:
		_card_box.add_child(_label("NO EXAM LOADED", 20, COL_WARN))
		return
	_card_box.add_child(_label("// SPEC: %s //" % spec.title, 20, ACCENT))
	_card_box.add_child(_rule())
	for line in spec.brief:
		_card_box.add_child(_wrapped("> " + line, 15, COL_TEXT))
	_card_box.add_child(_rule())
	var qm: QuestManager = chamber._player.get("quests") if chamber._player != null else null
	var best := qm.exam_grade(spec.rank_id) if qm != null else -1
	if best >= 0:
		_card_box.add_child(_label("BEST GRADE: %s" % ExamSpec.GRADES[best], 15, GRADE_COLORS[best]))
	_card_box.add_child(_wrapped("Edit your script with [K]. Then press [T] at the terminal to RUN.", 15, COL_GOLD))


## The terminal turned the script down.
func refuse(why: String) -> void:
	_show_flash(why, COL_WARN, 3.5)


# ---------- RUN ----------
var _run_labels: Array[Label] = []


func show_run() -> void:
	_result.visible = false
	_card.visible = true
	_clear(_card_box)
	_card_box.add_child(_label("// RUNNING: %s //" % chamber.spec.title, 20, ACCENT))
	_card_box.add_child(_rule())
	_run_labels.clear()
	for i in 4:
		var l := _label("", 17, COL_TEXT)
		_card_box.add_child(l)
		_run_labels.append(l)
	update_run(0, chamber.spec.wave_sizes.size(), 0.0, chamber.spec.time_limit, 0,
			chamber.spec.required_fires, 0.0)


func countdown() -> void:
	for n in [3, 2, 1]:
		_show_flash("RUN IN %d" % n, ACCENT, 0.8)
		await get_tree().create_timer(1.0, false).timeout
	if chamber.spec.wave_name(0) == "":          # otherwise the first wave's name goes up here
		_show_flash("EXECUTE", COL_GOOD, 0.8)


## A named wave starts: its name in big letters, in its colour, with what it is under it.
func announce_wave(index: int, spec: ExamSpec, tint: Color) -> void:
	var text := "WAVE %d // %s" % [index + 1, spec.wave_name(index)]
	if spec.wave_note(index) != "":
		text += "\n" + spec.wave_note(index)
	_show_flash(text, tint, 1.6)


func update_run(wave: int, waves: int, t: float, limit: float, fires: int, need: int, lost: float) -> void:
	if _run_labels.size() < 4:
		return
	_run_labels[0].text = "WAVE      %d / %d" % [wave, waves]
	var name_now := chamber.spec.wave_name(wave - 1)
	if name_now != "":
		_run_labels[0].text += "  " + name_now
		_run_labels[0].add_theme_color_override("font_color", chamber.spec.wave_tint(wave - 1))
	_run_labels[1].text = "TIME      %s / %s" % [_clock(t), _clock(limit)]
	_run_labels[1].add_theme_color_override("font_color", COL_WARN if limit - t < 10.0 else COL_TEXT)
	_run_labels[2].text = "%s  %d / %d" % [chamber.spec.required_condition_label, fires, need]
	_run_labels[2].add_theme_color_override("font_color", COL_GOOD if fires >= need else COL_GOLD)
	_run_labels[3].text = "HEALTH LOST  %d%%" % roundi(lost * 100.0)
	_run_labels[3].add_theme_color_override("font_color", COL_WARN if lost > chamber.spec.par_damage else COL_TEXT)


# ---------- RESULT ----------
func show_result(r: Dictionary) -> void:
	_card.visible = false
	_clear(_result_box)
	var spec := chamber.spec
	if r["passed"]:
		var g: int = r["grade"]
		_result_box.add_child(_label("%s  //  %s" % [spec.title, ExamSpec.GRADES[g]], 28, GRADE_COLORS[g]))
	else:
		_result_box.add_child(_label("%s  //  FAILED: %s" % [spec.title, r["fail"]], 26, COL_WARN))
	_result_box.add_child(_rule())
	# The numbers, each marked with whether it earned its grade point
	var tier: String = r["tier"]
	_result_box.add_child(_stat("SCRIPT TIER", tier.to_upper() if tier != "" else "NONE",
			"+2" if tier == "elegant" else ("+1" if tier == "lean" else "+0")))
	_result_box.add_child(_stat("TIME", "%s  (par %s)" % [_clock(r["time"]), _clock(spec.par_time)],
			"+1" if r["fast"] else "+0"))
	_result_box.add_child(_stat("HEALTH LOST", "%d%%  (par %d%%)" % [roundi(r["damage"] * 100.0),
			roundi(spec.par_damage * 100.0)], "+1" if r["unhurt"] else "+0"))
	if spec.set_per_wave:
		_result_box.add_child(_stat("SETS USED", "%d of %d, in %d swaps  (par %d)" % [r["fires"],
				spec.required_fires, r["swaps"], spec.par_swaps], ""))
	else:
		_result_box.add_child(_stat("RULE FIRED", "%d times in %d casts" % [r["fires"], r["casts"]], ""))
	_result_box.add_child(_rule())
	_result_box.add_child(_label("EXAMINER SUDO:", 16, ACCENT))
	for line in ExamDebrief.lines(spec, r):
		_result_box.add_child(_wrapped(line, 16, COL_TEXT))
	if r["passed"]:
		var note := ""
		if r["first_pass"]:
			note = "Report to Examiner Sudo to receive your rank."
			var unlocks := Ranks.unlock_lines(Ranks.LADDER.map(func(r: Dictionary) -> String: return r["id"]).find(spec.rank_id))
			if not unlocks.is_empty():
				note += "\nUnlocks: " +", ".join(unlocks) + "."
		elif r["new_best"]:
			note = "New best grade recorded."
		else:
			var qm: QuestManager = chamber._player.get("quests")
			note = "Your best is still %s." % ExamSpec.GRADES[qm.exam_grade(spec.rank_id)]
		_result_box.add_child(_label(note, 16, COL_GOLD))
	_result_box.add_child(_rule())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	_result_box.add_child(buttons)
	buttons.add_child(_button("RETRY", chamber.retry))
	buttons.add_child(_button("RETURN TO TOWN", chamber.leave))
	_result.visible = true
	_center_result.call_deferred()


func _center_result() -> void:
	_result.reset_size()
	var screen := get_viewport().get_visible_rect().size
	_result.position = ((screen - _result.size) * 0.5).round()


# ---------- HELPERS ----------
func _show_flash(text: String, col: Color, hold: float) -> void:
	_flash.text = text
	_flash.add_theme_color_override("font_color", col)
	_flash.modulate.a = 1.0
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_interval(hold)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.4)


static func _clock(t: float) -> String:
	var s := maxi(int(t), 0)
	return "%d:%02d" % [s / 60, s % 60]


func _stat(name: String, value: String, points: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var n := _label(name, 16, COL_DIM)
	n.custom_minimum_size.x = 170
	row.add_child(n)
	var v := _label(value, 16, COL_TEXT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	if points != "":
		row.add_child(_label(points, 16, COL_GOOD if points != "+0" else COL_DIM))
	return row


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.09, 0.92)
	sb.border_color = ACCENT
	sb.set_border_width_all(2)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _vbox(gap: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", gap)
	return b


func _rule() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxLine.new()
	sb.color = Color(ACCENT, 0.4)
	s.add_theme_stylebox_override("separator", sb)
	return s


func _label(text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	if _font:
		l.add_theme_font_override("font", _font)
	return l


func _wrapped(text: String, size_px: int, col: Color) -> Label:
	var l := _label(text, size_px, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 400
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 44)
	b.add_theme_font_size_override("font_size", 17)
	if _font:
		b.add_theme_font_override("font", _font)
	b.pressed.connect(action)
	return b


func _clear(box: Container) -> void:
	for c in box.get_children():
		c.queue_free()
