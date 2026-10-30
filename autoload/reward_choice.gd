extends CanvasLayer
## Autoload: RewardChoice
## "Pick a support gem" quest reward. Opens by itself whenever the player's QuestManager has a
## choice waiting (pending_choices), lists the support gems that fit the class's starting skill,
## and gives the picked one with QuestManager.claim_choice(). It can't be closed without
## picking, and an unpicked choice is saved, so the reward is never lost.

const FONT_PATH := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const ACCENT := Color("#00E5FF")
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_GEM := Color(0.45, 0.75, 1.0)          # support gem blue, as in the skill menu
const COL_WARN := Color(1.0, 0.30, 0.37)
const COL_BG := Color(0.02, 0.06, 0.08, 0.96)
const CARD_WIDTH := 760.0
const LIST_HEIGHT := 470.0
const ANY_SKILL_TAGS := [TagTypes.TagGem.STRIKE, TagTypes.TagGem.SLAM, TagTypes.TagGem.SPELL, TagTypes.TagGem.SHOOT]

var _font: Font
var _root: Control
var _title: Label
var _subtitle: Label
var _list: VBoxContainer
var _take: Button
var _msg: Label
var _options: Array = []                 # [{def, panel}]
var _picked: ItemDefinition
var _quests: QuestManager
var _open := false


func _ready() -> void:
	layer = 30                           # over the HUD (20) and dialogue, under tutorial hints (50)
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	_build()
	_root.visible = false


func is_open() -> bool:
	return _open


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("players")
	var qm: QuestManager = player.get("quests") if player != null else null
	_quests = qm
	var waiting := qm != null and not qm.pending_choices.is_empty()
	if waiting and not _open:
		_show()
	elif not waiting and _open:
		_hide()


# ---------- OPEN / CLOSE ----------
func _show() -> void:
	_open = true
	_picked = null
	_msg.text = ""
	var quest_id: String = _quests.pending_choices[0]
	var def := _quests.get_def(quest_id)
	var skill := _quests.starting_skill()
	_title.text = "CHOOSE A SUPPORT GEM"
	_subtitle.text = "%s complete. Pick one support gem for your %s skill: it goes into your backpack. Socket it next to the skill in the skill menu." % [
		def.title if def != null else "Quest", skill.display_name if skill != null else "starting"]
	for child in _list.get_children():
		child.queue_free()
	_options.clear()
	for item in _quests.support_choices():
		var panel := _option(item, skill)
		_list.add_child(panel)
		_options.append({"def": item, "panel": panel})
	_refresh()
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true


func _hide() -> void:
	_open = false
	_root.visible = false


func _on_take() -> void:
	if _picked == null or _quests == null:
		return
	var err := _quests.claim_choice(_picked)
	if err != "":
		_msg.text = err
		return
	# closes on the next frame, when pending_choices is empty (or shows the next choice)


# ---------- UI ----------
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP          # nothing behind it can be clicked
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	card.add_theme_stylebox_override("panel", _box(COL_BG, ACCENT, 2, 22))
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	_title = _label("", 26, ACCENT)
	col.add_child(_title)
	_subtitle = _label("", 15, COL_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_subtitle)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = LIST_HEIGHT
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	_msg = _label("", 15, COL_WARN)
	_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_msg)
	_take = Button.new()
	_take.text = "TAKE"
	_take.custom_minimum_size = Vector2(180, 44)
	_take.focus_mode = Control.FOCUS_NONE
	if _font:
		_take.add_theme_font_override("font", _font)
	_take.add_theme_font_size_override("font_size", 20)
	_take.add_theme_color_override("font_color", ACCENT)
	_take.add_theme_color_override("font_disabled_color", Color(COL_DIM, 0.4))
	_take.add_theme_stylebox_override("normal", _box(Color(ACCENT, 0.10), ACCENT, 2, 8))
	_take.add_theme_stylebox_override("hover", _box(Color(ACCENT, 0.22), ACCENT, 2, 8))
	_take.add_theme_stylebox_override("pressed", _box(Color(ACCENT, 0.30), ACCENT, 2, 8))
	_take.add_theme_stylebox_override("disabled", _box(Color(0, 0, 0, 0.3), Color(COL_DIM, 0.3), 1, 8))
	_take.pressed.connect(_on_take)
	foot.add_child(_take)


## One clickable choice: gem name, what it fits, and its description.
func _option(item: ItemDefinition, skill: SkillGemDefinition) -> PanelContainer:
	var sup := item.support_gem
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var name_label := _label(sup.display_name.to_upper(), 19, COL_GEM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	head.add_child(_label(_fits_text(sup, skill), 13, COL_DIM))

	var desc_text := sup.description.strip_edges()
	if desc_text == "":
		desc_text = "Changes how your skill works. Hover it in the skill menu for details."
	var desc := _label(desc_text, 14, COL_TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = CARD_WIDTH - 90.0
	box.add_child(desc)
	if not sup.program_knobs.is_empty():
		box.add_child(_label("+ adds its own file to your skill's script", 13, Color(1.0, 0.50, 0.78)))

	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_picked = item
			_msg.text = ""
			_refresh()
			if ev.double_click:
				_on_take())
	return panel


func _fits_text(sup: SupportGemDefinition, skill: SkillGemDefinition) -> String:
	var any := true
	for t in ANY_SKILL_TAGS:
		if not (t in sup.allowed_tags):
			any = false
	if any:
		return "ANY SKILL"
	return ("%s" % skill.display_name).to_upper() if skill != null else ""


func _refresh() -> void:
	for o in _options:
		var on: bool = o["def"] == _picked
		(o["panel"] as PanelContainer).add_theme_stylebox_override("panel",
			_box(Color(ACCENT, 0.16) if on else Color(1, 1, 1, 0.03), ACCENT if on else Color(ACCENT, 0.25), 2 if on else 1, 12))
	_take.disabled = _picked == null
	_take.text = "TAKE %s" % _picked.support_gem.display_name.trim_suffix(" Support").to_upper() if _picked != null else "PICK ONE"


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _box(bg: Color, border: Color, width: int, margin: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_content_margin_all(margin)
	return sb
