extends Control
## The Null Law in force, top left: its name, what it does to your scripts, and a bar draining
## until the next rewrite. While a rewrite is coming it says so, flickering. Built and driven by
## NullLawDirector, which puts it on the HUD's StimLayer beside the ThreatPanel (outside the game
## view, so the retro screen filter doesn't touch it). It sits under the threat card, and moves
## as that card folds and unfolds. When a law takes hold, a soft violet glow washes in from the
## screen's edges, the card itself flares, and a short line near the top names the law and what it
## does to fights, for a few seconds. It sits between the tutorial banner and the quest toasts, and
## clear of the NEW LOCK card.

const NullLawsRef := preload("res://systems/world/null_laws.gd")
const FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_BG := Color(0.03, 0.01, 0.06, 0.86)
const COL_LAW := Color(0.78, 0.4, 1.0)
const COL_TEXT := Color(0.85, 0.82, 0.92)
const COL_WARN := Color(1.0, 0.75, 0.95)
const WIDTH := 400.0
## Where it sits with no threat card showing, and the gap it keeps below the card.
const TOP := Vector2(16, 100)
const GAP := 8.0

var _panel: PanelContainer
var _style: StyleBoxFlat
var _title: Label
var _name: Label
var _rule: Label
var _bar: ProgressBar
var _warning := false
var _flash: ColorRect                  # the edge glow (EDGE_SHADER)
var _flash_mat: ShaderMaterial
var _big: VBoxContainer
var _big_name: Label
var _big_effect: Label
var _big_tween: Tween
## Seconds the announcement holds before it fades.
const ANNOUNCE_HOLD := 2.5
## Pixels from the top of the screen: under the tutorial banner, above the quest toasts (215).
const ANNOUNCE_TOP := 132.0
## How far it drifts down as it appears.
const ANNOUNCE_DRIFT := 10.0
## Peak strength of the edge glow (0..1).
const GLOW := 0.45
## A violet glow at the screen's edges only, fading to nothing a third of the way in.
const EDGE_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.78, 0.4, 1.0, 1.0);
uniform float amount = 0.0;
void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.62, 1.0, max(d.x, d.y));
	COLOR = vec4(tint.rgb, edge * amount);
}
"""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font := load(FONT) as Font
	_panel = PanelContainer.new()
	_panel.position = TOP
	_panel.custom_minimum_size.x = WIDTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = COL_BG
	_style.border_color = Color(COL_LAW, 0.8)
	_style.set_border_width_all(2)
	_style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", _style)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	_title = _label(font, 13, Color(COL_LAW, 0.8))
	_name = _label(font, 22, COL_LAW)
	_rule = _label(font, 14, COL_TEXT)
	_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rule.custom_minimum_size.x = WIDTH - 24.0
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 5)
	_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_LAW
	var back := StyleBoxFlat.new()
	back.bg_color = Color(COL_LAW, 0.15)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	for c in [_title, _name, _rule, _bar]:
		box.add_child(c)
	_panel.visible = false
	# the announcement: a soft glow at the screen's edges, and one short line near the top
	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = EDGE_SHADER
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = shader
	_flash_mat.set_shader_parameter("tint", COL_LAW)
	_flash_mat.set_shader_parameter("amount", 0.0)
	_flash.material = _flash_mat
	add_child(_flash)
	move_child(_flash, 0)
	_big = VBoxContainer.new()
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_big.offset_top = ANNOUNCE_TOP
	_big.offset_bottom = ANNOUNCE_TOP
	_big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_big.add_theme_constant_override("separation", 2)
	add_child(_big)
	_big_name = _label(font, 22, COL_LAW)
	_big_effect = _label(font, 14, COL_TEXT)
	for l in [_big_name, _big_effect]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_big.add_child(l)
	_big.modulate.a = 0.0


func _process(_delta: float) -> void:
	_panel.position = Vector2(TOP.x, _below_threats())


## The top of the banner: under the threat card when it shows, else TOP.
func _below_threats() -> float:
	var threats := get_parent().get_node_or_null("ThreatPanel") as Control if get_parent() != null else null
	if threats == null or not threats.is_visible_in_tree():
		return TOP.y
	var card := threats.get("_panel") as Control
	if card == null or not card.is_visible_in_tree():
		return TOP.y
	var bottom := card.get_global_rect().end.y - get_global_rect().position.y
	return maxf(TOP.y, bottom + GAP)


## A law is in force.
func show_law(id: String) -> void:
	_warning = false
	_panel.visible = true
	_title.text = "// NULL LAW //"
	_name.text = NullLawsRef.name_of(id)
	_name.add_theme_color_override("font_color", COL_LAW)
	_rule.text = "FIGHTS: %s\nSCRIPTS: %s" % [NullLawsRef.effect_of(id), NullLawsRef.rule_of(id)]
	_style.border_color = Color(COL_LAW, 0.8)


## The law takes hold: a glow from the screen's edges, the card flares, and one line near the top
## names the law and its fight effect.
func announce(id: String) -> void:
	_big_name.text = "NULL LAW // %s" % NullLawsRef.name_of(id)
	_big_effect.text = NullLawsRef.effect_of(id)
	if _big_tween != null and _big_tween.is_valid():
		_big_tween.kill()
	_big.modulate.a = 0.0
	_set_top(ANNOUNCE_TOP - ANNOUNCE_DRIFT)
	_panel.modulate = Color(1.8, 1.6, 2.0)                    # the card flares, then settles
	_big_tween = create_tween().set_parallel(true)
	_big_tween.tween_method(_set_glow, GLOW, 0.0, 1.2)
	_big_tween.tween_property(_panel, "modulate", Color.WHITE, 0.8)
	_big_tween.tween_property(_big, "modulate:a", 1.0, 0.25)
	_big_tween.tween_method(_set_top, ANNOUNCE_TOP - ANNOUNCE_DRIFT, ANNOUNCE_TOP, 0.35) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_big_tween.tween_property(_big, "modulate:a", 0.0, 0.6).set_delay(0.25 + ANNOUNCE_HOLD)


func _set_glow(v: float) -> void:
	_flash_mat.set_shader_parameter("amount", v)


## The announcement's top edge, in pixels from the top of the screen.
func _set_top(y: float) -> void:
	_big.offset_top = y
	_big.offset_bottom = y


## A rewrite is coming: `id` takes over when the bar runs out.
func warn(id: String) -> void:
	_warning = true
	_panel.visible = true
	_title.text = "// THE NULL IS REWRITING //"
	_name.text = "NEXT: " + NullLawsRef.name_of(id)
	_rule.text = "FIGHTS: %s\nSCRIPTS: %s\nSwap to the script set for it." % [NullLawsRef.effect_of(id), NullLawsRef.rule_of(id)]


## 1 = just started .. 0 = about to change.
func set_left(fraction: float) -> void:
	_bar.value = clampf(fraction, 0.0, 1.0)
	if _warning:
		var flick := 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 90.0))
		_name.add_theme_color_override("font_color", Color(COL_WARN, flick))
		_style.border_color = Color(COL_WARN, flick)


func _label(font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
