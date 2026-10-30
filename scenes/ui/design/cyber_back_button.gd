@tool
class_name CyberBackButton
extends TextureButton

@export var color := Color("#00E5FF")
@export var label := "BACK"
@export var font: Font                       # leave empty to use the theme/fallback font
@export var font_size := 28
@export var chamfer := 16.0                  # cut size on the top-left and bottom-right corners
@export var line_width := 2.0

var _t := 0.0:                               # 0 = idle, 1 = hovered/focused
	set(v):
		_t = v
		queue_redraw()
var _tween: Tween

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(200, 60)

	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	focus_entered.connect(_set_hover.bind(true))
	focus_exited.connect(_set_hover.bind(false))
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	resized.connect(queue_redraw)

func _set_hover(on: bool) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_t", 1.0 if on else 0.0, 0.15)

func _draw() -> void:
	var pad := line_width * 2.0
	var s := size - Vector2(pad, pad) * 2.0
	var o := Vector2(pad, pad)
	var c := chamfer

	var outline := PackedVector2Array([
		o + Vector2(c, 0), o + Vector2(s.x, 0), o + Vector2(s.x, s.y - c),
		o + Vector2(s.x - c, s.y), o + Vector2(0, s.y), o + Vector2(0, c),
		o + Vector2(c, 0),                                   # closes the loop
	])

	var pressed_boost := 0.2 if button_pressed or is_pressed() else 0.0
	var energy := lerpf(0.65, 1.0, _t) + pressed_boost

	# translucent fill
	var fill := outline.duplicate()
	fill.remove_at(fill.size() - 1)
	draw_colored_polygon(fill, Color(color, lerpf(0.04, 0.18, _t) + pressed_boost * 0.5))

	# glow outline: wide/faint first, thin/bright last
	for p in [[6.0, 0.08], [3.0, 0.2], [1.0, 1.0]]:
		draw_polyline(outline, Color(color, p[1] * energy), line_width * p[0], true)

	# chevron that nudges left on hover
	var cy := size.y * 0.5
	var ax := pad + c + 6.0 - 6.0 * _t
	var chev := PackedVector2Array([
		Vector2(ax + 10, cy - 11), Vector2(ax, cy), Vector2(ax + 10, cy + 11)
	])
	for p in [[5.0, 0.12], [2.5, 0.3], [1.0, 1.0]]:
		draw_polyline(chev, Color(color, p[1] * energy), line_width * p[0], true)

	# label
	var f: Font = font if font else ThemeDB.fallback_font
	var text_x := ax + 28.0
	var baseline := cy + (f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
	var tc := color.lerp(Color.WHITE, 0.35 * _t)
	draw_string(f, Vector2(text_x, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(tc, energy))
