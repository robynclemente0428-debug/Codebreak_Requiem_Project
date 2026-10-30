class_name CircuitBorder
extends Control

@export var seed_value: int = 0            # 0 = random each run
@export var color: Color = Color(0.1, 0.9, 1.0)
@export var border_depth: float = 90.0     # how far traces reach inward
@export var traces_per_edge: int = 4
@export var line_width: float = 2.0

var _traces: Array[PackedVector2Array] = []
var _dots: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	resized.connect(generate)
	generate()

func generate() -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_traces.clear()
	_dots.clear()

	var w := size.x
	var h := size.y
	# [origin, along-direction, inward-normal, edge length]
	var edges := [
		[Vector2(0, 0),  Vector2(1, 0), Vector2(0, 1),  w],  # top
		[Vector2(0, h),  Vector2(1, 0), Vector2(0, -1), w],  # bottom
		[Vector2(0, 0),  Vector2(0, 1), Vector2(1, 0),  h],  # left
		[Vector2(w, 0),  Vector2(0, 1), Vector2(-1, 0), h],  # right
	]
	for e in edges:
		for i in traces_per_edge:
			_make_trace(e[0], e[1], e[2], e[3], i)
	queue_redraw()
	for c in get_children():
		if c is CircuitPulses:
			c.set_traces(_traces)

func _make_trace(origin: Vector2, along: Vector2, normal: Vector2, length: float, index: int) -> void:
	# each trace lives in a depth "lane" so they don't all overlap
	var lane_min := 6.0 + (border_depth / traces_per_edge) * index
	var lane_max := lane_min + border_depth / traces_per_edge
	var v := _rng.randf_range(lane_min, lane_max)

	var u := _rng.randf_range(0.0, length * 0.2)
	var u_end := _rng.randf_range(length * 0.6, length)
	var pts := PackedVector2Array()
	pts.append(origin + along * u + normal * v)

	while u < u_end:
		# straight run
		u += _rng.randf_range(40.0, 180.0)
		pts.append(origin + along * u + normal * v)
		# optional 45° jog toward/away from the edge
		if _rng.randf() < 0.6:
			var dv := _rng.randf_range(10.0, 35.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
			var new_v := clampf(v + dv, 4.0, border_depth)
			dv = new_v - v
			if absf(dv) > 1.0:
				u += absf(dv)          # equal run and rise = 45°
				v = new_v
				pts.append(origin + along * u + normal * v)

	_traces.append(pts)
	# node dot at one end (sometimes both)
	_dots.append(pts[pts.size() - 1])
	if _rng.randf() < 0.4:
		_dots.append(pts[0])

func _draw() -> void:
	# glow passes: [width multiplier, alpha]
	var passes := [[8.0, 0.04], [4.0, 0.10], [2.0, 0.30], [1.0, 1.0]]
	for p in passes:
		var c := Color(color, p[1])
		for t in _traces:
			draw_polyline(t, c, line_width * p[0], true)
	for d in _dots:
		draw_circle(d, line_width * 4.0, Color(color, 0.12))
		draw_circle(d, line_width * 2.0, color)
