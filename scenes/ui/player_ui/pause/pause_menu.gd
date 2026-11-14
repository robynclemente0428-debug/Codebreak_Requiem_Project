class_name PauseMenu
extends CanvasLayer
## Esc pauses the game: a dark overlay plus a small menu with Resume, Settings, Main Menu and Exit.
## If a panel (inventory, skills, character) is open, Esc closes that first instead.
##
## Setup: add a CanvasLayer to your world scene, attach this script, and set "Main Menu Scene"
## in the Inspector. It builds its own UI in code, in the same look as your other panels.

@export_file("*.tscn") var main_menu_scene: String = ""
@export var font: Font                              # leave empty to use the Courier Prime font below
@export var font_scale: float = 1.0
@export var accent := Color("#00E5FF")
@export_range(0.0, 1.0, 0.01) var dim_opacity: float = 0.7
@export var panel_width: float = 420.0
## Ask for a second click before leaving to the main menu or quitting.
@export var confirm_destructive: bool = true

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
## Esc closes these first (one per press, in this order). Each needs is_open() and close().
## The pause menu reads Esc in _input, before any panel sees it, so every panel that should
## close on Esc must be listed here, or Esc pauses the game instead.
const PANEL_GROUPS := ["dialogue_panel", "shop_panel", "waypoint_panel", "party_menu", "npc_info", "skill_panel", "inventory_panel", "character_panel", "quest_log"]
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_WARN := Color(1.0, 0.30, 0.37)

var _font: Font
var _paused := false
var _tween: Tween
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _changed_mouse_mode := false
var _confirm_btn: Button

var _root: Control
var _dim: ColorRect
var _resume_btn: Button
var _settings_btn: Button
var _frame: Control
var _settings: SettingsPanel
var _menu_btn: Button
var _exit_btn: Button


func _ready() -> void:
	layer = 100                                     # above the HUD and the fade layer
	process_mode = Node.PROCESS_MODE_ALWAYS         # keeps working while the tree is paused
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_build_ui()
	_root.visible = false


func is_paused() -> bool:
	return _paused


func pause() -> void:
	if _paused:
		return
	_paused = true
	SaveManager.save_party()
	_reset_confirm()
	var mode := Input.mouse_mode
	if mode == Input.MOUSE_MODE_CAPTURED or mode == Input.MOUSE_MODE_HIDDEN \
			or mode == Input.MOUSE_MODE_CONFINED_HIDDEN:
		_prev_mouse_mode = mode
		_changed_mouse_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Coop.in_game:
		Coop.lock_input(true)                          # co-op: the world keeps running for the others
	else:
		get_tree().paused = true
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = true
	_fade(1.0)


func resume() -> void:
	if not _paused:
		return
	_paused = false
	_reset_confirm()
	if _settings != null and _settings.is_open():
		_settings.close()
	get_tree().paused = false
	Coop.lock_input(false)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE     # stop blocking clicks while it fades out
	if _changed_mouse_mode:
		Input.mouse_mode = _prev_mouse_mode
		_changed_mouse_mode = false
	_fade(0.0)


func _input(event: InputEvent) -> void:
	if _settings != null and _settings.is_open():
		return                                         # the settings panel handles its own Esc
	for n in get_tree().get_nodes_in_group("death_menu"):
		if n.is_open():
			return
	if not event.is_action_pressed(&"ui_cancel"):        # Esc by default
		return
	get_viewport().set_input_as_handled()
	if _paused:
		resume()
	elif not _close_open_panel():
		pause()


## Closes the first open panel. Returns true if one was open.
func _close_open_panel() -> bool:
	for group in PANEL_GROUPS:
		for panel in get_tree().get_nodes_in_group(group):
			if panel.has_method("is_open") and panel.is_open():
				panel.close()
				return true
	return false


func _fade(target: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", target, 0.14)
	if target <= 0.0:
		_tween.finished.connect(func() -> void:
			if not _paused:
				_root.visible = false)


# ---------- BUTTONS ----------
func _on_settings() -> void:
	if not _paused:
		return
	_reset_confirm()
	if _settings == null:
		_settings = SettingsPanel.new()
		_settings.accent = accent
		_settings.font = _font
		_settings.font_scale = font_scale
		_root.add_child(_settings)
		_settings.closed.connect(func() -> void: _frame.visible = true)
	_frame.visible = false
	_settings.open()


func _on_main_menu() -> void:
	if not _paused or _needs_confirm(_menu_btn):
		return
	if main_menu_scene == "":
		push_warning("PauseMenu: set Main Menu Scene in the Inspector")
		return
	# SaveManager.save()  # call your save here, if you have one
	SaveManager.save_party()
	SaveManager.end_session() 
	_paused = false
	get_tree().paused = false
	get_tree().change_scene_to_file(main_menu_scene)


func _on_exit() -> void:
	if not _paused or _needs_confirm(_exit_btn):
		return
	SaveManager.quit_game()                  # saves, hides the window, then closes


## First click arms the button ("CONFIRM?"), the second click does it.
func _needs_confirm(btn: Button) -> bool:
	if not confirm_destructive:
		return false
	if _confirm_btn == btn:
		return false
	_reset_confirm()
	_confirm_btn = btn
	btn.text = "CONFIRM?"
	btn.add_theme_color_override("font_color", COL_WARN)
	return true


func _reset_confirm() -> void:
	if _confirm_btn != null:
		_confirm_btn.text = _confirm_btn.get_meta("label")
		_confirm_btn.add_theme_color_override("font_color", COL_DIM)
		_confirm_btn = null


# ---------- BUILDING THE UI ----------
func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, dim_opacity)
	_root.add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var frame := Frame.new()
	_frame = frame
	frame.accent = accent
	_root.add_child(frame)
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -panel_width * 0.5
	frame.offset_right = panel_width * 0.5
	frame.offset_top = -225.0
	frame.offset_bottom = 225.0

	var margin := MarginContainer.new()
	frame.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := _label("// PAUSED //", 32, accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	col.add_child(_rule())

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	col.add_child(spacer)

	_resume_btn = _menu_button("RESUME")
	_resume_btn.pressed.connect(resume)
	col.add_child(_resume_btn)
	_settings_btn = _menu_button("SETTINGS")
	_settings_btn.pressed.connect(_on_settings)
	col.add_child(_settings_btn)
	_menu_btn = _menu_button("MAIN MENU")
	_menu_btn.pressed.connect(_on_main_menu)
	col.add_child(_menu_btn)
	_exit_btn = _menu_button("EXIT")
	_exit_btn.pressed.connect(_on_exit)
	col.add_child(_exit_btn)

	var hint := _label("[ ESC ]  RESUME", 13, COL_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	col.add_child(hint)

	var overlay := ScanOverlay.new()
	frame.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.set_meta("label", text)
	b.custom_minimum_size = Vector2(0, 56)
	b.focus_mode = Control.FOCUS_NONE
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", roundi(22 * font_scale))
	b.add_theme_color_override("font_color", COL_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _flat(Color(accent, 0.06), Color(accent, 0.35), 1))
	b.add_theme_stylebox_override("hover", _flat(Color(accent, 0.16), Color(accent, 0.8), 1))
	b.add_theme_stylebox_override("pressed", _flat(Color(accent, 0.28), accent, 2))
	b.add_theme_stylebox_override("hover_pressed", _flat(Color(accent, 0.28), accent, 2))
	b.mouse_exited.connect(func() -> void:                 # walking away cancels a pending confirm
		if _confirm_btn == b:
			_reset_confirm())
	return b


func _label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", roundi(fsize * font_scale))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _flat(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(accent, 0.5)
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ---------- SMALL DRAWN WIDGETS ----------
## The chamfered, glowing panel behind the buttons.
class Frame extends Control:
	var accent := Color.WHITE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := 22.0
		var poly := PackedVector2Array([
			Vector2(c, 0), Vector2(w, 0), Vector2(w, h - c),
			Vector2(w - c, h), Vector2(0, h), Vector2(0, c)])
		draw_colored_polygon(poly, Color(0.02, 0.05, 0.09, 0.96))
		var outline := PackedVector2Array(poly)
		outline.append(poly[0])
		draw_polyline(outline, Color(accent, 0.18), 7.0, true)
		draw_polyline(outline, accent, 2.0, true)


## CRT scanlines and a slow sweep over the panel.
class ScanOverlay extends Control:
	var t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			t += delta
			queue_redraw()

	func _draw() -> void:
		var inset := 22.0
		var y := 2.0
		while y < size.y - 2.0:
			draw_line(Vector2(inset, y), Vector2(size.x - inset, y), Color(0, 0, 0, 0.13), 1.0)
			y += 3.0
		# The sweep stays inside the scanlines' band, so it never shows past the panel's edges
		var top := 2.0 + 4.0                          # half the sweep's 8 px thickness
		var band := maxf(size.y - 4.0 - 8.0, 1.0)
		var sweep_y := top + fposmod(t * 90.0, band)
		draw_line(Vector2(inset, sweep_y), Vector2(size.x - inset, sweep_y), Color(1, 1, 1, 0.05), 8.0)
