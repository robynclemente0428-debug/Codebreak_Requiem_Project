class_name LockBanner
extends Control
## Banner for boss locks, bottom centre over the skill bar (PortLock, EchoLock): what the lock just
## said in its colour, the lock's name, a one-line hint, and a bar draining while the port is open.
## Kept quiet: a small translucent strip sized to its text, the hint only for the lock's first few
## messages (the hover plate and quest tracker keep it), and a short hold. Only act bosses use it:
## an ordinary enemy's lock (an Echo Wisp's ECHO) says the same on its tag (LockTags), which
## flashes and shows what it has learned, so a pack of them doesn't keep the banner up.
##
## Locks report through EnemyTrait.say() / pop(), which call LockBanner.report(). The hint
## comes from the lock script's LOCK_NAME and HINT constants; hint_for_enemy() gives the same
## text to the quest tracker, so both always agree.
## AreaManager adds one to the HUD layer.

const COL_BG := Color(0.02, 0.05, 0.08, 0.6)
const COL_TITLE := Color("#00E5FF")
const COL_HINT := Color(0.7, 0.8, 0.84)
const COL_OPEN := Color(0.3, 0.95, 1.0)
const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
## Seconds the banner stays up after the lock's last message (longer while the port is open).
const HOLD := 3.5
## Its bottom edge sits this far above the screen's bottom: just over the skill bar, below the
## player, clear of the toasts and tutorial hints that use the top of the screen.
const BOTTOM := 190.0
## It's as wide as its text, between these; the hint wraps at MAX_WIDTH.
const MIN_WIDTH := 300.0
const MAX_WIDTH := 520.0
## The hint shows with a lock's first this-many messages, then only the message does.
const HINT_MESSAGES := 3
## How bright a new message flashes (1 = no flash).
const FLASH := 1.4

var _panel: PanelContainer
var _style: StyleBoxFlat
var _title: Label
var _message: Label
var _hint: Label
var _bar: Bar
var _lock: Node                       # the lock (an EnemyTrait) that spoke last
var _left := 0.0                      # seconds until it hides
var _tween: Tween
var _told := {}                       # lock instance id -> messages shown (the hint stops after HINT_MESSAGES)
static var _hints := {}               # enemy id -> {"name", "hint"} (hint_for_enemy cache)


func _enter_tree() -> void:
	add_to_group("lock_banner")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font: Font = load(DEFAULT_FONT) if ResourceLoader.exists(DEFAULT_FONT) else null
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = COL_BG
	_style.set_border_width_all(1)
	_style.border_color = COL_TITLE
	_style.content_margin_left = 14
	_style.content_margin_right = 14
	_style.content_margin_top = 6
	_style.content_margin_bottom = 7
	_panel.add_theme_stylebox_override("panel", _style)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_title = _label(font, 12, Color(COL_TITLE, 0.75))
	_message = _label(font, 20, Color.WHITE)
	_message.add_theme_constant_override("outline_size", 5)
	_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint = _label(font, 13, COL_HINT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bar = Bar.new()
	_bar.custom_minimum_size = Vector2(0, 4)
	for c in [_title, _message, _hint, _bar]:
		box.add_child(c)
	_panel.visible = false
	_panel.modulate.a = 0.0


## A lock said something (EnemyTrait.say / pop). Ignored for traits that aren't locks.
static func report(trait_: Node, text: String, col: Color) -> void:
	if trait_ == null or not trait_.is_inside_tree():
		return
	var info := lock_info(trait_.get_script())
	if info.is_empty():
		return
	if trait_.has_method("_lock_const") and not bool(trait_.call("_lock_const", "BANNER", true)):
		return                            # a lock that pops on every hit (Firewalled): its tag is enough
	var owner_enemy = trait_.get("enemy")
	if owner_enemy is Node and not (owner_enemy as Node).get_meta(&"act_boss", false):
		return                            # an ordinary enemy's lock: its tag says it (LockTags)
	var banner := trait_.get_tree().get_first_node_in_group("lock_banner") as LockBanner
	if banner != null:
		banner._show(trait_, info, text, col)


## {"name", "hint"} for a lock script (its LOCK_NAME / HINT constants), or {} if it isn't one.
static func lock_info(script: Script) -> Dictionary:
	if script == null:
		return {}
	var consts := script.get_script_constant_map()
	if not consts.has("LOCK_NAME"):
		return {}
	return {"name": str(consts["LOCK_NAME"]), "hint": str(consts.get("HINT", ""))}


## The lock hint for an enemy id (its EnemyDefinition's innate lock), or {} if it has none.
## The quest tracker shows it under a "Defeat ..." objective.
static func hint_for_enemy(id: String) -> Dictionary:
	if _hints.has(id):
		return _hints[id]
	var out := {}
	var path := "res://data/enemies/%s.tres" % id
	if ResourceLoader.exists(path):
		var def := load(path) as EnemyDefinition
		if def != null:
			for s in def.innate_traits:
				out = lock_info(s)
				if not out.is_empty():
					break
	_hints[id] = out
	return out


func _show(trait_: Node, info: Dictionary, text: String, col: Color) -> void:
	_lock = trait_
	_title.text = "// %s //" % info["name"]
	_message.text = text
	_message.add_theme_color_override("font_color", Color(col, 1.0))
	var told: int = _told.get(trait_.get_instance_id(), 0) + 1
	_told[trait_.get_instance_id()] = told
	_hint.text = info["hint"]
	_hint.visible = info["hint"] != "" and not _is_open() and told <= HINT_MESSAGES
	_style.border_color = Color(col, 0.55)
	_left = HOLD
	_layout()
	if not _panel.visible or _panel.modulate.a < 1.0:
		_panel.visible = true
		_fade(1.0)
	# A quick flash on every new message, so a change is seen from the corner of the eye
	_message.modulate = Color(FLASH, FLASH, FLASH)
	create_tween().tween_property(_message, "modulate", Color.WHITE, 0.3)


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	if _lock == null or not is_instance_valid(_lock) or not _lock.is_inside_tree():
		_left = minf(_left, 0.5)              # the boss is gone (dead, area left)
	var open := _is_open()
	_bar.visible = open
	if open:
		_bar.fraction = _lock.call("open_fraction")
		_bar.queue_redraw()
		_left = maxf(_left, 1.0)              # stays up while the port is open
	_left -= delta
	if _left <= 0.0 and _panel.modulate.a >= 1.0:
		_fade(0.0)
	_layout()


func _is_open() -> bool:
	return _lock != null and is_instance_valid(_lock) and _lock.has_method("open_fraction") \
		and _lock.has_method("is_open") and bool(_lock.call("is_open"))


func _layout() -> void:
	var font := _message.get_theme_font("font")
	var text_w := 0.0
	if font != null:
		text_w = maxf(font.get_string_size(_message.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x,
				font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	var width := clampf(text_w + 28.0, MIN_WIDTH, MAX_WIDTH)
	if _hint.visible:
		width = MAX_WIDTH                       # room for the hint to wrap
	_hint.custom_minimum_size.x = width - 28.0
	var want := _panel.get_combined_minimum_size()
	_panel.size = Vector2(maxf(want.x, width), want.y)
	_panel.position = Vector2((size.x - _panel.size.x) * 0.5, size.y - BOTTOM - _panel.size.y).round()


func _fade(to: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", to, 0.18 if to > 0.0 else 0.5)
	if to <= 0.0:
		_tween.finished.connect(func() -> void: _panel.visible = false)


func _label(font: Font, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	return l


## The open-port countdown: a cyan bar that drains.
class Bar extends Control:
	var fraction := 1.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(LockBanner.COL_OPEN, 0.18))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(fraction, 0.0, 1.0), size.y)), LockBanner.COL_OPEN)
