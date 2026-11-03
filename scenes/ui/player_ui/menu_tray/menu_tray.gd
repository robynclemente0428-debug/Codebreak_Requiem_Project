class_name MenuTray
extends Control
## A button for every panel, for players who'd rather click than remember keys. An arrow tab
## sits on the minimap's left edge; clicking it slides the buttons out (and back in).
##   BACKPACK [I]  SKILLS [K]  CHARACTER [C]  QUESTS [J]  MAP [TAB]  WAYPOINTS [U]  MENU [ESC]
## Each button toggles its panel like its key does, shows that key, and lights up while the
## panel is open. The tray follows the minimap (and its [ ] opacity); with the minimap hidden
## it moves into the corner. Add it to the HUD after the MiniMap.

@export var font: Font
@export var accent := Color("#00E5FF")
@export var button_width: float = 170.0
@export var gap: float = 8.0                   # between the tab and the minimap
@export var margin_right: float = 32.0         # in the corner, when the minimap is hidden
@export var margin_top: float = 32.0
@export var slide_time: float = 0.2
@export var base_font_size: int = 14

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const TAB_SIZE := Vector2(24, 64)

## Open or not, for the rest of the session.
static var expanded := false

var _font: Font
var _tab: Button
var _tray: PanelContainer
var _buttons := {}                  # id -> Button
var _slide := 0.0                   # 0 = tucked in, 1 = out
var _tween: Tween
var _minimap: Control


func _enter_tree() -> void:
	add_to_group("menu_tray")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_build()
	_slide = 1.0 if expanded else 0.0
	_update_tab()


# ---------- THE PANELS ----------
## id, label, the node's group, and the key shown on the button.
func _entries() -> Array:
	return [
		["backpack", "BACKPACK", "inventory_panel", _key_of("inventory_panel", "I")],
		["skills", "SKILLS", "skill_panel", _key_of("skill_panel", "K")],
		["character", "CHARACTER", "character_panel", _key_of("character_panel", "C")],
		["quests", "QUESTS", "quest_log", "J"],
		["map", "MAP", "minimap", _key_of_map()],
		["waypoints", "WAYPOINTS", "waypoint_panel", GemText.key_label(WaypointPanel.ACTION)],
		["menu", "MENU", "", "ESC"],
	]


func _key_of(group: String, fallback: String) -> String:
	var n := get_tree().get_first_node_in_group(group)
	var k = n.get("toggle_key") if n != null else null
	return OS.get_keycode_string(int(k)) if k != null else fallback


func _key_of_map() -> String:
	var mm := get_tree().get_first_node_in_group("minimap")
	var k = mm.get("overlay_key") if mm != null else null
	return "TAB" if k == null or int(k) == KEY_TAB else OS.get_keycode_string(int(k))


func _pause_menu() -> PauseMenu:
	var found := get_tree().root.find_children("*", "PauseMenu", true, false)
	return found[0] as PauseMenu if not found.is_empty() else null


## What the button does: the same as the panel's key.
func _press(id: String) -> void:
	match id:
		"map":
			var mm := get_tree().get_first_node_in_group("minimap")
			if mm != null:
				mm.set_overlay(not mm.is_overlay_open())
		"menu":
			var pm := _pause_menu()
			if pm != null:
				pm.pause()
		_:
			for e in _entries():
				if e[0] == id:
					var panel := get_tree().get_first_node_in_group(e[2])
					if panel != null and panel.has_method("toggle"):
						panel.toggle()


func _is_open(id: String) -> bool:
	match id:
		"map":
			var mm := get_tree().get_first_node_in_group("minimap")
			return mm != null and mm.is_overlay_open()
		"menu":
			var pm := _pause_menu()
			return pm != null and pm.is_paused()
	for e in _entries():
		if e[0] == id:
			var panel := get_tree().get_first_node_in_group(e[2])
			return panel != null and panel.has_method("is_open") and panel.is_open()
	return false


# ---------- SLIDING ----------
func toggle() -> void:
	expanded = not expanded
	if expanded:
		_refresh_labels()                   # keys can be rebound, or made after we were built
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_slide", 1.0 if expanded else 0.0, slide_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_update_tab()


func _update_tab() -> void:
	_tab.tooltip_text = "Hide the menu buttons" if expanded else "Show a button for every menu"


func _process(_delta: float) -> void:
	if _minimap == null or not is_instance_valid(_minimap):
		_minimap = get_tree().get_first_node_in_group("minimap") as Control
	# Right edge: just left of the minimap. While it's hidden the quest tracker slides up into
	# its place, so then just left of the tracker; the corner only when neither is there.
	var screen := get_viewport_rect().size
	var right := screen.x - margin_right
	var tracker := get_tree().get_first_node_in_group("quest_tracker") as QuestTracker
	var tracker_panel: Control = tracker.tutorial_target()[0] if tracker != null and not tracker.tutorial_target().is_empty() else null
	if tracker_panel != null:
		right = tracker_panel.get_global_rect().position.x - gap
	var top := margin_top
	var docked := 0.0
	if _minimap != null and _minimap.has_method("docked_amount"):
		docked = _minimap.docked_amount()
		right = lerpf(right, _minimap.get_global_rect().position.x - gap, docked)
	_tab.position = Vector2(right - TAB_SIZE.x, top).round()
	if _tween != null and _tween.is_running():
		_tab.queue_redraw()                       # the arrow turns as the tray slides
	var tray_w := _tray.get_combined_minimum_size().x
	_tray.size = Vector2(tray_w, _tray.get_combined_minimum_size().y)
	_tray.position = Vector2(right - TAB_SIZE.x - 4.0 - tray_w * _slide, top).round()
	_tray.visible = _slide > 0.01
	_tray.modulate.a = _slide
	# Fade with the minimap's [ ] opacity, like the quest tracker
	var alpha: float = 1.0
	if _minimap != null and docked > 0.0 and _minimap.get("opacity") != null:
		alpha = _minimap.opacity
	_tab.modulate.a = alpha
	_tray.self_modulate.a = alpha
	if _tray.visible:
		for id in _buttons:
			_style_button(_buttons[id], _is_open(id))


# ---------- BUILDING ----------
func _build() -> void:
	_tray = PanelContainer.new()
	_tray.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.06, 0.09, 0.75)
	bg.border_color = Color(accent, 0.6)
	bg.border_width_left = 2
	bg.set_content_margin_all(6)
	_tray.add_theme_stylebox_override("panel", bg)
	add_child(_tray)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_tray.add_child(col)
	for e in _entries():
		var b := Button.new()
		b.custom_minimum_size = Vector2(button_width, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s  [%s]" % [e[1], e[3]]
		b.tooltip_text = "Open or close %s  [ %s ]" % [str(e[1]).to_lower(), e[3]]
		if _font:
			b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", base_font_size)
		b.pressed.connect(_press.bind(e[0]))
		_style_button(b, false)
		col.add_child(b)
		_buttons[e[0]] = b

	# The tab is a drawn arrow, no button box: see _draw_arrow
	_tab = Button.new()
	_tab.custom_minimum_size = TAB_SIZE
	_tab.size = TAB_SIZE
	_tab.focus_mode = Control.FOCUS_NONE
	_tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		_tab.add_theme_stylebox_override(state, empty)
	_tab.draw.connect(_draw_arrow)
	_tab.mouse_entered.connect(_tab.queue_redraw)
	_tab.mouse_exited.connect(_tab.queue_redraw)
	_tab.pressed.connect(toggle)
	add_child(_tab)


## A solid arrowhead with a soft glow behind it. It points left while
## the tray is tucked in ("pull it out") and turns to point right as the tray slides out.
func _draw_arrow() -> void:
	var c := TAB_SIZE * 0.5
	var angle := lerpf(PI, 0.0, _slide)              # PI = pointing left
	var hover := _tab.is_hovered()
	var col := Color.WHITE if hover else accent
	# Just the head, pointing right around (0, 0)
	var arrow := PackedVector2Array([Vector2(-7, -13), Vector2(9, 0), Vector2(-7, 13)])
	var shape := Transform2D(angle, c) * arrow
	var outline := shape.duplicate()
	outline.append(shape[0])                          # closed, for the glow around it
	for glow in [[7.0, 0.08], [4.0, 0.16]]:          # wider and fainter first
		_tab.draw_polyline(outline, Color(col, float(glow[1]) * (1.8 if hover else 1.0)), float(glow[0]), true)
	_tab.draw_colored_polygon(shape, col)


## Each button's text and tooltip, with the panel's current key.
func _refresh_labels() -> void:
	for e in _entries():
		var b: Button = _buttons.get(e[0])
		if b != null:
			b.text = "%s  [%s]" % [e[1], e[3]]
			b.tooltip_text = "Open or close %s  [ %s ]" % [str(e[1]).to_lower(), e[3]]


## Lit while its panel is open.
func _style_button(b: Button, lit: bool) -> void:
	if b.get_meta(&"lit", null) == lit:
		return
	b.set_meta(&"lit", lit)
	b.add_theme_color_override("font_color", accent if lit else COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		var strong: bool = lit or state != "normal"
		sb.bg_color = Color(accent, 0.22 if lit else (0.14 if state != "normal" else 0.04))
		sb.border_color = Color(accent, 0.9 if strong else 0.3)
		sb.set_border_width_all(1)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		b.add_theme_stylebox_override(state, sb)
