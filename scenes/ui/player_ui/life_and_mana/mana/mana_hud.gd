@tool
class_name ManaHud
extends Control
## Retro-futuristic mana readout, the blue twin of HpHud: chamfered neon frame, segmented
## bar, spend trail, scanlines. It draws everything itself, so attach it to a plain Control
## and call bind() with a ManaComponent. Place it under or beside the HP HUD.

@export var segments: int = 12
@export var label_text: String = "MP"
@export var font: Font                      # leave empty to use the Courier Prime font below
@export var font_size: int = 14             # at ui_scale 1.0
@export var show_scanlines := true
@export var debug_keys := false             # N = spend mana, M = restore (for tuning the look)
@export_group("Size and opacity")
## Scales the whole HUD. 1.0 = 300x58 px, a compact bar (the HP HUD is 520x92 at 1.0).
@export_range(0.5, 4.0, 0.05) var ui_scale: float = 1.0:
	set(v):
		ui_scale = v
		_update_size()
## 0 = no background panel, 1 = solid.
@export_range(0.0, 1.0, 0.01) var bg_opacity: float = 0.35
@export_group("Colors")
@export var col_ok := Color("#2FA8FF")      # normal
@export var col_low := Color("#5CC8FF")     # nearly empty (brighter, pulses)
@export var col_denied := Color("#FF2A3D")  # flashes when a spell can't be afforded

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
# Same proportions as HpHud, so the two bars match when given the same ui_scale
const BASE_SIZE := Vector2(520, 92)
const CHAMFER := 16.0
const PAD := 16.0
const SLANT := 8.0
const SEG_GAP := 4.0
const BAR_H := 26.0

var _mana: ManaComponent
var _cur := 1.0
var _max := 1.0
var _target := 1.0          # real mana ratio
var _shown := 1.0           # ratio the bar is filled to
var _ghost := 1.0           # white spend trail
var _ghost_delay := 0.0
var _flash := 0.0
var _denied := 0.0
var _time := 0.0
var _drawn: Array = []      # what the bar was last drawn with: redraw only when it changes
var _sweep: HudSweep


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_size()


func _update_size() -> void:
	custom_minimum_size = BASE_SIZE * ui_scale
	if is_inside_tree():
		size = custom_minimum_size


# Joined in _enter_tree so the player can find the HUD even if it readies first
func _enter_tree() -> void:
	add_to_group("mana_hud")


func _ready() -> void:
	if font == null and ResourceLoader.exists(DEFAULT_FONT):
		font = load(DEFAULT_FONT)


# ---------- DATA ----------
func bind(mana: ManaComponent) -> void:
	if _mana:
		if _mana.mana_changed.is_connected(_on_mana_changed):
			_mana.mana_changed.disconnect(_on_mana_changed)
		if _mana.spend_failed.is_connected(_on_spend_failed):
			_mana.spend_failed.disconnect(_on_spend_failed)
	_mana = mana
	if _mana == null:
		return
	_mana.mana_changed.connect(_on_mana_changed)
	_mana.spend_failed.connect(_on_spend_failed)

	# Pick up the current value if initialize() already ran
	var m := _mana.get_max_mana()
	if m > 0.0:
		set_values(_mana.current_mana, m, true)


func _on_mana_changed(current: float, max_mana: float) -> void:
	set_values(current, max_mana)


func _on_spend_failed(_needed: float, _current: float) -> void:
	_denied = 1.0


func set_values(current: float, max_mana: float, snap := false) -> void:
	_max = maxf(max_mana, 1.0)
	_cur = clampf(current, 0.0, _max)
	var ratio := _cur / _max

	if snap:
		_shown = ratio
		_ghost = ratio
		_flash = 0.0
	elif ratio < _target - 0.0005:                  # spent
		_ghost = maxf(_ghost, _target)              # trail starts where the bar was
		_shown = ratio
		_ghost_delay = 0.3
		_flash = 0.6
	elif ratio > _target:                           # regenerated: rises smoothly, no flash
		_ghost = maxf(_ghost, ratio)
	_target = ratio


func _unhandled_key_input(event: InputEvent) -> void:
	if not debug_keys:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			set_values(_cur - _max * 0.15, _max)
		elif event.keycode == KEY_M:
			set_values(_cur + _max * 0.15, _max)


# ---------- ANIMATION ----------
func _process(delta: float) -> void:
	_time += delta
	# the bar follows quickly so steady regeneration looks smooth rather than stepped
	_shown = move_toward(_shown, _target, delta * 1.5)
	if _ghost_delay > 0.0:
		_ghost_delay -= delta
	elif _ghost > _target:
		_ghost = move_toward(_ghost, _target, delta * 0.8)
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	_denied = move_toward(_denied, 0.0, delta * 3.0)
	if _sweep == null:
		_sweep = HudSweep.new()
		add_child(_sweep)
	_sweep.visible = show_scanlines
	if show_scanlines:
		_sweep.follow(size, CHAMFER * ui_scale, ui_scale, _time)
	# Redraw only when something on the bar changed. Low mana (the pulse, DEPLETED blink)
	# moves every frame, so it always does.
	var moving := _target < 0.2
	var state := [_shown, _ghost, _flash, _denied, _max, ui_scale, size]
	if moving or state != _drawn:
		_drawn = state
		queue_redraw()


# ---------- DRAWING ----------
func _draw() -> void:
	var s := ui_scale
	var w := size.x
	var h := size.y
	var chamfer := CHAMFER * s
	var pad := PAD * s
	var slant := SLANT * s
	var seg_gap := SEG_GAP * s
	var bar_h := BAR_H * s
	var fs := roundi(font_size * s)

	var fnt: Font = font if font else ThemeDB.fallback_font
	var empty := _target <= 0.001
	var low := not empty and _target < 0.2
	var pulse := 0.5 + 0.5 * sin(_time * 8.0)
	var accent := col_low if low else col_ok
	accent = accent.lerp(col_denied, _denied)
	var frame_col := accent.lerp(Color.WHITE, _flash * 0.6)

	# --- frame: cut corners top-right and bottom-left (the mirror of the HP frame) ---
	var poly := PackedVector2Array([
		Vector2(0, 0), Vector2(w - chamfer, 0), Vector2(w, chamfer),
		Vector2(w, h), Vector2(chamfer, h), Vector2(0, h - chamfer)])
	if bg_opacity > 0.0:
		draw_colored_polygon(poly, Color(0.02, 0.06, 0.12, bg_opacity))
	var outline := PackedVector2Array(poly)
	outline.append(poly[0])
	draw_polyline(outline, Color(frame_col, 0.18), 7.0 * s, true)    # glow
	draw_polyline(outline, frame_col, 2.0 * s, true)

	# --- header ---
	var bar_x := pad
	var bar_y := h - pad - bar_h - 6.0 * s
	var bar_w := w - pad * 2.0 - slant
	var base_y := bar_y - 8.0 * s

	_text(fnt, Vector2(pad, base_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, accent)
	var readout := "%03d / %03d" % [ceili(_shown * _max), int(_max)]
	_text(fnt, Vector2(pad, base_y), readout, HORIZONTAL_ALIGNMENT_RIGHT, w - pad * 2.0, fs,
		accent.lerp(Color.WHITE, 0.6))
	if _denied > 0.05:
		_text(fnt, Vector2(pad, base_y), "NO MANA", HORIZONTAL_ALIGNMENT_CENTER,
			w - pad * 2.0, fs - roundi(3.0 * s), Color(col_denied, _denied))
	elif low:
		_text(fnt, Vector2(pad, base_y), "! LOW MANA !", HORIZONTAL_ALIGNMENT_CENTER,
			w - pad * 2.0, fs - roundi(3.0 * s), Color(col_low, 0.4 + 0.6 * pulse))

	# --- segmented bar ---
	var n := maxi(segments, 1)
	var sw := (bar_w - seg_gap * (n - 1)) / n
	var fill_col := accent
	if low:
		fill_col.a = 0.55 + 0.45 * pulse

	for i in n:
		var x := bar_x + i * (sw + seg_gap)
		_seg(x, bar_y, sw, 1.0, Color(accent, 0.16))                       # empty slot
		var g := clampf(_ghost * n - i, 0.0, 1.0)
		if g > 0.0:
			_seg(x, bar_y, sw, g, Color(1, 1, 1, 0.4))                     # spend trail
		var f := clampf(_shown * n - i, 0.0, 1.0)
		if f > 0.0:
			_seg(x, bar_y, sw, f, fill_col, true)                          # mana

	# Tick marks under the bar, every 5 segments
	for i in range(0, n + 1, 5):
		var tx := bar_x + (bar_w + slant) * float(i) / n
		draw_line(Vector2(tx, bar_y + bar_h + 3.0 * s), Vector2(tx, bar_y + bar_h + 8.0 * s),
			Color(accent, 0.5), maxf(1.0, s * 0.8))

	if empty:
		var blink := 1.0 if int(_time * 2.0) % 2 == 0 else 0.35
		_text(fnt, Vector2(bar_x, bar_y + bar_h - 5.0 * s), "// DEPLETED //",
			HORIZONTAL_ALIGNMENT_CENTER, bar_w, fs, Color(col_low, blink))

	# --- CRT scanlines and a slow sweep ---
	if show_scanlines:
		var step := maxf(3.0 * s, 3.0)
		var line_w := maxf(1.0, s * 0.8)
		var y := 2.0
		while y < h - 2.0:
			draw_line(Vector2(chamfer, y), Vector2(w - chamfer, y), Color(0, 0, 0, 0.14), line_w)
			y += step
		# The moving sweep is its own child (HudSweep), so the bar only redraws when it changes


## Text with a dark outline, so it stays readable over a see-through background.
func _text(fnt: Font, pos: Vector2, text: String, align: HorizontalAlignment,
		width: float, fs: int, col: Color) -> void:
	draw_string_outline(fnt, pos, text, align, width, fs, maxi(roundi(2.0 * ui_scale), 2),
		Color(0, 0, 0, 0.75 * col.a))
	draw_string(fnt, pos, text, align, width, fs, col)


## One leaning bar segment, filled `frac` of the way from its left edge.
func _seg(x: float, y: float, sw: float, frac: float, col: Color, glow := false) -> void:
	var fw := sw * frac
	if fw < 1.0:
		return
	var slant := SLANT * ui_scale
	var bar_h := BAR_H * ui_scale
	var pts := PackedVector2Array([
		Vector2(x, y + bar_h), Vector2(x + slant, y),
		Vector2(x + slant + fw, y), Vector2(x + fw, y + bar_h)])
	draw_colored_polygon(pts, col)
	if glow:
		var o := PackedVector2Array(pts)
		o.append(pts[0])
		draw_polyline(o, Color(col, col.a * 0.25), 5.0 * ui_scale, true)
		
