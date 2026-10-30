class_name EnemyHover
extends Node
## Child of the player. Hover an enemy to see its name, rarity, health and modifier names.
##
## Same idea as PickupController:
##  - the mouse ray uses THIS node's viewport (the small pixelated 3D one);
##  - the plate lives in the HUD and is placed with the real window's mouse position,
##    so it is drawn at full resolution and stays sharp.
##
## Setup: add a plain Node named EnemyHover under the Player and attach this script.

@export var hud: Node                          # leave empty to use the Hud that holds LootLabels
@export var accent := Color("#00E5FF")
@export var font: Font                         # leave empty to use the Courier Prime font below
@export var font_scale: float = 1.0
## The plate is never narrower than this.
@export var plate_width: float = 240.0
## The plate grows with the name up to this width. Past it, the name wraps onto more lines.
@export var max_plate_width: float = 380.0

@export_group("Enemy data")
## Property on the enemy that holds its modifiers. An Array of strings, or of resources
## with display_name / id, both work.
@export var modifier_property: StringName = &"modifiers"
## Physics layers the mouse ray can hit. Must include the layer of the enemy's hover Area3D.
## Default is layer 6. Loot pickups use layer 5, so keep enemies off it or loot blocks the ray.
@export_flags_3d_physics var enemy_mask: int = 32
## true = the ray hits Area3D nodes (a hover area on the enemy). false = it hits physics bodies.
@export var hit_areas: bool = true
@export var ray_length: float = 200.0

@export_group("Behaviour")
@export var hide_while_pickup_held: bool = true    # F is for loot, so no enemy plate then

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const PLATE_OFFSET := Vector2(24, 24)              # from the mouse pointer
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_LIFE := Color(1.0, 0.30, 0.37)

var _plate: Plate
var _hovered: Node3D
var _font: Font

@onready var _player: Node3D = get_parent()
## Settings (Gameplay tab): show the name / life plate when hovering an enemy.
var enabled := true
## The cursor turns into a target crosshair over an enemy (Settings > Display > cursor).
var _targeting := false
var _world_view: Control


func _ready() -> void:
	Settings.bind_to(self, &"enabled", "gameplay", "enemy_info")
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_plate = Plate.new()
	_plate.setup(accent, _font, font_scale, plate_width, max_plate_width)
	_add_plate_to_hud.call_deferred()


func _add_plate_to_hud() -> void:
	if hud == null:
		var overlay := get_tree().get_first_node_in_group("loot_labels")
		if overlay != null:
			hud = overlay.get_parent()
	if hud == null:
		push_warning("EnemyHover: no HUD found (assign the Hud export). " \
			+ "Falling back to the 3D viewport, so the plate will look pixelated.")
		hud = self
	hud.add_child(_plate)


func _process(_delta: float) -> void:
	if _plate == null or not _plate.is_inside_tree():
		return

	var enemy: Node3D = null
	var blocked := not enabled or (hide_while_pickup_held and Input.is_action_pressed(&"pickup"))
	if not blocked and not _ui_under_mouse():
		enemy = _enemy_under_mouse()

	_set_target_cursor(enemy != null)
	if enemy == null:
		_hovered = null
		_plate.hide_plate()
		return

	var health := enemy.get("health") as HealthComponent
	if enemy != _hovered:                              # new target: rebuild the text once
		_hovered = enemy
		_plate.set_enemy(_enemy_name(enemy), _enemy_rarity(enemy), _modifier_names(enemy))
	_plate.set_health(health.current_health, _max_health(health))   # live every frame
	_place_plate()


## The 3D view is a SubViewportContainer covering the screen, so its cursor shape is the one
## shown over the world. Switch it to the crosshair while an enemy is under the mouse.
func _set_target_cursor(on: bool) -> void:
	if on == _targeting:
		return
	_targeting = on
	if _world_view == null:
		_world_view = get_tree().current_scene.find_child("SubViewportContainer", true, false) as Control
	var shape := Control.CURSOR_CROSS if on else Control.CURSOR_ARROW
	if _world_view != null:
		_world_view.mouse_default_cursor_shape = shape
	Input.set_default_cursor_shape(shape as Input.CursorShape)


func _place_plate() -> void:
	var ui_viewport := _plate.get_viewport()
	var mouse := ui_viewport.get_mouse_position()
	var screen := ui_viewport.get_visible_rect().size
	var pos := mouse + PLATE_OFFSET
	if pos.x + _plate.size.x > screen.x - 8.0:
		pos.x = mouse.x - PLATE_OFFSET.x - _plate.size.x
	pos.y = clampf(pos.y, 8.0, maxf(8.0, screen.y - _plate.size.y - 8.0))
	_plate.position = pos


## A panel (inventory, skills menu...) under the mouse wins. The full-screen
## SubViewportContainer is always "hovered", so it doesn't count.
func _ui_under_mouse() -> bool:
	var hovered := _plate.get_viewport().gui_get_hovered_control()
	return hovered != null and not (hovered is SubViewportContainer)


func _enemy_under_mouse() -> Node3D:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * ray_length
	var query := PhysicsRayQueryParameters3D.create(from, to, enemy_mask)
	query.collide_with_areas = hit_areas
	query.collide_with_bodies = not hit_areas
	if _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	# Walk up from whatever was hit to the node that owns the HealthComponent
	var n := hit.get("collider") as Node
	while n != null:
		if n is Node3D and n.get("health") is HealthComponent:
			var h := n.get("health") as HealthComponent
			return n as Node3D if h.current_health > 0.0 else null    # corpses don't count
		n = n.get_parent()
	return null


func _max_health(health: HealthComponent) -> float:
	if health.stats != null:
		return health.stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	return health.current_health


func _enemy_name(enemy: Node) -> String:
	var n = enemy.get("display_name")
	return str(n) if n != null and str(n) != "" else String(enemy.name)


func _enemy_rarity(enemy: Node) -> String:
	var r = enemy.get("rarity")
	return str(r) if r != null and str(r) != "" else "normal"


func _modifier_names(enemy: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var mods = enemy.get(modifier_property)
	if not (mods is Array):
		return out
	for m in mods:
		if m is String or m is StringName:
			out.append(String(m).capitalize())
		elif m is Object:
			var label = m.get("display_name")
			if label == null or str(label) == "":
				label = m.get("display_name_prefix")      # your EnemyModifierDefinition's name field
			if label == null or str(label) == "":
				label = m.get("name")
			if label == null or str(label) == "":
				label = str(m.get("id")).capitalize() if m.get("id") != null else ""
			if label == null or str(label) == "":
				label = m.resource_name if m is Resource else ""
			if str(label) != "":
				out.append(str(label))
	return out


func _exit_tree() -> void:
	_set_target_cursor(false)
	if _plate != null and is_instance_valid(_plate):
		_plate.queue_free()               # it lives in the HUD, so clean it up with the player


# ---------- THE PLATE ----------
class Plate extends PanelContainer:
	var accent := Color.WHITE
	var font: Font
	var font_scale := 1.0
	var plate_width := 240.0
	var max_width := 380.0

	var _style: StyleBoxFlat
	var _name_label: Label
	var _sub_label: Label
	var _bar: Bar
	var _mods_box: VBoxContainer

	func setup(p_accent: Color, p_font: Font, p_scale: float, p_width: float, p_max: float) -> void:
		accent = p_accent
		font = p_font
		font_scale = p_scale
		plate_width = p_width
		max_width = maxf(p_max, p_width)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		custom_minimum_size.x = plate_width

		_style = StyleBoxFlat.new()
		_style.bg_color = Color(0.02, 0.05, 0.09, 0.94)
		_style.border_color = Color(accent, 0.8)
		_style.set_border_width_all(1)
		_style.corner_radius_top_right = 10
		_style.corner_radius_bottom_left = 10
		_style.content_margin_left = 12
		_style.content_margin_right = 12
		_style.content_margin_top = 10
		_style.content_margin_bottom = 10
		add_theme_stylebox_override("panel", _style)

		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 4)
		add_child(box)

		_name_label = _label("", 20, Color.WHITE)
		_sub_label = _label("", 13, COL_DIM)
		box.add_child(_name_label)
		box.add_child(_sub_label)

		_bar = Bar.new()
		_bar.font = font if font else ThemeDB.fallback_font
		_bar.font_size = roundi(13 * font_scale)
		_bar.col = COL_LIFE
		_bar.custom_minimum_size = Vector2(plate_width - 24.0, 22.0 * font_scale)
		box.add_child(_bar)

		_mods_box = VBoxContainer.new()
		_mods_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mods_box.add_theme_constant_override("separation", 2)
		box.add_child(_mods_box)

	func set_enemy(enemy_name: String, rarity: String, mods: PackedStringArray) -> void:
		var col: Color = LootPickup.RARITY_COLORS.get(rarity, LootPickup.RARITY_COLORS["normal"])
		_name_label.text = enemy_name
		_name_label.add_theme_color_override("font_color", col)
		_sub_label.text = rarity.to_upper()
		_sub_label.add_theme_color_override("font_color", col)
		_style.border_color = Color(col if rarity != "normal" else accent, 0.8)

		for child in _mods_box.get_children():
			_mods_box.remove_child(child)
			child.queue_free()
		# Width: as wide as the longest line needs, but never past max_width
		var pad := 24.0                                    # the panel's left + right margins
		var f: Font = font if font else ThemeDB.fallback_font
		var widest := f.get_string_size(enemy_name, HORIZONTAL_ALIGNMENT_LEFT, -1,
			roundi(20 * font_scale)).x
		for m in mods:
			widest = maxf(widest, f.get_string_size("> " + m, HORIZONTAL_ALIGNMENT_LEFT, -1,
				roundi(15 * font_scale)).x)
		var width := clampf(widest + pad + 4.0, plate_width, max_width)
		var inner := width - pad

		# Wrapping labels need a real width up front, or they stack one word per line
		custom_minimum_size.x = width
		_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_name_label.custom_minimum_size.x = inner
		_bar.custom_minimum_size.x = inner
		for m in mods:
			var l := _label("> " + m, 15, COL_TEXT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = inner
			_mods_box.add_child(l)
		_mods_box.visible = not mods.is_empty()

		visible = true
		size = Vector2(width, 0.0)              # shrink to the new content
		reset_size.call_deferred()

	func set_health(current: float, maximum: float) -> void:
		_bar.set_values(current, maximum)

	func hide_plate() -> void:
		visible = false

	func _label(text: String, fsize: int, col: Color) -> Label:
		var l := Label.new()
		l.text = text
		if font:
			l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", roundi(fsize * font_scale))
		l.add_theme_color_override("font_color", col)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return l


## Segmented health bar with "current / max" over it.
class Bar extends Control:
	var cur := 0.0
	var maxv := 1.0
	var col := Color.RED
	var font: Font
	var font_size := 13

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(c: float, m: float) -> void:
		if is_equal_approx(c, cur) and is_equal_approx(m, maxv):
			return
		cur = c
		maxv = maxf(m, 1.0)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.45))
		var frac := clampf(cur / maxv, 0.0, 1.0)
		draw_rect(Rect2(2, 2, (w - 4.0) * frac, h - 4.0), Color(col, 0.9))
		for i in range(1, 10):                                   # segment ticks
			var x := w * i / 10.0
			draw_line(Vector2(x, 2), Vector2(x, h - 2), Color(0, 0, 0, 0.45), 1.0)
		draw_rect(Rect2(0, 0, w, h), Color(col, 0.85), false, 1.0)
		var shown_max := roundi(maxv)
		var shown_cur := mini(ceili(cur), shown_max)        # never show more than the maximum
		var text := "%d / %d" % [shown_cur, shown_max]
		draw_string(font, Vector2(1, h - 5.0), text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size,
			Color(0, 0, 0, 0.8))                                 # shadow
		draw_string(font, Vector2(0, h - 6.0), text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size,
			Color.WHITE)
