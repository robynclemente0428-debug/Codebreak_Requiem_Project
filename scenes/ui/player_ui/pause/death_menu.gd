class_name DeathMenu
extends CanvasLayer
## "YOU DIED" overlay with Respawn and Main Menu. Same look as PauseMenu (reuses its Frame/ScanOverlay).
##
## Setup: add a CanvasLayer to main.tscn (next to PauseMenu), attach this script, then in the Inspector set
## Area Manager and Main Menu Scene. Which SpawnMarker you respawn at is set on the dungeon itself
## (Respawn Spawn Id), so each dungeon can have its own.

@export var area_manager: Node                        # your AreaManager node
@export_file("*.tscn") var main_menu_scene: String = ""
## Off = teleport back to the spawn marker and keep the dungeon as it is.
## On = reload the dungeon (new enemies, loot and layout) and spawn at the marker.
@export var reload_area: bool = false
@export var show_delay: float = 1.5                   # lets the death animation play first
@export var font: Font
@export var accent := Color("#FF4D5E")
@export_range(0.0, 1.0, 0.01) var dim_opacity: float = 0.6
@export var panel_width: float = 420.0

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_DIM := Color(0.85, 0.78, 0.80)

var _font: Font
var _open := false
var _player: Player
var _root: Control
var _dim: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = 90                                        # under the pause menu (100), above the HUD
	add_to_group("death_menu")
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _open


## Called by Player._on_died().
func show_death(p: Player) -> void:
	if _open:
		return
	_open = true
	_player = p
	await get_tree().create_timer(show_delay).timeout
	if not _open:
		return
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.modulate.a = 0.0
	_root.visible = true
	_fade(1.0)


func _hide() -> void:
	_open = false
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade(0.0)


func _fade(target: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", target, 0.25)
	if target <= 0.0:
		_tween.finished.connect(func() -> void:
			if not _open:
				_root.visible = false)


func _on_respawn() -> void:
	if not _open:
		return
	var am: Node = area_manager
	if am == null:
		am = get_tree().get_first_node_in_group("area_manager")
	if am == null or not am.has_method("respawn"):
		push_error("DeathMenu: no AreaManager with a respawn() method found")
		return
	_hide()
	am.respawn(reload_area)


func _on_main_menu() -> void:
	if not _open:
		return
	if main_menu_scene == "":
		push_warning("DeathMenu: set Main Menu Scene in the Inspector")
		return
	_open = false
	SaveManager.save_party()
	SaveManager.end_session()
	get_tree().paused = false
	get_tree().change_scene_to_file(main_menu_scene)


# ---------- UI ----------
func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_dim = ColorRect.new()
	_dim.color = Color(0.12, 0, 0, dim_opacity)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var frame := PauseMenu.Frame.new()
	frame.accent = accent
	_root.add_child(frame)
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -panel_width * 0.5
	frame.offset_right = panel_width * 0.5
	frame.offset_top = -150.0
	frame.offset_bottom = 150.0

	var margin := MarginContainer.new()
	frame.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := _label("YOU DIED", 38, accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var rule := ColorRect.new()
	rule.color = Color(accent, 0.5)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	col.add_child(spacer)

	var respawn_btn := _menu_button("RESPAWN")
	respawn_btn.pressed.connect(_on_respawn)
	col.add_child(respawn_btn)
	var menu_btn := _menu_button("MAIN MENU")
	menu_btn.pressed.connect(_on_main_menu)
	col.add_child(menu_btn)

	var overlay := PauseMenu.ScanOverlay.new()
	frame.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.focus_mode = Control.FOCUS_NONE
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", COL_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _flat(Color(accent, 0.06), Color(accent, 0.35), 1))
	b.add_theme_stylebox_override("hover", _flat(Color(accent, 0.16), Color(accent, 0.8), 1))
	b.add_theme_stylebox_override("pressed", _flat(Color(accent, 0.28), accent, 2))
	b.add_theme_stylebox_override("hover_pressed", _flat(Color(accent, 0.28), accent, 2))
	return b


func _label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", fsize)
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
