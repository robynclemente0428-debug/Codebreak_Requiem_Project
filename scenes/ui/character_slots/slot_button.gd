class_name SlotButton
extends Button
## One card on the Character Select screen. A filled card shows the class icon, name, class,
## where the character is and their credits/playtime, with small MOVE / DELETE actions at the
## bottom. An empty card shows a "+" and NEW CHARACTER. Every card uses the same states:
## normal (dark), hover (lighter + glow), focus/selected (bright outline).

signal slot_chosen(slot_index: int)
signal delete_requested(slot_index: int)
signal move_requested(slot_index: int)
## REBOOT (Reboot): a character who chose TERMINATE can start a new game plus.
signal reboot_requested(slot_index: int)

const ACCENT := Color("#00E5FF")
const CARD_BG := Color(0.035, 0.13, 0.17, 0.92)
const CARD_BG_EMPTY := Color(0.035, 0.13, 0.17, 0.55)
const CARD_BG_HOVER := Color(0.06, 0.22, 0.28, 0.96)
const CARD_BG_PRESSED := Color(0.08, 0.29, 0.36, 1.0)
const DANGER := Color(1.0, 0.35, 0.3)
const REBOOT_COL := Color(1.0, 0.78, 0.35)
const CORNER := 48

@onready var slot_number: Label = $SlotNumber
@onready var body: VBoxContainer = $Body
@onready var class_icon: TextureRect = $Body/ClassIcon
@onready var name_label: Label = $Body/NameLabel
@onready var class_label: Label = $Body/ClassLabel
@onready var accent_line: ColorRect = $Body/AccentLine
@onready var location_label: Label = $Body/LocationLabel
@onready var details: GridContainer = $Body/Details
@onready var plus_icon: Control = $Body/PlusIcon
@onready var empty_label: Label = $Body/EmptyLabel
@onready var actions: HBoxContainer = $Actions
@onready var move_button: Button = $Actions/MoveButton
@onready var delete_button: Button = $Actions/DeleteButton

var slot_index := 0
var _move_tag: Label                # "SWAP HERE" / "MOVE HERE" / "MOVING" while a move is on
var _filled := false
var _reboot_button: Button          # shown on TERMINATE characters only

## Long names shrink down to this font size before they get cut with "...".
const MIN_NAME_SIZE := 22
var _name_size := 40                      # the scene's name font size (read in _ready)


func _ready() -> void:
	clip_contents = true                  # nothing spills onto the neighbouring card
	_name_size = name_label.get_theme_font_size("font_size")
	resized.connect(_fit_name)
	pressed.connect(func(): slot_chosen.emit(slot_index))
	move_button.pressed.connect(func(): move_requested.emit(slot_index))
	delete_button.pressed.connect(func(): delete_requested.emit(slot_index))
	_style_action(move_button, ACCENT)
	_style_action(delete_button, DANGER)
	_reboot_button = Button.new()
	_reboot_button.text = "REBOOT"
	_reboot_button.tooltip_text = "New game plus: this character starts over from Act I, keeping its rank, scripts and routines"
	_reboot_button.focus_mode = Control.FOCUS_NONE
	_reboot_button.custom_minimum_size = Vector2(0, 44)
	_reboot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reboot_button.visible = false
	_reboot_button.pressed.connect(func(): reboot_requested.emit(slot_index))
	actions.add_child(_reboot_button)
	actions.move_child(_reboot_button, 0)
	_style_action(_reboot_button, REBOOT_COL)
	_build_move_tag()
	_apply_card_style()


# ---------- LOOK ----------
func _card_box(bg: Color, border: Color, width: int, glow: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.corner_radius_top_right = CORNER
	sb.corner_radius_bottom_left = CORNER
	sb.anti_aliasing = true
	if glow > 0.0:
		sb.shadow_color = Color(ACCENT, glow)
		sb.shadow_size = 12
	return sb


## Same shapes for filled and empty cards; an empty one is just dimmer until hovered.
func _apply_card_style() -> void:
	var bg := CARD_BG if _filled else CARD_BG_EMPTY
	var edge := Color(ACCENT, 0.55 if _filled else 0.3)
	add_theme_stylebox_override("normal", _card_box(bg, edge, 2, 0.0))
	add_theme_stylebox_override("disabled", _card_box(bg, edge, 2, 0.0))
	add_theme_stylebox_override("hover", _card_box(CARD_BG_HOVER, ACCENT, 2, 0.35))
	add_theme_stylebox_override("pressed", _card_box(CARD_BG_PRESSED, ACCENT, 2, 0.45))
	add_theme_stylebox_override("hover_pressed", _card_box(CARD_BG_PRESSED, ACCENT, 2, 0.45))
	# Focus (the selected card) is drawn over the state above: a bright outline and glow only.
	var focus := _card_box(Color.TRANSPARENT, ACCENT, 3, 0.5)
	focus.draw_center = false
	focus.shadow_size = 16
	add_theme_stylebox_override("focus", focus)
	plus_icon.set("color", Color(ACCENT, 0.75))
	plus_icon.queue_redraw()


## MOVE / DELETE: small outlined buttons, quiet until hovered.
func _style_action(b: Button, tint: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.07, 0.1, 0.6)
	normal.border_color = Color(tint, 0.45)
	normal.set_border_width_all(1)
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(tint, 0.18)
	hover.border_color = tint
	var down := hover.duplicate() as StyleBoxFlat
	down.bg_color = Color(tint, 0.32)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("hover_pressed", down)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(tint, 0.85))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)


## The tag shown in place of the actions while a move is picking its target.
func _build_move_tag() -> void:
	_move_tag = Label.new()
	_move_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_move_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_move_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_move_tag.add_theme_font_size_override("font_size", 26)
	_move_tag.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	_move_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_move_tag.add_theme_constant_override("outline_size", 6)
	_move_tag.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_move_tag.offset_top = -76.0
	_move_tag.offset_bottom = -20.0
	_move_tag.visible = false
	add_child(_move_tag)


## While Character Select is picking where to move a character: "source" (the one moving),
## "target" (any other slot), "" (no move on).
func set_move_state(state: String) -> void:
	var picking := state != ""
	actions.visible = _filled and not picking
	_move_tag.visible = picking
	modulate = Color(1.0, 0.9, 0.6) if state == "source" else Color.WHITE
	match state:
		"source":
			_move_tag.text = "MOVING..."
		"target":
			_move_tag.text = "SWAP HERE" if _filled else "MOVE HERE"


# ---------- CONTENT ----------
func setup(index: int, data: Dictionary) -> void:
	slot_index = index
	slot_number.text = "%02d" % (index + 1)

	_filled = not data.is_empty()
	for n: Control in [class_icon, name_label, class_label, accent_line, location_label, details, actions]:
		n.visible = _filled
	plus_icon.visible = not _filled
	empty_label.visible = not _filled
	tooltip_text = ""
	_apply_card_style()
	if not _filled:
		return

	name_label.text = str(data.get("name", "???"))
	tooltip_text = name_label.text    # hover shows the full name
	_fit_name.call_deferred()

	var class_id := String(data.get("class_id", ""))
	var cd := _class_data(class_id)
	var accent := cd.accent_color if cd != null else ACCENT
	class_label.text = cd.display_name if cd != null else class_id.capitalize()
	class_label.add_theme_color_override("font_color", accent)
	accent_line.color = accent
	class_icon.texture = cd.get_icon() if cd != null else null
	class_icon.visible = class_icon.texture != null

	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	var wallet: Variant = data.get("currency")
	var credits := int(wallet.get("amount", 0)) if wallet is Dictionary else 0
	location_label.text = _location_text(str(data.get(SaveManager.LAST_TOWN_KEY, "")))
	location_label.tooltip_text = location_label.text
	_add_detail("CREDITS", _group_digits(credits))
	var runs := Reboot.count_of_save(data)
	if runs > 0:
		_add_detail("RUN", "REBOOT %d" % runs)
	if _reboot_button != null:
		_reboot_button.visible = Reboot.can_reboot(data)
	_add_detail("PLAYTIME", _playtime_text(int(data.get("playtime_seconds", 0))))
	var saved_at := int(data.get("saved_at", 0))
	if saved_at > 0:
		_add_detail("LAST PLAYED", _date_text(saved_at))

static func _date_text(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

func _add_detail(key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	k.add_theme_font_size_override("font_size", 18)
	k.add_theme_color_override("font_color", Color(ACCENT, 0.55))
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 20)
	v.add_theme_color_override("font_color", Color(0.85, 0.97, 1.0))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.clip_text = true
	v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.custom_minimum_size.x = 0.0
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(k)
	details.add_child(v)


static func _class_data(class_id: String) -> ClassData:
	var path := "res://data/classes/%s.tres" % class_id
	if class_id.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as ClassData


const _ROMAN: Array[String] = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

## "res://scenes/map/town/act_5_core.tscn" -> "Act V - Core". No town yet -> "Act I".
static func _location_text(town_path: String) -> String:
	if town_path.is_empty():
		return "Act I"
	var base := town_path.get_file().get_basename()
	var rx := RegEx.create_from_string("^act_(\\d+)_?(.*)$")
	var m := rx.search(base)
	if m == null:
		return base.capitalize()
	var n := int(m.get_string(1))
	var act := "Act " + (_ROMAN[n] if n < _ROMAN.size() else str(n))
	var place := m.get_string(2).capitalize()
	return act if place.is_empty() or place == "Town" else "%s - %s" % [act, place]


static func _playtime_text(seconds: int) -> String:
	if seconds <= 0:
		return "--"
	var h := int(seconds / 3600.0)
	var m := int((seconds % 3600) / 60.0)
	return "%dh %02dm" % [h, m] if h > 0 else "%dm" % maxi(m, 1)


static func _group_digits(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Shrinks a long name's font until it fits the card (down to MIN_NAME_SIZE); past that the
## label trims it with "...".
func _fit_name() -> void:
	if name_label == null or not name_label.visible:
		return
	var width := body.size.x
	if width <= 0.0:
		return
	var font := name_label.get_theme_font("font")
	var fsize := _name_size
	while fsize > MIN_NAME_SIZE and \
			font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > width:
		fsize -= 1
	name_label.add_theme_font_size_override("font_size", fsize)
