extends Node
## Autoload: DisplaySettings
## Makes the whole UI scale with the window, so every resolution looks like 1920x1080, just
## bigger or smaller. Godot's project settings say the same thing, but some ways of running the
## game (like the editor's embedded game window) can start with a different base size, which
## makes the UI too big. Setting it from code at startup keeps it right everywhere.
##
## Later, a settings menu can call set_ui_scale() for a "UI size" slider.

## The resolution the UI was designed for. Everything is laid out as if the screen were this
## size, then scaled to the real window.
const BASE_SIZE := Vector2i(1920, 1080)

## 1.0 = designed size. 1.25 makes all UI 25% bigger (still scaling with the window).
var ui_scale := 1.0


func _ready() -> void:
	_apply()
	get_tree().root.size_changed.connect(_apply)
	print("[Display] window %s, UI laid out at %s (scale %.2f)" % [
		get_tree().root.size, get_tree().root.get_visible_rect().size, ui_scale])


func set_ui_scale(value: float) -> void:
	ui_scale = clampf(value, 0.5, 2.0)
	_apply()


func _apply() -> void:
	var root := get_tree().root
	if root.content_scale_size != BASE_SIZE:
		root.content_scale_size = BASE_SIZE
	if root.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if root.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if not is_equal_approx(root.content_scale_factor, ui_scale):
		root.content_scale_factor = ui_scale
