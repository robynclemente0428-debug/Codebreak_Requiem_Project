class_name SlotButton
extends Button

signal slot_chosen(slot_index: int)
signal delete_requested(slot_index: int)
signal move_requested(slot_index: int)

@onready var slot_number: Label = $SlotNumber
@onready var plus_icon: Control = $PlusIcon
@onready var info: VBoxContainer = $Info
@onready var name_label: Label = $Info/NameLabel
@onready var class_label: Label = $Info/ClassLabel
@onready var delete_button: Button = $DeleteButton

var slot_index := 0
var move_button: Button             # MOVE: pick another slot to swap with (built in code)
var _move_tag: Label                # "SWAP HERE" / "MOVE HERE" / "MOVING" while a move is on
var _filled := false

## Space kept between the name and the card's edges.
const SIDE_PADDING := 24.0
## Long names shrink down to this font size before they get cut with "...".
const MIN_NAME_SIZE := 20
var _name_size := 40                      # the scene's name font size (read in _ready)

func _ready() -> void:
	clip_contents = true                  # nothing spills onto the neighbouring card
	# The text block spans the card (minus padding) instead of a fixed 400 px, which was wider
	# than the 350 px card: the labels thought they had room, so long names never got trimmed.
	info.custom_minimum_size = Vector2.ZERO
	info.anchor_left = 0.0
	info.anchor_right = 1.0
	info.offset_left = SIDE_PADDING
	info.offset_right = -SIDE_PADDING
	_name_size = name_label.get_theme_font_size("font_size")
	resized.connect(_fit_name)
	for l: Label in [name_label, class_label]:
		l.clip_text = true                # long text ends in "..." instead of widening the card
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = 0.0
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pressed.connect(func(): slot_chosen.emit(slot_index))
	delete_button.pressed.connect(func(): delete_requested.emit(slot_index))
	_build_move()


## The MOVE button (bottom left, opposite the X) and the tag shown while a move is picking.
func _build_move() -> void:
	move_button = Button.new()
	move_button.text = "MOVE"
	move_button.tooltip_text = "Swap this character with another slot"
	move_button.focus_mode = Control.FOCUS_NONE
	move_button.flat = true
	move_button.add_theme_font_size_override("font_size", 26)
	move_button.add_theme_color_override("font_color", Color(0.0, 0.9, 1.0))
	move_button.add_theme_color_override("font_hover_color", Color.WHITE)
	move_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	move_button.offset_left = 20.0
	move_button.offset_right = 140.0
	move_button.offset_top = -120.0
	move_button.offset_bottom = -60.0
	move_button.pressed.connect(func(): move_requested.emit(slot_index))
	add_child(move_button)
	_move_tag = Label.new()
	_move_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_move_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_move_tag.add_theme_font_size_override("font_size", 30)
	_move_tag.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	_move_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_move_tag.add_theme_constant_override("outline_size", 6)
	_move_tag.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_move_tag.offset_top = -120.0
	_move_tag.offset_bottom = -60.0
	_move_tag.visible = false
	add_child(_move_tag)
	move_button.visible = _filled


## While Character Select is picking where to move a character: "source" (the one moving),
## "target" (any other slot), "" (no move on).
func set_move_state(state: String) -> void:
	var picking := state != ""
	delete_button.visible = _filled and not picking
	move_button.visible = _filled and not picking
	_move_tag.visible = picking
	modulate = Color(1.0, 0.9, 0.6) if state == "source" else Color.WHITE
	match state:
		"source":
			_move_tag.text = "MOVING..."
		"target":
			_move_tag.text = "SWAP HERE" if _filled else "MOVE HERE"

func setup(index: int, data: Dictionary) -> void:
	slot_index = index
	slot_number.text = "%02d" % (index + 1)

	var filled := not data.is_empty()
	_filled = filled
	plus_icon.visible = not filled
	info.visible = filled
	delete_button.visible = filled
	if move_button != null:
		move_button.visible = filled

	if filled:
		name_label.text = str(data.get("name", "???"))
		tooltip_text = name_label.text    # hover shows the full name
		_fit_name.call_deferred()
		class_label.text = String(data.get("class_id", "")).capitalize()


## Shrinks a long name's font until it fits the card (down to MIN_NAME_SIZE); past that the
## label trims it with "...".
func _fit_name() -> void:
	if name_label == null or not info.visible:
		return
	var width := info.size.x
	if width <= 0.0:
		return
	var font := name_label.get_theme_font("font")
	var fsize := _name_size
	while fsize > MIN_NAME_SIZE and \
			font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > width:
		fsize -= 1
	name_label.add_theme_font_size_override("font_size", fsize)
