class_name SettingsPanel
extends Control
## The settings menu, built in code in the same look as the pause menu and the other panels.
## Tabs: DISPLAY, AUDIO, GAMEPLAY, CONTROLS. Every change is applied and saved straight away
## (through the Settings autoload), so there is no "apply" button.
##
## Used by the pause menu (SETTINGS button) and by the main menu's settings scene.
## Call open(); it emits `closed` when the player presses BACK or Esc.

signal closed

@export var accent := Color("#00E5FF")
@export var font: Font
@export var font_scale: float = 1.0
@export var panel_size := Vector2(980, 720)

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_WARN := Color(1.0, 0.30, 0.37)
const COL_OK := Color(0.30, 0.95, 0.60)
const TABS := ["DISPLAY", "GRAPHICS", "AUDIO", "GAMEPLAY", "CONTROLS"]
const TAB_SECTIONS := {"DISPLAY": "display", "GRAPHICS": "graphics", "AUDIO": "audio", "GAMEPLAY": "gameplay"}

## Rebindable actions, in menu order, with their names.
const ACTIONS := [
	[&"forward", "MOVE UP"], [&"backward", "MOVE DOWN"], [&"left", "MOVE LEFT"], [&"right", "MOVE RIGHT"],
	[&"attack", "ATTACK"], [&"attack_2", "ATTACK 2"],
	[&"skill_1", "SKILL 1"], [&"skill_2", "SKILL 2"], [&"skill_3", "SKILL 3"], [&"skill_4", "SKILL 4"],
	[&"pickup", "PICK UP / SHOW LOOT"], [&"interact", "INTERACT / TALK"],
	[&"stim_1", "USE STIM 1"], [&"stim_2", "USE STIM 2"], [&"script_set", "SWAP SCRIPT SET"],
]
## Menu keys and Esc can't be given to an action.
const RESERVED_KEYS: Array[int] = [KEY_ESCAPE, KEY_K, KEY_I, KEY_C, KEY_M]

var _font: Font
var _tab := "DISPLAY"
var _tab_buttons: Dictionary = {}
var _rows: VBoxContainer
var _msg: Label
var _msg_tween: Tween
var _waiting_action: StringName = &""          # CONTROLS: the action waiting for a new key
var _key_buttons: Dictionary = {}              # action -> Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS        # works in the pause menu
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_build()
	_show_tab(_tab)


func open() -> void:
	visible = true
	_show_tab(_tab)


func close() -> void:
	_waiting_action = &""
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


# ---------- INPUT ----------
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _waiting_action != &"":
		_capture_key(event)
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _capture_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	var is_key := key != null and key.pressed and not key.echo
	var is_mouse := mouse != null and mouse.pressed
	if not (is_key or is_mouse):
		return
	if is_key and key.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return                                        # wait for the real key
	if is_mouse and mouse.button_index >= MOUSE_BUTTON_WHEEL_UP and mouse.button_index <= MOUSE_BUTTON_WHEEL_RIGHT:
		return
	get_viewport().set_input_as_handled()
	var action := _waiting_action
	_waiting_action = &""
	if is_key and key.keycode == KEY_ESCAPE:
		_show_tab("CONTROLS")
		return
	var all: Array = []
	for a in ACTIONS:
		all.append(a[0])
	var error := KeyBindings.rebind(action, event, all, RESERVED_KEYS)
	_show_tab("CONTROLS")
	_notify(error if error != "" else "%s -> %s" % [_action_name(action), GemText.key_label(action)],
		error == "")


# ---------- BUILDING ----------
func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var frame := PauseMenu.Frame.new()
	frame.accent = accent
	add_child(frame)
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -panel_size.x * 0.5
	frame.offset_right = panel_size.x * 0.5
	frame.offset_top = -panel_size.y * 0.5
	frame.offset_bottom = panel_size.y * 0.5

	var margin := MarginContainer.new()
	frame.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := _label("// SETTINGS //", 30, accent)
	col.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	col.add_child(tabs)
	var group := ButtonGroup.new()
	for t in TABS:
		var b := _button(t, 17)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(170, 40)
		b.pressed.connect(_show_tab.bind(t))
		tabs.add_child(b)
		_tab_buttons[t] = b
	col.add_child(_rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(scroll.get_v_scroll_bar())
	col.add_child(scroll)
	var pad := MarginContainer.new()                 # keeps rows clear of the scrollbar
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 18)
	scroll.add_child(pad)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	pad.add_child(_rows)

	_msg = _label("", 15, COL_OK)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.modulate.a = 0.0
	col.add_child(_msg)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	col.add_child(footer)
	var reset := _button("RESET TAB", 16)
	reset.custom_minimum_size = Vector2(170, 44)
	reset.pressed.connect(_reset_tab)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var hint := _label("[ ESC ] BACK", 13, COL_DIM)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(hint)
	var back := _button("BACK", 16)
	back.custom_minimum_size = Vector2(170, 44)
	back.pressed.connect(close)
	footer.add_child(back)

	var overlay := PauseMenu.ScanOverlay.new()
	frame.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _show_tab(t: String) -> void:
	_tab = t
	for name in _tab_buttons:
		(_tab_buttons[name] as Button).set_pressed_no_signal(name == t)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_key_buttons.clear()
	match t:
		"DISPLAY":
			_build_display()
		"GRAPHICS":
			_build_graphics()
		"AUDIO":
			_build_audio()
		"GAMEPLAY":
			_build_gameplay()
		"CONTROLS":
			_build_controls()


func _build_display() -> void:
	var embedded := Settings.is_embedded()
	_choice_row("WINDOW MODE", "display", "window_mode", Settings.WINDOW_MODES,
		func(v): return {"windowed": "WINDOWED", "borderless": "BORDERLESS", "fullscreen": "FULLSCREEN"}[v])
	var windowed: bool = Settings.get_value("display", "window_mode") == "windowed"
	var res_row := _choice_row("RESOLUTION", "display", "resolution", Settings.available_resolutions(),
		func(v): return str(v).replace("x", " x "))
	if not windowed:
		res_row.modulate.a = 0.45
		res_row.tooltip_text = "Only used in WINDOWED mode. Fullscreen always uses your monitor's resolution."
	_toggle_row("VSYNC", "display", "vsync")
	_choice_row("FPS LIMIT", "display", "max_fps", Settings.FPS_LIMITS,
		func(v): return "UNLIMITED" if int(v) == 0 else "%d" % v)
	_toggle_row("SHOW FPS", "display", "show_fps")
	_slider_row("UI SIZE", "display", "ui_scale", 0.75, 1.5, 0.05, func(v): return "%d%%" % roundi(v * 100.0))
	_choice_row("CURSOR", "display", "cursor", Settings.CURSOR_MODES,
		func(v): return "GAME CURSOR" if v == "themed" else "SYSTEM CURSOR")
	var size_row := _choice_row("CURSOR SIZE", "display", "cursor_size", Settings.CURSOR_SIZES,
		func(v): return {24: "SMALL", 32: "NORMAL", 40: "LARGE", 48: "X-LARGE", 64: "HUGE"}.get(int(v), str(v)))
	if Settings.get_value("display", "cursor") != "themed":
		size_row.modulate.a = 0.45
	_note("The UI is laid out for 1920 x 1080 and scaled to your window, so it keeps the same "
		+ "proportions at every resolution. UI SIZE makes all of it bigger or smaller.")
	if embedded:
		_note("Running inside the editor: window mode and resolution apply when the game runs on its own.", COL_WARN)


## GRAPHICS (GraphicsQuality): a QUALITY preset, then each part of it on its own.
func _build_graphics() -> void:
	var q_names := {"low": "LOW", "medium": "MEDIUM", "high": "HIGH", "custom": "CUSTOM"}
	var q_row := _choice_row("QUALITY", "graphics", "quality", GraphicsQuality.QUALITIES,
		func(v): return q_names.get(v, str(v).to_upper()))
	q_row.tooltip_text = "Sets everything below at once. LOW is for older or weaker computers."
	_note("Changing anything below makes QUALITY show CUSTOM.")
	var scale_row := _choice_row("3D RESOLUTION", "graphics", "render_scale", GraphicsQuality.RENDER_SCALES,
		func(v): return "%d%%" % roundi(float(v) * 100.0))
	scale_row.tooltip_text = "Draws the game world at a share of the window. Lower is much faster; menus stay sharp."
	var sh_row := _choice_row("SHADOWS", "graphics", "shadows", GraphicsQuality.SHADOW_MODES,
		func(v): return {"off": "OFF", "sun": "SUN ONLY", "all": "SUN + YOUR LIGHT"}.get(v, str(v)))
	sh_row.tooltip_text = "Your own light's shadows cost the most."
	var fx_row := _choice_row("EFFECT LIGHTS", "graphics", "effect_lights", GraphicsQuality.EFFECT_LIGHT_MODES,
		func(v): return {"none": "NONE", "few": "A FEW", "all": "ALL"}.get(v, str(v)))
	fx_row.tooltip_text = "Flashes from shots, slams and blasts lighting up the room."
	_choice_row("GLOW", "graphics", "glow", [false, true], func(v): return "ON" if v else "OFF")
	var tile_row := _choice_row("TILE DETAIL", "graphics", "tile_detail", GraphicsQuality.TILE_DETAILS,
		func(v): return {"simple": "SIMPLE", "full": "FULL"}.get(v, str(v)))
	tile_row.tooltip_text = "SIMPLE drops the fine cracks, sand and weathering on the road's floors and walls."
	_choice_row("MAX DAMAGE NUMBERS", "graphics", "damage_numbers_max", GraphicsQuality.DAMAGE_NUMBER_CAPS,
		func(v): return str(v))
	var retro_row := _choice_row("RETRO FILTER", "graphics", "retro_filter", GraphicsQuality.RETRO_FILTERS,
		func(v): return {"off": "OFF", "light": "LIGHT", "full": "FULL"}.get(v, str(v)))
	retro_row.tooltip_text = "The screen's retro look. LIGHT drops its glow and colour bleed, the costly parts."
	_note("Older computer? Pick LOW, or lower 3D RESOLUTION and SHADOWS first: they help the most.")


func _build_audio() -> void:
	var pct := func(v): return "%d%%" % roundi(v * 100.0)
	_slider_row("MASTER VOLUME", "audio", "master", 0.0, 1.0, 0.01, pct)
	_slider_row("MUSIC", "audio", "music", 0.0, 1.0, 0.01, pct)
	_slider_row("EFFECTS", "audio", "effects", 0.0, 1.0, 0.01, pct)
	_slider_row("INTERFACE", "audio", "ui", 0.0, 1.0, 0.01, pct)
	_toggle_row("MUTE IN BACKGROUND", "audio", "mute_in_background")
	_note("Sounds use the Music, Effects or UI bus (set the Bus of an AudioStreamPlayer).")


func _build_gameplay() -> void:
	_toggle_row("DAMAGE NUMBERS ON ENEMIES", "gameplay", "enemy_damage_numbers")
	_toggle_row("DAMAGE NUMBERS ON YOU", "gameplay", "player_damage_numbers")
	_choice_row("ITEM NAMES", "gameplay", "item_labels", Settings.ITEM_LABEL_MODES,
		func(v): return "WHILE %s HELD" % GemText.key_label(&"pickup") if v == "hold" else "ALWAYS")
	_choice_row("SHOW LOOT", "gameplay", "loot_filter", Settings.LOOT_FILTERS,
		func(v): return {"all": "ALL ITEMS", "magic": "MAGIC AND BETTER", "rare": "RARE AND BETTER"}[v])
	_toggle_row("ENEMY INFO ON HOVER", "gameplay", "enemy_info")
	_toggle_row("AUTO-BIND NEW SKILLS", "gameplay", "auto_bind_skills")
	_toggle_row("SHAKE LIFE BAR WHEN HIT", "gameplay", "hud_shake")
	_toggle_row("AIM LINE FOR RANGED SKILLS", "gameplay", "aim_line")
	_note("SHOW LOOT only hides item names. Gems are always shown.")


func _build_controls() -> void:
	for entry in ACTIONS:
		var action: StringName = entry[0]
		if not InputMap.has_action(action):
			continue
		var row := _row(entry[1])
		var b := _button("PRESS A KEY..." if action == _waiting_action else GemText.key_label(action), 16)
		b.custom_minimum_size = Vector2(300, 40)
		b.pressed.connect(func() -> void:
			_waiting_action = action
			b.text = "PRESS A KEY...")
		row.add_child(b)
		_key_buttons[action] = b
	_note("Click a key, then press the new key or mouse button. Esc cancels. "
		+ "Taking a key another action uses swaps them. The skills menu shows the same keys.")


# ---------- ROW TYPES ----------
func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := _label(text, 18, COL_TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	_rows.add_child(row)
	return row


## "< VALUE >" picker. `names` turns a value into its label.
func _choice_row(text: String, section: String, key: String, options: Array, names: Callable) -> HBoxContainer:
	var row := _row(text)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	row.add_child(box)
	var prev := _button("<", 18)
	prev.custom_minimum_size = Vector2(44, 40)
	var value := _label("", 18, accent)
	value.custom_minimum_size = Vector2(300, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var next := _button(">", 18)
	next.custom_minimum_size = Vector2(44, 40)
	box.add_child(prev)
	box.add_child(value)
	box.add_child(next)
	var refresh := func() -> void:
		value.text = str(names.call(Settings.get_value(section, key)))
	var step := func(d: int) -> void:
		var current = Settings.get_value(section, key)
		var i := options.find(current)
		i = posmod((i if i >= 0 else 0) + d, options.size())
		Settings.set_value(section, key, options[i])
		if section == "display" or section == "graphics":
			_show_tab(_tab)                 # e.g. resolution greys out; QUALITY moves to CUSTOM
		else:
			refresh.call()
	prev.pressed.connect(step.bind(-1))
	next.pressed.connect(step.bind(1))
	refresh.call()
	return row


func _toggle_row(text: String, section: String, key: String) -> HBoxContainer:
	var row := _row(text)
	var b := _button("", 18)
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(400, 40)
	var refresh := func() -> void:
		var on: bool = Settings.get_value(section, key)
		b.set_pressed_no_signal(on)
		b.text = "ON" if on else "OFF"
		b.add_theme_color_override("font_color", COL_OK if on else COL_DIM)
	b.toggled.connect(func(on: bool) -> void:
		Settings.set_value(section, key, on)
		refresh.call())
	refresh.call()
	row.add_child(b)
	return row


func _slider_row(text: String, section: String, key: String, lo: float, hi: float, step: float,
		fmt: Callable) -> HBoxContainer:
	var row := _row(text)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(310, 40)
	slider.value = float(Settings.get_value(section, key))
	_style_slider(slider)
	var value := _label(str(fmt.call(slider.value)), 18, accent)
	value.custom_minimum_size = Vector2(80, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		value.text = str(fmt.call(v))
		Settings.set_value(section, key, v))
	box.add_child(slider)
	box.add_child(value)
	return row


func _note(text: String, col: Color = COL_DIM) -> void:
	var l := _label(text, 14, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1.0
	_rows.add_child(l)


func _reset_tab() -> void:
	if _tab == "CONTROLS":
		KeyBindings.reset_all()
		_notify("KEYS RESET TO DEFAULT", true)
	else:
		Settings.reset_section(TAB_SECTIONS[_tab])
		_notify("%s RESET TO DEFAULT" % _tab, true)
	_show_tab(_tab)


func _notify(text: String, ok: bool) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", COL_OK if ok else COL_WARN)
	_msg.modulate.a = 1.0
	if _msg_tween:
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_interval(1.5)
	_msg_tween.tween_property(_msg, "modulate:a", 0.0, 0.5)


func _action_name(action: StringName) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return String(action).to_upper()


# ---------- STYLING (same look as PauseMenu / SkillPanel) ----------
func _label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", roundi(fsize * font_scale))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, fsize: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", roundi(fsize * font_scale))
	b.add_theme_color_override("font_color", COL_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _flat(Color(accent, 0.06), Color(accent, 0.35), 1))
	b.add_theme_stylebox_override("hover", _flat(Color(accent, 0.16), Color(accent, 0.8), 1))
	b.add_theme_stylebox_override("pressed", _flat(Color(accent, 0.28), accent, 2))
	b.add_theme_stylebox_override("hover_pressed", _flat(Color(accent, 0.28), accent, 2))
	return b


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


func _style_scrollbar(bar: ScrollBar) -> void:
	bar.custom_minimum_size = Vector2(8, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(accent, 0.08)
	bar.add_theme_stylebox_override("scroll", track)
	for entry in [["grabber", 0.55], ["grabber_highlight", 0.85], ["grabber_pressed", 1.0]]:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(accent, entry[1])
		bar.add_theme_stylebox_override(entry[0], g)


func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(accent, 0.15)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(accent, 0.7)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var grab := _grabber_texture(Color.WHITE)
	s.add_theme_icon_override("grabber", grab)
	s.add_theme_icon_override("grabber_highlight", _grabber_texture(accent))


func _grabber_texture(col: Color) -> Texture2D:
	var img := Image.create(14, 22, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)
