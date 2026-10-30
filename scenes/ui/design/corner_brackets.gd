extends Control

@export var color := Color("#00E5FF")
@export var arm_length := 100.0
@export var thickness := 4.0
@export var gap := 10.0:
	set(v):
		gap = v
		queue_redraw()
@export var glow_strength := 1.0:
	set(v):
		glow_strength = v
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	resized.connect(queue_redraw)

func _draw() -> void:
	var o := gap + thickness * 0.5
	var a := arm_length
	var l := -o
	var t := -o
	var r := size.x + o
	var b := size.y + o

	var tl := PackedVector2Array([Vector2(l, t + a), Vector2(l, t), Vector2(l + a, t)])
	var br := PackedVector2Array([Vector2(r - a, b), Vector2(r, b), Vector2(r, b - a)])

	# [width multiplier, alpha], widest/faintest first
	var passes := [[5.0, 0.04], [3.0, 0.08], [1.8, 0.2], [1.0, 1.0]]
	for p in passes:
		var c := Color(color, p[1] * (glow_strength if p[1] < 1.0 else 1.0))
		draw_polyline(tl, c, thickness * p[0], true)
		draw_polyline(br, c, thickness * p[0], true)
