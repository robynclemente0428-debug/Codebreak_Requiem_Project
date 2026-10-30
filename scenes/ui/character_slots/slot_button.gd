class_name SlotButton
extends Button

signal slot_chosen(slot_index: int)
signal delete_requested(slot_index: int)

@onready var slot_number: Label = $SlotNumber
@onready var plus_icon: Control = $PlusIcon
@onready var info: VBoxContainer = $Info
@onready var name_label: Label = $Info/NameLabel
@onready var class_label: Label = $Info/ClassLabel
@onready var delete_button: Button = $DeleteButton

var slot_index := 0

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

func setup(index: int, data: Dictionary) -> void:
	slot_index = index
	slot_number.text = "%02d" % (index + 1)

	var filled := not data.is_empty()
	plus_icon.visible = not filled
	info.visible = filled
	delete_button.visible = filled

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
