class_name EndingCard
extends CanvasLayer
## The ending: a full-screen sequence of epilogue pages over the game (Endings.pages), one at a
## time. CONTINUE (or Enter / Escape once a page is in) turns to the next; after the last the
## player is back in the Core, which now shows that ending (Endings, CoreEnding).
## Shown by the Last Log's `> ending <id>` dialogue action (DialoguePanel), which also records
## the choice (Endings.choose: the `ending` deed, and ending_now).

const FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_BG := Color(0.0, 0.01, 0.02, 0.96)
const COL_TEXT := Color(0.8, 0.88, 0.9)
const COL_DIM := Color(0.45, 0.55, 0.6)
## Seconds before CONTINUE can be pressed on a page, so a held key doesn't skip it.
const LOCK_TIME := 1.2                  # (each page)

var _id := ""
var _pages: Array = []
var _page := 0
var _shown_at := 0.0
var _root: Control
var _title: Label
var _body: Label
var _count: Label
var _continue: Button
var _font: Font


## Shows the epilogue for `id` ("merge", "overwrite" or "terminate").
static func show_ending(tree: SceneTree, id: String) -> void:
	if tree == null or not id in Endings.IDS:
		push_warning("EndingCard: unknown ending '%s'" % id)
		return
	var player := tree.get_first_node_in_group("players")
	var qm: QuestManager = player.get("quests") if player != null else null
	var card: CanvasLayer = load("res://scenes/ui/ending/ending_card.gd").new()   # by path: no class cache needed
	card.set("_id", id)
	card.set("_pages", Endings.pages(qm, player, id))
	tree.root.add_child(card)


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load(FONT) as Font
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP     # nothing behind the card takes clicks
	_root.modulate.a = 0.0
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 820.0
	box.add_theme_constant_override("separation", 22)
	centre.add_child(box)
	box.add_child(_label("// FINAL EXECUTION //", 18, COL_DIM))
	_title = _label("", 56, COL_TEXT)
	box.add_child(_title)
	_body = _label("", 21, COL_TEXT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 820.0
	box.add_child(_body)
	_count = _label("", 14, COL_DIM)
	box.add_child(_count)
	_continue = Button.new()
	_continue.add_theme_font_override("font", _font)
	_continue.add_theme_font_size_override("font_size", 22)
	_continue.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue.custom_minimum_size = Vector2(240, 52)
	_continue.pressed.connect(_next)
	box.add_child(_continue)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_page(0)
	create_tween().tween_property(_root, "modulate:a", 1.0, 1.2)


func _show_page(i: int) -> void:
	_page = i
	var p: Dictionary = _pages[i]
	_title.text = str(p["title"])
	_title.visible = _title.text != ""
	_title.add_theme_color_override("font_color", p["colour"])
	_body.text = str(p["text"])
	# The final log reads as a log: left-aligned lines
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _body.text.begins_with(">") else HORIZONTAL_ALIGNMENT_CENTER
	_count.text = "%d / %d" % [i + 1, _pages.size()]
	_continue.text = "CONTINUE" if i < _pages.size() - 1 else "BACK TO THE CORE"
	_continue.disabled = true
	_shown_at = Time.get_ticks_msec() / 1000.0
	_body.modulate.a = 0.0
	create_tween().tween_property(_body, "modulate:a", 1.0, 0.6)


func _process(_delta: float) -> void:
	if _continue.disabled and _page >= 0 and Time.get_ticks_msec() / 1000.0 - _shown_at >= LOCK_TIME:
		_continue.disabled = false
		_continue.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _continue.disabled:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_next()


## The next page, or (after the last) back to the game.
func _next() -> void:
	if _continue.disabled:
		return
	if _page < _pages.size() - 1:
		_show_page(_page + 1)
		return
	_continue.disabled = true
	_page = -1
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.8)
	t.tween_callback(queue_free)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
