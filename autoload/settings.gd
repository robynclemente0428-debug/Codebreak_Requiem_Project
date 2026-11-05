extends Node
## Autoload: Settings
## Loads, applies and saves the player's settings (user://settings.cfg). Settings belong to the
## computer, not to a character, so they live outside the character saves.
## Key bindings are saved separately by KeyBindings (user://keybinds.cfg).
##
## Read a value:        Settings.get_value("gameplay", "hud_shake")
## Change a value:      Settings.set_value("audio", "music", 0.5)    (applies, saves, emits changed)
## Follow a value:      Settings.bind_to(self, "show_enemy_damage", "gameplay", "enemy_damage_numbers")
##                      sets the property now and every time the setting changes.
##
## The UI is always laid out at BASE_SIZE (1920x1080) and scaled to the real window, so every
## resolution looks the same, just bigger or smaller. ui_scale makes all UI bigger or smaller.

signal changed(section: String, key: String, value: Variant)

const SAVE_PATH := "user://settings.cfg"
const BASE_SIZE := Vector2i(1920, 1080)
## Frames WINDOWED is checked (and re-applied if needed) after switching to it.
const WINDOWED_RETRIES := 4

## Every setting and its default. Add new settings here and they are saved automatically.
const DEFAULTS := {
	"display": {
		"window_mode": "borderless",      # "windowed", "borderless" or "fullscreen"
		"resolution": "1920x1080",        # window size, only used when windowed
		"vsync": true,
		"max_fps": 0,                     # 0 = no limit
		"show_fps": false,                # frame counter in the top-left corner (FpsCounter)
		"ui_scale": 1.0,
		"cursor": "themed",               # "themed" (the game's cursors) or "system"
		"cursor_size": 32,                # pixels
	},
	"graphics": {                         # see GraphicsQuality (systems/graphics/graphics_quality.gd)
		"quality": "high",                # "low" / "medium" / "high" preset, or "custom"
		"render_scale": 1.0,              # share of the window the 3D world is drawn at
		"shadows": "all",                 # "off", "sun" or "all" (sun + the player's light)
		"effect_lights": "all",           # skill flash lights: "none", "few" or "all"
		"glow": true,
		"tile_detail": "full",            # "simple" or "full" floor / wall patterns
		"damage_numbers_max": 60,
		"retro_filter": "full",           # "off", "light" (no glow / colour bleed) or "full"
	},
	"audio": {
		"master": 1.0,
		"music": 0.8,
		"effects": 1.0,
		"ui": 1.0,
		"mute_in_background": true,
	},
	"gameplay": {
		"enemy_damage_numbers": true,
		"player_damage_numbers": true,
		"item_labels": "hold",            # "hold" (while the pickup key is held) or "always"
		"loot_filter": "all",             # "all", "magic" (hide normal) or "rare" (hide normal + magic)
		"enemy_info": true,               # name / life plate when hovering an enemy
		"auto_bind_skills": true,         # new skill gems go on a free hotkey
		"hud_shake": true,                # life bar shakes when you are hit
		"aim_line": true,                 # line on the ground showing where ranged skills will go
	},
	# Not shown in the settings menu: remembered from play
	"camera": {
		"zoom": 0.0,                      # camera size from the mouse wheel (0 = the scene's size)
	},
	"layout": {
		"script_panes": {},               # SCRIPTING tab bars: "explorer" / "snippets" / "output" -> split_offset
	},
}

## Choices shown in the settings menu, in order.
const WINDOW_MODES := ["windowed", "borderless", "fullscreen"]
const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
const FPS_LIMITS := [0, 30, 60, 120, 144, 240]
const ITEM_LABEL_MODES := ["hold", "always"]
const LOOT_FILTERS := ["all", "magic", "rare"]
const CURSOR_MODES := ["themed", "system"]
const CURSOR_SIZES := [24, 32, 40, 48, 64]

## The game's cursors: which image each cursor shape uses, and its click point in the 64x64 image.
## Controls pick a shape with mouse_default_cursor_shape; drag and drop uses DRAG / CAN_DROP /
## FORBIDDEN automatically; EnemyHover switches to CROSS over an enemy.
const CURSOR_DIR := "res://assets/ui/cursors/"
const CURSORS := {
	Input.CURSOR_ARROW: ["cursor_pointer.png", Vector2(4, 4)],
	Input.CURSOR_POINTING_HAND: ["cursor_hand.png", Vector2(4, 4)],
	Input.CURSOR_DRAG: ["cursor_grab.png", Vector2(32, 32)],
	Input.CURSOR_CAN_DROP: ["cursor_grab.png", Vector2(32, 32)],
	Input.CURSOR_MOVE: ["cursor_grab.png", Vector2(32, 32)],
	Input.CURSOR_FORBIDDEN: ["cursor_forbidden.png", Vector2(32, 32)],
	Input.CURSOR_CROSS: ["cursor_target.png", Vector2(32, 32)],
}

## Audio bus for each audio setting (see default_bus_layout.tres). Give sounds one of these buses.
const AUDIO_BUSES := {"master": "Master", "music": "Music", "effects": "Effects", "ui": "UI"}

var _values: Dictionary = {}
var _save_queued := false
var _focused := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	KeyBindings.load_saved()
	_apply_display(true)
	_apply_audio()
	GraphicsQuality.apply(get_tree())             # the tile shaders' detail; the rest when the game loads
	add_child(preload("res://scenes/ui/fps_counter.gd").new())   # FpsCounter
	get_tree().root.size_changed.connect(_apply_ui_scale)
	print("[Settings] window %s, UI laid out at %s" % [get_tree().root.size, get_tree().root.get_visible_rect().size])


# ---------- PUBLIC ----------
func get_value(section: String, key: String) -> Variant:
	return _values.get(section, {}).get(key, DEFAULTS.get(section, {}).get(key))


func set_value(section: String, key: String, value: Variant) -> void:
	if not _values.has(section):
		_values[section] = {}
	if _values[section].get(key) == value:
		return
	_values[section][key] = value
	match section:
		"display":
			_apply_display(key in ["window_mode", "resolution"])
		"audio":
			_apply_audio()
		"graphics":
			_set_graphics(key, value)
	changed.emit(section, key, value)
	_queue_save()


## QUALITY sets every graphics setting from its preset; changing one by hand makes it CUSTOM
## (or the preset it now matches). Then it all applies to what's on screen.
func _set_graphics(key: String, value: Variant) -> void:
	var g: Dictionary = _values["graphics"]
	if key == "quality":
		var preset: Dictionary = GraphicsQuality.PRESETS.get(value, {})
		for k in preset:
			if g.get(k) != preset[k]:
				g[k] = preset[k]
				changed.emit("graphics", k, preset[k])
	else:
		var q := GraphicsQuality.matching_preset()
		if g.get("quality") != q:
			g["quality"] = q
			changed.emit("graphics", "quality", q)
	GraphicsQuality.apply(get_tree())


## Puts a whole section back to its defaults.
func reset_section(section: String) -> void:
	for key in DEFAULTS.get(section, {}):
		set_value(section, key, DEFAULTS[section][key])


## Keeps `target.property` equal to a setting: now, and whenever the setting changes.
## Stops automatically when the target node leaves the tree.
func bind_to(target: Object, property: StringName, section: String, key: String) -> void:
	target.set(property, get_value(section, key))
	var callback := func(s: String, k: String, v: Variant) -> void:
		if s == section and k == key and is_instance_valid(target):
			target.set(property, v)
	changed.connect(callback)
	if target is Node:
		(target as Node).tree_exiting.connect(func() -> void:
			if changed.is_connected(callback):
				changed.disconnect(callback), CONNECT_ONE_SHOT)


static func parse_resolution(text: String) -> Vector2i:
	var parts := text.split("x")
	if parts.size() != 2:
		return BASE_SIZE
	return Vector2i(int(parts[0]), int(parts[1]))


## Resolutions that fit on this monitor (the current setting is always included).
func available_resolutions() -> Array[String]:
	var screen := DisplayServer.screen_get_size()
	var out: Array[String] = []
	for r in RESOLUTIONS:
		var size := parse_resolution(r)
		if size.x <= screen.x and size.y <= screen.y:
			out.append(r)
	var current: String = get_value("display", "resolution")
	if not (current in out):
		out.append(current)
	return out


## True while the game runs inside the editor's Game view, where the window can't be resized.
func is_embedded() -> bool:
	if Engine.has_method("is_embedded_in_editor") and Engine.call("is_embedded_in_editor"):
		return true
	# Fallback: the editor starts an embedded game with an --embedded command-line argument
	return OS.has_feature("editor") and "--embedded" in OS.get_cmdline_args()


# ---------- APPLYING ----------
func _apply_display(window_too: bool) -> void:
	_apply_ui_scale()
	_apply_cursor()
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if get_value("display", "vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("display", "max_fps"))
	if window_too and not is_embedded():
		_apply_window()
	_log_display()


func _apply_window() -> void:
	# Through the root Window node, not DisplayServer directly: the Window keeps its own copy of
	# the mode (fullscreen, from the project settings) and would put it back on its next update,
	# which is what kept WINDOWED from sticking.
	var win := get_window()
	match str(get_value("display", "window_mode")):
		"windowed":
			# Going straight from exclusive fullscreen to a window doesn't stick on Windows
			# (and the game starts in exclusive fullscreen): step through borderless first.
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				win.mode = Window.MODE_FULLSCREEN
				await get_tree().process_frame
			win.mode = Window.MODE_WINDOWED
			win.borderless = false
			_size_window()
			# Then make sure it stayed a window (asking the OS, not the Window node's own copy),
			# and size it again: leaving fullscreen, Windows can restore an old size a frame later.
			for attempt in WINDOWED_RETRIES:
				await get_tree().process_frame
				if str(get_value("display", "window_mode")) != "windowed":
					return                                  # the player picked something else meanwhile
				var now := DisplayServer.window_get_mode()
				if now != DisplayServer.WINDOW_MODE_WINDOWED and now != DisplayServer.WINDOW_MODE_MAXIMIZED:
					print("[Settings]   window went back to mode %d, setting windowed again (try %d)" % [now, attempt + 1])
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					win.mode = Window.MODE_WINDOWED
				_size_window()
		"fullscreen":
			win.borderless = false
			win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		_:   # borderless
			win.borderless = false
			win.mode = Window.MODE_FULLSCREEN


## Sizes the window to the resolution setting and centres it, keeping the whole window
## (title bar and borders included) inside the screen's usable area (above the taskbar).
## A resolution as big as the monitor gets the largest window that fits.
func _size_window() -> void:
	var win := get_window()
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var want := parse_resolution(str(get_value("display", "resolution")))
	var deco := win.get_size_with_decorations() - win.size
	deco = Vector2i(maxi(deco.x, 0), maxi(deco.y, 0))
	var size := Vector2i(mini(want.x, usable.size.x - deco.x), mini(want.y, usable.size.y - deco.y))
	win.size = size
	# Window.position places the inside of the window: offset it by the left border and title bar
	var corner := usable.position + (usable.size - (size + deco)) / 2
	win.position = corner + Vector2i(deco.x / 2, deco.y - deco.x / 2)


## Prints what the window really ended up as, a couple of frames after a display change, so the
## settings can be checked in the Output panel. Compare with the settings menu.
func _log_display() -> void:
	for i in WINDOWED_RETRIES + 3:              # after _apply_window has finished its retries
		await get_tree().process_frame
	var mode_names := {
		DisplayServer.WINDOW_MODE_WINDOWED: "windowed",
		DisplayServer.WINDOW_MODE_MINIMIZED: "minimized",
		DisplayServer.WINDOW_MODE_MAXIMIZED: "maximized",
		DisplayServer.WINDOW_MODE_FULLSCREEN: "borderless fullscreen",
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN: "exclusive fullscreen",
	}
	var vsync_names := {
		DisplayServer.VSYNC_DISABLED: "off",
		DisplayServer.VSYNC_ENABLED: "on",
		DisplayServer.VSYNC_ADAPTIVE: "adaptive",
		DisplayServer.VSYNC_MAILBOX: "mailbox",
	}
	var mode_now := DisplayServer.window_get_mode()
	var vsync_now := DisplayServer.window_get_vsync_mode()
	var want_mode := str(get_value("display", "window_mode"))
	var want_vsync: bool = get_value("display", "vsync")
	var want_modes := {"windowed": [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_MAXIMIZED],
		"borderless": [DisplayServer.WINDOW_MODE_FULLSCREEN],
		"fullscreen": [DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]}
	var problems: Array[String] = []
	if not is_embedded() and not (mode_now in want_modes.get(want_mode, [])):
		problems.append("window mode")
	if (vsync_now != DisplayServer.VSYNC_DISABLED) != want_vsync:
		problems.append("vsync")
	print("[Settings] display now: %s, window %s (screen %s, %.0f Hz), vsync %s, fps cap %s%s" % [
		mode_names.get(mode_now, "?"),
		DisplayServer.window_get_size(), DisplayServer.screen_get_size(),
		DisplayServer.screen_get_refresh_rate(),
		vsync_names.get(vsync_now, "?"),
		"none" if Engine.max_fps == 0 else str(Engine.max_fps),
		"  (inside the editor: window mode and size are not applied)" if is_embedded() else ""])
	print("[Settings]   run: %s, embedded %s, args %s" % ["editor" if OS.has_feature("editor") else "exported",
		is_embedded(), " ".join(OS.get_cmdline_args())])
	print("[Settings]   requested: %s, resolution %s, vsync %s  ->  %s" % [
		want_mode, get_value("display", "resolution"), "on" if want_vsync else "off",
		"OK" if problems.is_empty() else "MISMATCH: " + ", ".join(problems)])


## Lays the UI out at 1920x1080 and scales it to the window, times the UI size setting.
func _apply_ui_scale() -> void:
	var root := get_tree().root
	if root.content_scale_size != BASE_SIZE:
		root.content_scale_size = BASE_SIZE
	if root.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if root.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var factor := clampf(float(get_value("display", "ui_scale")), 0.5, 2.0)
	if not is_equal_approx(root.content_scale_factor, factor):
		root.content_scale_factor = factor


## Swaps the system cursors for the game's (or back), at the chosen size.
func _apply_cursor() -> void:
	var themed: bool = get_value("display", "cursor") == "themed"
	var size := clampi(int(get_value("display", "cursor_size")), 16, 128)
	for shape in CURSORS:
		if not themed:
			Input.set_custom_mouse_cursor(null, shape)
			continue
		var tex := load(CURSOR_DIR + CURSORS[shape][0]) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		var hotspot: Vector2 = CURSORS[shape][1] * size / 64.0
		Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), shape, hotspot)


func _apply_audio() -> void:
	for key in AUDIO_BUSES:
		var bus := AudioServer.get_bus_index(AUDIO_BUSES[key])
		if bus < 0:
			continue
		var v := clampf(float(get_value("audio", key)), 0.0, 1.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.0001)))
		var muted := v <= 0.001
		if key == "master" and not _focused and get_value("audio", "mute_in_background"):
			muted = true
		AudioServer.set_bus_mute(bus, muted)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_apply_audio()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		_apply_audio()


# ---------- SAVING ----------
func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if cfg.has_section_key(section, key):
				var v = cfg.get_value(section, key)
				if typeof(v) == typeof(DEFAULTS[section][key]) \
						or (DEFAULTS[section][key] is float and v is int):
					if not _values.has(section):
						_values[section] = {}
					_values[section][key] = v


## Sliders change many times a second, so saving waits a moment.
func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	get_tree().create_timer(0.5, true).timeout.connect(_save)


func _save() -> void:
	_save_queued = false
	var cfg := ConfigFile.new()
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			cfg.set_value(section, key, get_value(section, key))
	cfg.save(SAVE_PATH)
