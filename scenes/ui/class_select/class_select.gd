extends Control

const CLASS_DIR := "res://data/classes/"
const CLASS_CARD_SCENE := preload("res://scenes/ui/class_select/class_card.tscn")
# Check this path with right-click → Copy Path in the FileSystem dock
const CHARACTER_SELECT_SCENE := "res://scenes/ui/character_slots/character_select.tscn"
const ATTR_MAX := 24.0          # attribute value that fills a bar completely

@onready var class_list: VBoxContainer = %ClassList
@onready var info_panel: Control = %InfoPanel
@onready var class_name_label: Label = %ClassName
@onready var tagline_label: Label = %TagLine
@onready var description_label: Label = %Description
@onready var attribute_list: VBoxContainer = %AttributeList
@onready var skill_label: Label = %SkillLabel
@onready var preview_container: SubViewportContainer = %PreviewContainer
@onready var model_pivot: Node3D = %ModelPivot
@onready var name_input: LineEdit = %NameInput
@onready var error_label: Label = %ErrorLabel
@onready var create_button: Button = %CreateButton
@onready var back_button: TextureButton = %BackButton
@onready var info_scroll: ScrollContainer = %InfoPanel.get_node("InfoScroll")
@onready var list_scroll: ScrollContainer = %ClassListPanel.get_node("ListScroll")

var classes: Array[ClassData] = []
var selected: ClassData = null

var _cards: Array[ClassCard] = []
var _passive_name: Label            # built in code under "Starting Skill"
var _passive_desc: Label
var _dragging := false
var _swap_tween: Tween

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	back_button.pressed.connect(_on_back)
	create_button.pressed.connect(_on_create)
	name_input.text_submitted.connect(func(_t): _on_create())
	name_input.text_changed.connect(func(_t): error_label.text = "")
	preview_container.gui_input.connect(_on_preview_input)

	error_label.text = ""
	_polish_layout()
	_build_passive_section()
	_load_classes()
	_build_cards()
	if not _cards.is_empty():
		_cards[0].button_pressed = true       # selects the first class

# ---------- LOADING ----------
func _load_classes() -> void:
	for file in DirAccess.get_files_at(CLASS_DIR):
		# In exported builds, resources get remapped to .tres.remap
		var clean := file.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			var res := load(CLASS_DIR + clean)
			if res is ClassData:
				classes.append(res)
	classes.sort_custom(func(a: ClassData, b: ClassData) -> bool:
		if a.sort_order != b.sort_order:
			return a.sort_order < b.sort_order
		return a.display_name < b.display_name)

func _build_cards() -> void:
	var group := ButtonGroup.new()
	for i in classes.size():
		var card := CLASS_CARD_SCENE.instantiate() as ClassCard
		class_list.add_child(card)            # add first so @onready vars exist
		card.button_group = group
		card.setup(classes[i])
		card.toggled.connect(_on_card_toggled.bind(i))
		_cards.append(card)

# ---------- SELECTION ----------
func _on_card_toggled(pressed: bool, index: int) -> void:
	if pressed:
		_select(index)

func _select(index: int) -> void:
	selected = classes[index]
	var c := selected

	class_name_label.text = c.display_name
	class_name_label.add_theme_color_override("font_color", c.accent_color)
	tagline_label.text = c.tagline
	description_label.text = c.description
	skill_label.text = c.starting_skill_gem.display_name if c.starting_skill_gem else "None"

	_show_passive(c)
	_build_attributes(c)
	info_scroll.scroll_vertical = 0               # each class's details start from the top
	_update_fades.call_deferred()
	_show_model(c)
	_play_swap_animation()
	error_label.text = ""

## "Passive" title, trait name and description, added below the starting skill in the same
## style as the other headings, so nothing has to be placed in the scene.
func _build_passive_section() -> void:
	var box := skill_label.get_parent()
	for heading in [box.get_node("AttrTitle"), box.get_node("SkillTitle")]:
		_add_gap_before(heading)
	_add_gap(box)
	var title := Label.new()
	title.text = "Passive"
	title.add_theme_color_override("font_color", Color(0, 0.8980392, 1, 0.7019608))
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	_passive_name = Label.new()
	_passive_name.add_theme_font_size_override("font_size", 26)
	box.add_child(_passive_name)
	_passive_desc = Label.new()
	_passive_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_passive_desc.custom_minimum_size.x = 100.0       # lets it wrap inside the panel
	_passive_desc.add_theme_font_size_override("font_size", 20)
	_passive_desc.add_theme_color_override("font_color", Color(0.85, 0.96, 1.0, 0.85))
	box.add_child(_passive_desc)


## Space above a section heading, so the sections don't run into each other.
const SECTION_GAP := 14.0

func _add_gap(box: Node) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = SECTION_GAP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(gap)
	return gap


func _add_gap_before(heading: Node) -> void:
	var box := heading.get_parent()
	box.move_child(_add_gap(box), heading.get_index())


# ---------- LAYOUT POLISH ----------
const ACCENT := Color("#00E5FF")
const PANEL_INSET := 6          # keeps scrolled content and scrollbars inside the panel border

var _fades: Dictionary = {}     # ScrollContainer -> its bottom fade


## Panels get an inner margin, both scroll areas a thin cyan scrollbar and a fade at the bottom
## while there is more to scroll to; the Create button loses the theme's outward expand margin
## so it lines up with the panels above it.
func _polish_layout() -> void:
	for sc: ScrollContainer in [list_scroll, info_scroll]:
		var panel := sc.get_parent() as PanelContainer
		var box := (panel.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		box.set_content_margin_all(PANEL_INSET)
		panel.add_theme_stylebox_override("panel", box)
		_style_scrollbar(sc.get_v_scroll_bar())
		sc.get_v_scroll_bar().value_changed.connect(func(_v): _update_fades())
		sc.get_v_scroll_bar().changed.connect(_update_fades)
		_fades[sc] = _add_fade(panel, box.bg_color)

	var sep := StyleBoxLine.new()
	sep.color = Color(ACCENT, 0.3)
	sep.thickness = 2
	var hsep := info_scroll.find_child("HSeparator", true, false) as Control
	if hsep != null:
		hsep.add_theme_stylebox_override("separator", sep)

	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var sb := create_button.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			var flat := sb.duplicate() as StyleBoxFlat
			flat.expand_margin_left = 0
			flat.expand_margin_right = 0
			flat.content_margin_left = 28
			flat.content_margin_right = 28
			create_button.add_theme_stylebox_override(state, flat)


## The same slim cyan scrollbar on both lists, whatever class is picked.
func _style_scrollbar(bar: ScrollBar) -> void:
	bar.custom_minimum_size = Vector2(6, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(ACCENT, 0.08)
	track.set_corner_radius_all(3)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	for entry in [["grabber", 0.45], ["grabber_highlight", 0.8], ["grabber_pressed", 1.0]]:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(ACCENT, entry[1])
		g.set_corner_radius_all(3)
		bar.add_theme_stylebox_override(entry[0], g)


## A gradient over the bottom of a panel, in the panel's own colour: "there's more below".
func _add_fade(panel: PanelContainer, bg: Color) -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(bg, 0.0), Color(bg, 1.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	var fade := TextureRect.new()
	fade.texture = tex
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.size_flags_vertical = Control.SIZE_SHRINK_END     # the panel puts it at the bottom
	fade.custom_minimum_size = Vector2(0, 56)
	fade.visible = false
	panel.add_child(fade)
	return fade


func _update_fades() -> void:
	for sc: ScrollContainer in _fades:
		var bar := sc.get_v_scroll_bar()
		var more := bar.max_value - bar.page - bar.value > 2.0
		var fade := _fades[sc] as Control
		fade.visible = more


func _show_passive(c: ClassData) -> void:
	var t := c.get_trait()
	_passive_name.text = t.display_name if t else "None"
	_passive_name.add_theme_color_override("font_color", c.accent_color)
	_passive_desc.text = t.description if t else ""
	_passive_desc.visible = t != null and t.description != ""


func _build_attributes(c: ClassData) -> void:
	for child in attribute_list.get_children():
		attribute_list.remove_child(child)
		child.queue_free()
		
	var fill := StyleBoxFlat.new()
	fill.bg_color = c.accent_color
	fill.set_corner_radius_all(4)
	
	# One grid gives three aligned columns: name | bar | value
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	attribute_list.add_child(grid)
	
	var tween := create_tween().set_parallel(true)
	var attrs: Dictionary = c.get_attributes()
	for key in attrs:
		var name_l := Label.new()
		name_l.text = str(key).capitalize()
		name_l.add_theme_font_size_override("font_size", 24)
		
		var bar := ProgressBar.new()
		bar.max_value = ATTR_MAX
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("fill", fill)
		
		var value_l := Label.new()
		value_l.add_theme_font_size_override("font_size", 26)
		value_l.text = str(attrs[key])
		value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		
		grid.add_child(name_l)
		grid.add_child(bar)
		grid.add_child(value_l)
		
		bar.value = 0.0
		tween.tween_property(bar, "value", float(attrs[key]), 0.4)

func _show_model(c: ClassData) -> void:
	for child in model_pivot.get_children():
		child.queue_free()
	model_pivot.rotation = Vector3.ZERO
	if c.model_scene == null:
		return

	var model := c.model_scene.instantiate()
	model_pivot.add_child(model)
	if model is Node3D:
		model.scale = Vector3.ONE * c.model_scale
		model.position = c.model_offset

	# Stand in the idle pose, looping. Class models carry the shared player_anims library,
	# where it is "player_anims/Idle" (see model.gd); a model of its own may call it "idle".
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var ap := players[0] as AnimationPlayer
		var idle := _idle_clip(ap)
		if idle != "":
			ap.get_animation(idle).loop_mode = Animation.LOOP_LINEAR    # model.gd loops it too
			ap.play(idle)

	# Small pop-in (scales the pivot, so it doesn't fight model_scale)
	model_pivot.scale = Vector3.ONE * 0.85
	create_tween().tween_property(model_pivot, "scale", Vector3.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The model's idle clip: "player_anims/Idle", "idle", or any clip named like an idle.
static func _idle_clip(ap: AnimationPlayer) -> String:
	for clip in ["player_anims/Idle", "idle", "Idle"]:
		if ap.has_animation(clip):
			return clip
	for clip in ap.get_animation_list():
		if String(clip).get_file().to_lower().begins_with("idle"):
			return clip
	return ""


func _play_swap_animation() -> void:
	if _swap_tween:
		_swap_tween.kill()
	info_panel.modulate.a = 0.0
	_swap_tween = create_tween()
	_swap_tween.tween_property(info_panel, "modulate:a", 1.0, 0.25)

# ---------- PREVIEW: DRAG TO ROTATE ----------
func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		model_pivot.rotate_y(event.relative.x * 0.01)

# ---------- CREATE ----------
func _on_create() -> void:
	var char_name := name_input.text.strip_edges()
	var problem := _validate(char_name)
	if problem != "":
		error_label.text = problem
		return

	if SaveManager.create_character(SaveManager.creating_slot, char_name, selected):
		# creating_slot stays set so Character Select scrolls to the new card
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
	else:
		error_label.text = "Could not save. Try again."

func _validate(char_name: String) -> String:
	if selected == null:
		return "Pick a class first."
	if SaveManager.creating_slot < 0:
		return "No slot chosen. Open this screen from Character Select."
	if SaveManager.slot_exists(SaveManager.creating_slot):
		return "That slot is already in use."
	if char_name.length() < 3:
		return "Name must be at least 3 characters."

	var rx := RegEx.new()
	rx.compile("^[A-Za-z0-9_ ]+$")
	if rx.search(char_name) == null:
		return "Use letters, numbers, spaces and underscores only."

	for i in SaveManager.MAX_SLOTS:
		var existing := str(SaveManager.load_slot(i).get("name", ""))
		if existing.to_lower() == char_name.to_lower():
			return "You already have a character with that name."
	return ""

func _on_back() -> void:
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
