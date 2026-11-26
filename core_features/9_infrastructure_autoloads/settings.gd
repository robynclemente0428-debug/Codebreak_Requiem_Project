extends Node

signal changed(section: String, key: String, value: Variant)

const SAVE_PATH := "user://settings.cfg"
const BASE_SIZE := Vector2i(1920, 1080)
const WINDOWED_RETRIES := 4

const DEFAULTS := {
	"display": {
		"window_mode": "borderless",
		"resolution": "1920x1080",
		"vsync": true,
		"max_fps": 0,
		"show_fps": false,
		"ui_scale": 1.0,
		"cursor": "themed",
		"cursor_size": 32,
	},
	"graphics": {
		"quality": "high",
		"render_scale": 1.0,
		"shadows": "all",
		"effect_lights": "all",
		"glow": true,
		"tile_detail": "full",
		"damage_numbers_max": 60,
		"retro_filter": "full",
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
		"item_labels": "hold",
		"loot_filter": "all",
		"enemy_info": true,
		"auto_bind_skills": true,
		"hud_shake": true,
		"aim_line": true,
		"script_tips": true,
	},
	"camera": {
		"zoom": 0.0,
	},
	"layout": {
		"script_panes": {},
		"snippet_folds": {},
	},
}

const WINDOW_MODES := ["windowed", "borderless", "fullscreen"]
const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
const FPS_LIMITS := [0, 30, 60, 120, 144, 240]
const ITEM_LABEL_MODES := ["hold", "always"]
const LOOT_FILTERS := ["all", "magic", "rare"]
const CURSOR_MODES := ["themed", "system"]
const CURSOR_SIZES := [24, 32, 40, 48, 64]

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
	GraphicsQuality.apply(get_tree())
	add_child(preload("res://scenes/ui/fps_counter.gd").new())
	get_tree().root.size_changed.connect(_apply_ui_scale)
	print("[Settings] window %s, UI laid out at %s" % [get_tree().root.size, get_tree().root.get_visible_rect().size])


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


func reset_section(section: String) -> void:
	for key in DEFAULTS.get(section, {}):
		set_value(section, key, DEFAULTS[section][key])


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


func is_embedded() -> bool:
	if Engine.has_method("is_embedded_in_editor") and Engine.call("is_embedded_in_editor"):
		return true
	return OS.has_feature("editor") and "--embedded" in OS.get_cmdline_args()


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
	var win := get_window()
	match str(get_value("display", "window_mode")):
		"windowed":
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				win.mode = Window.MODE_FULLSCREEN
				await get_tree().process_frame
			win.mode = Window.MODE_WINDOWED
			win.borderless = false
			_size_window()
			for attempt in WINDOWED_RETRIES:
				await get_tree().process_frame
				if str(get_value("display", "window_mode")) != "windowed":
					return
				var now := DisplayServer.window_get_mode()
				if now != DisplayServer.WINDOW_MODE_WINDOWED and now != DisplayServer.WINDOW_MODE_MAXIMIZED:
					print("[Settings]   window went back to mode %d, setting windowed again (try %d)" % [now, attempt + 1])
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					win.mode = Window.MODE_WINDOWED
				_size_window()
		"fullscreen":
			win.borderless = false
			win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		_:
			win.borderless = false
			win.mode = Window.MODE_FULLSCREEN


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
	var corner := usable.position + (usable.size - (size + deco)) / 2
	win.position = corner + Vector2i(deco.x / 2, deco.y - deco.x / 2)


func _log_display() -> void:
	for i in WINDOWED_RETRIES + 3:
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
