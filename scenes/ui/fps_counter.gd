class_name FpsCounter
extends CanvasLayer
## Frames per second in the top-left corner, over everything (menus included). Settings adds
## one at start-up; it shows while Settings > DISPLAY > SHOW FPS is on.
## Refreshes a few times a second, so the number is readable instead of flickering.

const REFRESH := 0.25                # seconds between updates
const FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_GOOD := Color(0.45, 1.0, 0.6)
const COL_OK := Color(1.0, 0.85, 0.35)
const COL_BAD := Color(1.0, 0.35, 0.4)

var shown := false:
	set(v):
		shown = v
		visible = v
var _label: Label
var _wait := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FONT):
		_label.add_theme_font_override("font", load(FONT))
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	Settings.bind_to(self, &"shown", "display", "show_fps")


func _process(delta: float) -> void:
	if not shown:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = REFRESH
	var fps := Engine.get_frames_per_second()
	_label.text = "%d FPS" % fps
	_label.add_theme_color_override("font_color",
		COL_GOOD if fps >= 55 else COL_OK if fps >= 30 else COL_BAD)
