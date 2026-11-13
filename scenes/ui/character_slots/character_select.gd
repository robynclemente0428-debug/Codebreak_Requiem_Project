extends Control

const CLASS_DIR := "res://data/classes/"
const SlotButtonScene := preload("res://scenes/ui/character_slots/slot_button.tscn")
# Adjust these two paths to wherever your scenes actually are
const CLASS_SELECT_SCENE := "res://scenes/ui/class_select/class_select.tscn"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var slots_box: HBoxContainer = %SlotsBox
@onready var scroll: ScrollContainer = %Scroll
@onready var back_button: TextureButton = %BackButton
@onready var delete_dialog: ConfirmationDialog = %DeleteDialog
@onready var padding: MarginContainer = %Scroll.get_node("Padding")
@onready var slots_panel: Control = %Scroll.get_parent()
@onready var range_label: Label = %RangeLabel
@onready var prev_button: Button = %PrevButton
@onready var next_button: Button = %NextButton
@onready var scroll_track: Control = %ScrollTrack

const ACCENT := Color("#00E5FF")
## A card is never narrower than this; as many whole cards as fit are shown, sized to fill the row.
const MIN_CARD_WIDTH := 340.0
const CARD_GAP := 28
const SIDE_PAD := 40.0

var _visible_count := 1             # whole cards that fit in the strip
var _step := 0.0                    # card width + gap: one scroll notch
var _first := 0                     # index of the leftmost visible card
var _scroll_tween: Tween

var _pending_delete := -1
var _moving := -1                   # slot whose MOVE was pressed: the next card clicked swaps with it


func _ready() -> void:
	CyberDialog.style(delete_dialog)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	back_button.pressed.connect(_on_back)
	delete_dialog.confirmed.connect(_confirm_delete)
	prev_button.pressed.connect(func(): _page(-1))
	next_button.pressed.connect(func(): _page(1))
	for b in [prev_button, next_button]:
		_style_arrow(b)
	scroll.resized.connect(_layout_cards)
	scroll.get_h_scroll_bar().value_changed.connect(func(_v): scroll_track.queue_redraw())
	scroll_track.draw.connect(_draw_track)
	scroll_track.gui_input.connect(_on_track_input)
	
	# Return to the slot you just created a character in (or slot 0)
	var focus_index := maxi(SaveManager.creating_slot, 0)
	SaveManager.creating_slot = -1      # consumed
	_build_slots()
	_focus_slot(focus_index)
	_prefetch_class_select()


func _build_slots() -> void:
	for child in slots_box.get_children():
		slots_box.remove_child(child)   # remove now so child indices stay correct
		child.queue_free()

	for i in SaveManager.MAX_SLOTS:
		var card := SlotButtonScene.instantiate()
		slots_box.add_child(card)
		card.setup(i, SaveManager.load_slot(i))
		card.slot_chosen.connect(_on_slot_chosen)
		card.delete_requested.connect(_on_delete_requested)
		card.move_requested.connect(_on_move_requested)
		card.focus_entered.connect(_reveal.bind(i))
	_layout_cards()


func _focus_slot(index: int) -> void:
	await get_tree().process_frame      # wait for the layout to settle
	if index < 0 or index >= slots_box.get_child_count():
		return
	var card := slots_box.get_child(index) as Control
	_reveal(index, false)
	card.grab_focus()


func _on_slot_chosen(index: int) -> void:
	if _moving >= 0:
		_finish_move(index)
		return
	if SaveManager.slot_exists(index):
		if SaveManager.add_to_party(index) and SaveManager.party_full():
			SaveManager.start_game()                    # existing character: play
	else:
		SaveManager.creating_slot = index                   #empty slot
		var packed := ResourceLoader.load_threaded_get(CLASS_SELECT_SCENE) as PackedScene
		get_tree().change_scene_to_packed(packed)


func _on_delete_requested(index: int) -> void:
	_pending_delete = index
	var data := SaveManager.load_slot(index)
	delete_dialog.dialog_text = "Delete %s permanently?" % data.get("name", "this character")
	delete_dialog.popup_centered()


func _confirm_delete() -> void:
	SaveManager.delete_slot(_pending_delete)
	_build_slots()                                  # keeps _first, so the strip stays put
	_focus_slot(_pending_delete)

# ---------- MOVE ----------
## MOVE on a card: every other card shows SWAP HERE / MOVE HERE; the next card clicked takes
## this character (and the one there, if any, takes its place). The same card, Esc or BACK cancels.
func _on_move_requested(index: int) -> void:
	if index in SaveManager.party:
		return                                  # already seated: it can't move now
	_moving = index
	_show_move_state()


func _finish_move(target: int) -> void:
	var from := _moving
	_moving = -1
	if target != from and not SaveManager.swap_slots(from, target):
		push_warning("Could not move slot %d to %d" % [from, target])
	_build_slots()
	_focus_slot(target)


func _cancel_move() -> void:
	_moving = -1
	_show_move_state()


func _show_move_state() -> void:
	for card in slots_box.get_children():
		var c := card as SlotButton
		if c != null:
			c.set_move_state("" if _moving < 0 else ("source" if c.slot_index == _moving else "target"))


# ---------- STRIP: whole cards only ----------
## Sizes the cards so a whole number of them fills the strip exactly, then snaps the scroll to a
## card edge. Runs on every resize, so no card is ever half-cut at rest.
func _layout_cards() -> void:
	var count := slots_box.get_child_count()
	var width := scroll.size.x
	if count == 0 or width <= 0.0:
		return
	var inner := width - SIDE_PAD * 2.0
	_visible_count = clampi(int((inner + CARD_GAP) / (MIN_CARD_WIDTH + CARD_GAP)), 1, count)
	var card_w := floorf((inner - CARD_GAP * (_visible_count - 1)) / _visible_count)
	# Whatever rounding leaves over goes into the side padding, split evenly.
	var spare := width - card_w * _visible_count - CARD_GAP * (_visible_count - 1)
	padding.add_theme_constant_override("margin_left", int(floorf(spare / 2.0)))
	padding.add_theme_constant_override("margin_right", int(ceilf(spare / 2.0)))
	slots_box.add_theme_constant_override("separation", CARD_GAP)
	for card: Control in slots_box.get_children():
		card.custom_minimum_size.x = card_w
	_step = card_w + CARD_GAP
	_scroll_to(_first, false)


func _max_first() -> int:
	return maxi(slots_box.get_child_count() - _visible_count, 0)


func _page(dir: int) -> void:
	_scroll_to(_first + dir, true)


## Scrolls just enough to show card `index` (used when focus moves with keys or a pad).
func _reveal(index: int, animate := true) -> void:
	if index < _first:
		_scroll_to(index, animate)
	elif index >= _first + _visible_count:
		_scroll_to(index - _visible_count + 1, animate)


func _scroll_to(first: int, animate: bool) -> void:
	_first = clampi(first, 0, _max_first())
	var target := _first * _step
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	if animate and is_inside_tree():
		_scroll_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_scroll_tween.tween_method(func(v: float): scroll.scroll_horizontal = roundi(v),
				float(scroll.scroll_horizontal), target, 0.25)
	else:
		# The content may not have grown to its new width yet this frame; set it again after.
		scroll.scroll_horizontal = roundi(target)
		_set_scroll_late.call_deferred(roundi(target))
	_update_strip_ui()


func _set_scroll_late(px: int) -> void:
	if not (_scroll_tween and _scroll_tween.is_valid()):
		scroll.scroll_horizontal = px


func _update_strip_ui() -> void:
	var count := slots_box.get_child_count()
	var last := mini(_first + _visible_count, count)
	range_label.text = "%02d-%02d / %d" % [_first + 1, last, count]
	prev_button.disabled = _first <= 0
	next_button.disabled = _first >= _max_first()
	var paging := _max_first() > 0
	for c: Control in [range_label, prev_button, next_button, scroll_track]:
		c.visible = paging
	scroll_track.queue_redraw()


## A thin cyan track under the strip; the bright part is the visible window.
func _draw_track() -> void:
	var w := scroll_track.size.x
	var h := scroll_track.size.y
	var count := slots_box.get_child_count()
	if count == 0 or w <= 0.0:
		return
	scroll_track.draw_rect(Rect2(0, h * 0.25, w, h * 0.5), Color(ACCENT, 0.15))
	var thumb_w := w * float(_visible_count) / count
	var max_px := scroll.get_h_scroll_bar().max_value - scroll.size.x
	var t := clampf(scroll.scroll_horizontal / max_px, 0.0, 1.0) if max_px > 0.0 else 0.0
	scroll_track.draw_rect(Rect2((w - thumb_w) * t, 0, thumb_w, h), ACCENT)


## Clicking the track jumps there.
func _on_track_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var t := clampf(mb.position.x / scroll_track.size.x, 0.0, 1.0)
		_scroll_to(roundi(t * _max_first()), true)


func _style_arrow(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.07, 0.1, 0.7)
	normal.border_color = Color(ACCENT, 0.6)
	normal.set_border_width_all(2)
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.18)
	hover.border_color = ACCENT
	var down := hover.duplicate() as StyleBoxFlat
	down.bg_color = Color(ACCENT, 0.32)
	var off := normal.duplicate() as StyleBoxFlat
	off.border_color = Color(ACCENT, 0.2)
	off.bg_color = Color(0.02, 0.07, 0.1, 0.4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_disabled_color", Color(ACCENT, 0.25))


## The mouse wheel over the strip moves one card at a time (instead of free pixel scrolling).
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or delete_dialog.visible:
		return
	if not slots_panel.get_global_rect().has_point(slots_panel.get_global_mouse_position()):
		return
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
			_page(-1)
		MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
			_page(1)
		_:
			return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _moving >= 0 and event.is_action_pressed("ui_cancel"):
		_cancel_move()
		get_viewport().set_input_as_handled()


func _on_back() -> void:
	if _moving >= 0:
		_cancel_move()                          # BACK first just cancels a move
		return
	SaveManager.end_session()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _prefetch_class_select() -> void:
	# Loads on background threads; nothing blocks
	ResourceLoader.load_threaded_request(CLASS_SELECT_SCENE, "", true)
	for file in DirAccess.get_files_at(CLASS_DIR):
		var clean := file.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			ResourceLoader.load_threaded_request(CLASS_DIR + clean, "", true)
