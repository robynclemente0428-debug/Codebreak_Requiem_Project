class_name CircuitBackgroundx
extends Control

@export var color := Color(0.1, 0.9, 1.0)
@export_range(0.0, 1.0) var opacity := 0.3     # overall fade, lower = more subtle
@export var trace_count := 45
@export var line_width := 1.5
@export var grid := 40.0                        # traces snap to this grid for a clean PCB look
@export var seed_value := 0                     # 0 = random each run
@export var breathe := true                     # slow pulse

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

func _process(_delta: float) -> void:
	if breathe:
		self_modulate.a = 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.0012)

func generate() -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_traces.clear()
	_dots.clear()
	if size.x < grid or size.y < grid:
		return
	var cols := int(size.x / grid)
	var rows := int(size.y / grid)
	for i in trace_count:
		_make_trace(cols, rows)
	queue_redraw()
	for c in get_children():
		if c is CircuitPulses:
			c.set_traces(_traces)
func _make_trace(cols: int, rows: int) -> void:
	var p := Vector2(_rng.randi_range(0, cols), _rng.randi_range(0, rows)) * grid
	var along := Vector2.RIGHT if _rng.randf() < 0.5 else Vector2.DOWN
	if _rng.randf() < 0.5:
		along = -along
	var side := Vector2(-along.y, along.x)      # perpendicular direction
	var bounds := Rect2(Vector2.ZERO, size)
	var pts := PackedVector2Array([p])

	for _i in _rng.randi_range(3, 7):
		# straight run
		var q := p + along * grid * _rng.randi_range(1, 5)
		if not bounds.has_point(q):
			break
		pts.append(q)
		p = q
		# optional 45° jog (equal run and rise)
		if _rng.randf() < 0.7:
			var s := side * (1.0 if _rng.randf() < 0.5 else -1.0)
			q = p + (along + s) * grid * _rng.randi_range(1, 2)
			if not bounds.has_point(q):
				break
			pts.append(q)
			p = q

	if pts.size() < 2:
		return
	_traces.append(pts)
	_dots.append(pts[pts.size() - 1])
	if _rng.randf() < 0.5:
		_dots.append(pts[0])

func _draw() -> void:
	# [width multiplier, alpha], widest/faintest first
	var passes := [[5.0, 0.15], [2.5, 0.35], [1.0, 1.0]]
	for p in passes:
		var c := Color(color, p[1] * opacity)
		for t in _traces:
			draw_polyline(t, c, line_width * p[0], true)
	for d in _dots:
		draw_circle(d, line_width * 3.0, Color(color, 0.25 * opacity))
		draw_circle(d, line_width * 1.5, Color(color, opacity))
