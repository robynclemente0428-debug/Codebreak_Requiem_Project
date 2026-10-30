class_name CircuitPulses
extends Control

@export var color := Color(0.4, 1.0, 1.0)
@export var core_color := Color(0.85, 1.0, 1.0)   # bright head of the pulse
@export var speed := 450.0                        # px per second
@export_range(0.0, 0.9) var speed_variance := 0.3
@export var tail_length := 140.0
@export var width := 2.0
@export var interval_min := 0.6                   # seconds between spawns
@export var interval_max := 2.5
@export var max_pulses := 4
@export_range(0.0, 1.0) var intensity := 1.0

class Pulse:
	var pts: PackedVector2Array
	var cum: PackedFloat32Array
	var total := 0.0
	var dist := 0.0
	var speed := 0.0

var _paths: Array[Dictionary] = []
var _pulses: Array[Pulse] = []
var _timer := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_rng.randomize()
	_reset_timer()
	set_process(false)

# Called by the parent circuit whenever it regenerates its traces
func set_traces(traces: Array[PackedVector2Array]) -> void:
	_paths.clear()
	_pulses.clear()
	for t in traces:
		if t.size() < 2:
			continue
		_paths.append(_make_path(t))
		var r := t.duplicate()
		r.reverse()                                # pulses can travel both directions
		_paths.append(_make_path(r))
	set_process(not _paths.is_empty())
	queue_redraw()

func _make_path(pts: PackedVector2Array) -> Dictionary:
	var cum := PackedFloat32Array([0.0])
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
		cum.append(total)
	return {"pts": pts, "cum": cum, "total": total}

func _reset_timer() -> void:
	_timer = _rng.randf_range(interval_min, interval_max)

func _process(delta: float) -> void:
	var had := not _pulses.is_empty()
	_timer -= delta
	if _timer <= 0.0:
		if _pulses.size() < max_pulses:
			_spawn()
		_reset_timer()
	for i in range(_pulses.size() - 1, -1, -1):
		var p := _pulses[i]
		p.dist += p.speed * delta
		if p.dist - tail_length > p.total:         # tail fully left the trace
			_pulses.remove_at(i)
	if had or not _pulses.is_empty():
		queue_redraw()

func _spawn() -> void:
	# pick two random paths and keep the longer one, so pulses favor long runs
	var a := _paths[_rng.randi() % _paths.size()]
	var b := _paths[_rng.randi() % _paths.size()]
	var path := a if a.total >= b.total else b
	var p := Pulse.new()
	p.pts = path.pts
	p.cum = path.cum
	p.total = path.total
	p.speed = speed * (1.0 + _rng.randf_range(-speed_variance, speed_variance))
	_pulses.append(p)

func _point_at(p: Pulse, d: float) -> Vector2:
	for i in range(1, p.cum.size()):
		if d <= p.cum[i]:
			var seg := p.cum[i] - p.cum[i - 1]
			var t := 0.0 if seg <= 0.0 else (d - p.cum[i - 1]) / seg
			return p.pts[i - 1].lerp(p.pts[i], t)
	return p.pts[p.pts.size() - 1]

func _draw() -> void:
	var passes := [[6.0, 0.15], [3.0, 0.35], [1.0, 1.0]]
	for p in _pulses:
		var head := minf(p.dist, p.total)
		var tail_start := p.dist - tail_length
		var d0 := maxf(tail_start, 0.0)
		if head - d0 < 0.5:
			continue

		# distances to sample: tail start, every corner in between, head
		var ds: Array[float] = [d0]
		for c in p.cum:
			if c > d0 and c < head:
				ds.append(c)
		ds.append(head)

		var pts := PackedVector2Array()
		var base := PackedColorArray()
		for d in ds:
			pts.append(_point_at(p, d))
			var t := clampf((d - tail_start) / tail_length, 0.0, 1.0)
			base.append(Color(color, t * t * intensity))   # fades in toward the head

		for pass_ in passes:
			var cols := PackedColorArray()
			for c in base:
				cols.append(Color(c, c.a * pass_[1]))
			draw_polyline_colors(pts, cols, width * pass_[0], true)

		if p.dist <= p.total:                              # glowing head dot
			var hp := pts[pts.size() - 1]
			draw_circle(hp, width * 3.5, Color(color, 0.25 * intensity))
			draw_circle(hp, width * 1.6, Color(core_color, intensity))
