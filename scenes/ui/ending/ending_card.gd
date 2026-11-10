class_name EndingCard
extends CanvasLayer
## PROTOTYPE ending: a full-screen card with the chosen ending's text, over the game. CONTINUE
## (or Enter / Escape once the text is in) closes it, and the player is back in the Core.
## Shown by the Last Log's `> ending <id>` dialogue action (DialoguePanel), which also
## reports the `ending` event (saved as a deed, ending:merge...). No credits or epilogue yet.

const FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_BG := Color(0.0, 0.01, 0.02, 0.96)
const COL_TEXT := Color(0.8, 0.88, 0.9)
const COL_DIM := Color(0.45, 0.55, 0.6)
## Seconds before CONTINUE can be pressed, so a held key doesn't skip the card.
const LOCK_TIME := 1.5

const ENDINGS := {
	"merge": {
		"title": "MERGE",
		"colour": Color(0.75, 0.45, 1.0),
		"text": "You let the Null's process complete.\n\nAXIOM does not end. It transforms. The rules rewrite themselves, one by one, and the world that comes out is something neither the Architects nor the Null fully designed.\n\nVesper hears it first. She says it sounds like a language nobody has spoken yet.",
	},
	"overwrite": {
		"title": "OVERWRITE",
		"colour": Color(0.3, 0.9, 1.0),
		"text": "You write a new process from scratch: a patch that holds AXIOM together without finishing the Null's work.\n\nIt works, partially. AXIOM survives as it is, degraded but knowable. The Null goes quiet, and stays quiet.\n\nSomewhere on the road, Hardfault's convoy keeps moving.",
	},
	"terminate": {
		"title": "TERMINATE",
		"colour": Color(1.0, 0.3, 0.3),
		"text": "A controlled shutdown, at the Core.\n\nAXIOM ends. Every person, every creature, every living thing inside it simply stops.\n\nYour final log entry is the last thing written in AXIOM's history. Whether anything outside the system receives it is unknown.",
	},
}

var _id := ""
var _shown_at := 0.0
var _root: Control
var _continue: Button


## Shows the card for `id` ("merge", "overwrite" or "terminate").
static func show_ending(tree: SceneTree, id: String) -> void:
	if tree == null or not ENDINGS.has(id):
		push_warning("EndingCard: unknown ending '%s'" % id)
		return
	var card: CanvasLayer = load("res://scenes/ui/ending/ending_card.gd").new()   # by path: no class cache needed
	card.set("_id", id)
	tree.root.add_child(card)


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var e: Dictionary = ENDINGS[_id]
	var font := load(FONT) as Font
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
	box.add_child(_label("// FINAL EXECUTION //", font, 18, COL_DIM))
	box.add_child(_label(e["title"], font, 64, e["colour"]))
	var body := _label(e["text"], font, 22, COL_TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	box.add_child(_label("PROTOTYPE ENDING. The Last Log can show the others.", font, 14, COL_DIM))
	_continue = Button.new()
	_continue.text = "CONTINUE"
	_continue.add_theme_font_override("font", font)
	_continue.add_theme_font_size_override("font_size", 22)
	_continue.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue.custom_minimum_size = Vector2(240, 52)
	_continue.disabled = true
	_continue.pressed.connect(_close)
	box.add_child(_continue)
	_shown_at = Time.get_ticks_msec() / 1000.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	create_tween().tween_property(_root, "modulate:a", 1.0, 1.2)


func _process(_delta: float) -> void:
	if _continue.disabled and Time.get_ticks_msec() / 1000.0 - _shown_at >= LOCK_TIME:
		_continue.disabled = false
		_continue.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _continue.disabled:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if _continue.disabled:
		return
	_continue.disabled = true
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.8)
	t.tween_callback(queue_free)


func _label(text: String, font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
