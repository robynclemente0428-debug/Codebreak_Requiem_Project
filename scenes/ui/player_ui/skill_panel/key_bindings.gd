class_name KeyBindings
extends RefCounted
## Lets the player change which key or mouse button triggers an Input Map action, and
## remembers the choice between sessions in user://keybinds.cfg.
##
## Keys are stored as a "signature": the physical keycode for a key (always above 0),
## or the negative button number for a mouse button (-1 = left, -2 = right, -3 = middle).
## Gamepad events on the same action are left alone.

const SAVE_PATH := "user://keybinds.cfg"
const SECTION := "keys"

static var _loaded := false
static var _overrides: Dictionary = {}   # action -> signature the player chose (0 = unbound)
static var _defaults: Dictionary = {}    # action -> signature it had before the player changed it


## Applies the saved choices. Safe to call from several places, it only runs once.
static func load_saved() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or not cfg.has_section(SECTION):
		return                                  # nothing saved yet, or every key was reset
	for key in cfg.get_section_keys(SECTION):
		var action := StringName(key)
		if InputMap.has_action(action):
			_set_signature(action, int(cfg.get_value(SECTION, key, 0)))


## Gives `action` the key or mouse button in `event`. Returns "" on success, or a short
## message for the player when the change is refused.
##   swappable: actions that trade keys when the new key is already used by one of them
##   reserved:  keycodes nobody may bind (menu keys, escape)
static func rebind(action: StringName, event: InputEvent, swappable: Array, reserved: Array[int]) -> String:
	var sig := signature(event)
	if sig == 0:
		return "THAT INPUT CANNOT BE USED"
	if sig > 0 and sig in reserved:
		return "THAT KEY IS RESERVED"

	for other in InputMap.get_actions():
		if other == action or String(other).begins_with("ui_"):
			continue
		if not has_signature(other, sig):
			continue
		if other in swappable:
			var mine := current_signature(action)        # the other skill takes over my old key
			_set_signature(other, mine)
		else:
			return "KEY ALREADY USED BY %s" % String(other).to_upper().replace("_", " ")

	_set_signature(action, sig)
	_save()
	return ""


## Puts every action the player changed back to its original key.
static func reset_all() -> void:
	for action in _defaults.keys():
		_set_signature(action, int(_defaults[action]))
	_overrides.clear()
	_save()


static func signature(event: InputEvent) -> int:
	if event is InputEventKey:
		var code := int(event.physical_keycode)
		return code if code != 0 else int(event.keycode)
	if event is InputEventMouseButton:
		return -int(event.button_index)
	return 0


static func current_signature(action: StringName) -> int:
	for e in InputMap.action_get_events(action):
		var sig := signature(e)
		if sig != 0:
			return sig
	return 0


static func has_signature(action: StringName, sig: int) -> bool:
	for e in InputMap.action_get_events(action):
		if signature(e) == sig:
			return true
	return false


static func make_event(sig: int) -> InputEvent:
	if sig < 0:
		var m := InputEventMouseButton.new()
		m.button_index = (-sig) as MouseButton
		return m
	var k := InputEventKey.new()
	k.physical_keycode = sig as Key
	return k


## Replaces the keyboard and mouse events of an action, keeping everything else (gamepad).
## The new event goes first so labels that read the first event show it.
static func _set_signature(action: StringName, sig: int) -> void:
	if not _defaults.has(action):
		_defaults[action] = current_signature(action)
	var kept: Array[InputEvent] = []
	for e in InputMap.action_get_events(action):
		if not (e is InputEventKey or e is InputEventMouseButton):
			kept.append(e)
	InputMap.action_erase_events(action)
	if sig != 0:
		InputMap.action_add_event(action, make_event(sig))
	for e in kept:
		InputMap.action_add_event(action, e)
	_overrides[action] = sig


static func _save() -> void:
	var cfg := ConfigFile.new()
	for action in _overrides:
		cfg.set_value(SECTION, String(action), int(_overrides[action]))
	cfg.save(SAVE_PATH)
