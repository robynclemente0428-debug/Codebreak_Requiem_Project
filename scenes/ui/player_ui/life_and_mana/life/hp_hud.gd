@tool
class_name HpHud
extends Control
## Retro-futuristic HP readout: chamfered neon frame, segmented bar, damage trail,
## scanlines, low-health warning. It draws everything itself, so there are no child
## nodes to set up. Attach it to a plain Control and call bind() with a HealthComponent.
## (@tool lets you see and size it in the editor viewport.)

@export var segments: int = 20
@export var label_text: String = "HP"
@export var font: Font                      # leave empty to use the Courier Prime font below
@export var font_size: int = 22             # at ui_scale 1.0
@export var show_scanlines := true
## Shake when damaged (Settings > Gameplay > shake life bar when hit).
const COL_BARRIER := Color(0.45, 0.85, 1.0)
var shake_enabled := true
@export var debug_keys := false             # J = take damage, K = heal (for tuning the look)
@export_group("Size and opacity")
## Scales the whole HUD: frame, bar, text. 1.0 = 520x92 px.
@export_range(0.5, 4.0, 0.05) var ui_scale: float = 1.5:
	set(v):
		ui_scale = v
		_update_size()
## 0 = no background panel, 1 = solid.
@export_range(0.0, 1.0, 0.01) var bg_opacity: float = 0.35
@export_group("Colors")
@export var col_ok := Color("#FF2A3D")      # healthy
@export var col_warn := Color("#FF2A3D")    # getting low (same red; the pulse and warning text carry the alert)
@export var col_crit := Color("#FF7A85")    # critical (brighter, pulses)

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const BASE_SIZE := Vector2(520, 92)
# Layout values at ui_scale 1.0
const CHAMFER := 16.0       # size of the cut corners
const PAD := 16.0
const SLANT := 8.0          # how far each segment leans
const SEG_GAP := 4.0
const BAR_H := 26.0

var _health: HealthComponent
var _cur := 1.0
var _max := 1.0
var _target := 1.0          # real health ratio
var _shown := 1.0           # ratio the bar is filled to
var _ghost := 1.0           # white damage trail
var _ghost_delay := 0.0
var _flash := 0.0
var _shake := 0.0
var _time := 0.0
var _barrier_flash := 0.0  # bright pulse when a barrier goes up
var _last_barrier := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_size()


func _update_size() -> void:
	custom_minimum_size = BASE_SIZE * ui_scale
	if is_inside_tree():
		size = custom_minimum_size


# Joined in _enter_tree so the player can find the HUD even if it readies first
func _enter_tree() -> void:
	add_to_group("hp_hud")


func _ready() -> void:
	Settings.bind_to(self, &"shake_enabled", "gameplay", "hud_shake")
	if font == null and ResourceLoader.exists(DEFAULT_FONT):
		font = load(DEFAULT_FONT)


# ---------- DATA ----------
func bind(health: HealthComponent) -> void:
	if _health and _health.health_changed.is_connected(_on_health_changed):
		_health.health_changed.disconnect(_on_health_changed)
	_health = health
	if _health == null:
		return
	_health.health_changed.connect(_on_health_changed)

	# Pick up the current value if initialize() already ran
	var max_hp := 0.0
	if _health.stats:
		max_hp = _health.stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	if max_hp > 0.0 and _health.current_health > 0.0:
		set_values(_health.current_health, max_hp, true)


func _on_health_changed(current: float, max_hp: float) -> void:
	set_values(current, max_hp)


func set_values(current: float, max_hp: float, snap := false) -> void:
	var prev_cur := _cur
	var prev_max := _max
	_max = maxf(max_hp, 1.0)
	_cur = clampf(current, 0.0, _max)
	var ratio := _cur / _max

	# True when only the maximum changed (equipment), including the clamp when it shrinks
	var only_max_changed := is_equal_approx(_cur, prev_cur) \
		or (_max < prev_max and is_equal_approx(_cur, _max))

	if snap:
		_shown = ratio
		_ghost = ratio
		_flash = 0.0
	elif only_max_changed:
		_ghost = ratio                          # no trail, no flash; the bar eases to the new ratio
	elif _cur < prev_cur:                       # took damage
		_ghost = maxf(_ghost, _target)
		_shown = ratio
		_ghost_delay = 0.45
		_flash = 1.0
		_shake = 1.0 if shake_enabled else 0.0
	else:                                       # healed
		_ghost = ratio
		_flash = 0.5
	_target = ratio


func _unhandled_key_input(event: InputEvent) -> void:
	if not debug_keys:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_J:
			set_values(_cur - _max * 0.12, _max)
		elif event.keycode == KEY_K:
			set_values(_cur + _max * 0.12, _max)


# ---------- ANIMATION ----------
func _process(delta: float) -> void:
	_time += delta
	_shown = move_toward(_shown, _target, delta * 1.5)
	if _ghost_delay > 0.0:
		_ghost_delay -= delta
	elif _ghost > _target:
		_ghost = move_toward(_ghost, _target, delta * 0.8)
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	_shake = move_toward(_shake, 0.0, delta * 5.0)
	var b := _health.barrier if _health != null else 0.0
	if b > _last_barrier + 0.5:
		_barrier_flash = 1.0
	_last_barrier = b
	_barrier_flash = move_toward(_barrier_flash, 0.0, delta * 3.0)
	queue_redraw()


func _bar_color(r: float) -> Color:
	if r >= 0.5:
		return col_ok
	if r >= 0.25:
		return col_warn.lerp(col_ok, (r - 0.25) / 0.25)
	return col_crit.lerp(col_warn, r / 0.25)


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
	var alive := _target > 0.0
	var low := alive and _target <= 0.5
	var pulse := 0.5 + 0.5 * sin(_time * 8.0)
	var accent := _bar_color(_shown)
	var shield := _health.barrier if _health != null else 0.0
	var shielded := shield >= 1.0 and _max > 0.0
	var shield_left := _health.barrier_time_left() if shielded else 0.0
	# Fades in and out in its last second, so you can see it's about to drop
	var shield_alpha := 1.0 if shield_left * SkillBehavior.BARRIER_SECONDS > 1.0 		else 0.45 + 0.55 * (0.5 + 0.5 * sin(_time * 16.0))
	var frame_col := accent.lerp(Color.WHITE, _flash)
	if shielded:
		frame_col = frame_col.lerp(COL_BARRIER, 0.75).lerp(Color.WHITE, _barrier_flash * 0.6)

	# Hit shake
	if _shake > 0.0:
		var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 5.0 * s * _shake
		draw_set_transform(jitter, 0.0, Vector2.ONE)

	# --- frame: cut corners top-left and bottom-right ---
	var poly := PackedVector2Array([
		Vector2(chamfer, 0), Vector2(w, 0), Vector2(w, h - chamfer),
		Vector2(w - chamfer, h), Vector2(0, h), Vector2(0, chamfer)])
	if bg_opacity > 0.0:
		draw_colored_polygon(poly, Color(0.11, 0.02, 0.04, bg_opacity))
	var outline := PackedVector2Array(poly)
	outline.append(poly[0])
	draw_polyline(outline, Color(frame_col, 0.18), 7.0 * s, true)    # glow
	draw_polyline(outline, frame_col, 2.0 * s, true)

	# --- header: label, readout, warning ---
	var bar_x := pad
	var bar_y := h - pad - bar_h - 6.0 * s
	var bar_w := w - pad * 2.0 - slant
	var base_y := bar_y - 8.0 * s

	_text(fnt, Vector2(pad, base_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, accent)
	var max_shown := roundi(_max)
	var readout := "%03d / %03d" % [mini(ceili(_shown * _max), max_shown), max_shown]
	_text(fnt, Vector2(pad, base_y), readout, HORIZONTAL_ALIGNMENT_RIGHT, w - pad * 2.0, fs,
		accent.lerp(Color.WHITE, 0.6))
	if shielded:
		# Barrier from skill scripts, in cyan, just left of the life readout
		var rw := fnt.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tag := "BARRIER %d" % roundi(shield)
		_text(fnt, Vector2(pad, base_y), tag, HORIZONTAL_ALIGNMENT_RIGHT,
			w - pad * 2.0 - rw - 18.0 * s, fs,
			Color(COL_BARRIER.lerp(Color.WHITE, 0.3 + 0.5 * _barrier_flash), shield_alpha))
	if low:
		_text(fnt, Vector2(pad, base_y), "! LOW VITALS !", HORIZONTAL_ALIGNMENT_CENTER,
			w - pad * 2.0, fs - roundi(6.0 * s), Color(col_crit, 0.4 + 0.6 * pulse))

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
			_seg(x, bar_y, sw, g, Color(1, 1, 1, 0.45))                    # damage trail
		var f := clampf(_shown * n - i, 0.0, 1.0)
		if f > 0.0:
			_seg(x, bar_y, sw, f, fill_col, true)                          # health

	# Barrier: cyan segments laid over the life bar, as many as the shield is big
	# (a 15% barrier covers 15% of the bar), plus a strip above that drains with its time.
	if shielded:
		var frac := clampf(shield / _max, 0.0, 1.0)
		var fill := Color(COL_BARRIER.lerp(Color.WHITE, 0.4 * _barrier_flash), 0.92 * shield_alpha)
		for i in n:
			var f := clampf(frac * n - i, 0.0, 1.0)
			if f <= 0.0:
				break
			_seg(bar_x + i * (sw + seg_gap), bar_y, sw, f, fill, true)
		var edge := COL_BARRIER.lerp(Color.WHITE, 0.5)
		edge.a = shield_alpha
		var tx := bar_x + (bar_w + slant) * shield_left
		draw_line(Vector2(bar_x + slant, bar_y - 5.0 * s), Vector2(tx + slant, bar_y - 5.0 * s),
			Color(COL_BARRIER, 0.3 * shield_alpha), 9.0 * s)                # glow
		draw_line(Vector2(bar_x + slant, bar_y - 5.0 * s), Vector2(tx + slant, bar_y - 5.0 * s),
			edge, 4.0 * s)

	# Tick marks under the bar, every 5 segments
	for i in range(0, n + 1, 5):
		var tx := bar_x + (bar_w + slant) * float(i) / n
		draw_line(Vector2(tx, bar_y + bar_h + 3.0 * s), Vector2(tx, bar_y + bar_h + 8.0 * s),
			Color(accent, 0.5), maxf(1.0, s * 0.8))

	if not alive:
		var blink := 1.0 if int(_time * 2.0) % 2 == 0 else 0.35
		_text(fnt, Vector2(bar_x, bar_y + bar_h - 5.0 * s), "// OFFLINE //",
			HORIZONTAL_ALIGNMENT_CENTER, bar_w, fs, Color(col_crit, blink))

	# --- CRT scanlines and a slow sweep ---
	if show_scanlines:
		var step := maxf(3.0 * s, 3.0)
		var line_w := maxf(1.0, s * 0.8)
		var y := 2.0
		while y < h - 2.0:
			draw_line(Vector2(chamfer, y), Vector2(w - chamfer, y), Color(0, 0, 0, 0.14), line_w)
			y += step
		var sweep_y := fposmod(_time * 40.0 * s, h + 60.0 * s) - 30.0 * s
		if sweep_y > 2.0 and sweep_y < h - 2.0:
			draw_line(Vector2(chamfer, sweep_y), Vector2(w - chamfer, sweep_y),
				Color(1, 1, 1, 0.08), 5.0 * s)


## Text with a dark outline, so it stays readable over a see-through background.
func _text(fnt: Font, pos: Vector2, text: String, align: HorizontalAlignment,
		width: float, fs: int, col: Color) -> void:
	draw_string_outline(fnt, pos, text, align, width, fs, maxi(roundi(3.0 * ui_scale), 2),
		Color(0, 0, 0, 0.75 * col.a))
	draw_string(fnt, pos, text, align, width, fs, col)


## One leaning bar segment, filled `frac` of the way from its left edge.
func _seg(x: float, y: float, sw: float, frac: float, col: Color, glow := false) -> void:
	var fw := sw * frac
	if fw < 1.0:
		return                      # too thin to triangulate
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
