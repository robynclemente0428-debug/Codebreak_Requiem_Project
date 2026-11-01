class_name Minimap
extends Control
## Retro-futuristic dungeon minimap, styled to match CharacterPanel.
## Setup: add a plain Control under your HUD CanvasLayer, attach this script.
## It docks itself to the top-right corner and builds its UI in code.
##
## Needs two hooks:
##   1. Your player must be in the group "player" (or change player_group).
##   2. The dungeon calls bind_dungeon(director, grid_map, enemies_root) after generating.
##      Towns (TownArea) call it too, with {"town": true, "npcs": [...]}: no fog, NPCs marked.
##
## Quests: NPCs with a quest for you carry the same "!" / "+" as their name plate, and whatever
## an active quest still needs (the enemy to kill, the person to talk to, the key or its carrier,
## a ward beacon) gets a gold quest ring.
## Quest targets show anywhere on the map, even past the fog, and get an arrow on the rim when
## they're off the edge, so you can always find them.
##
## Keys: M shows/hides (slides in from the right like the character panel),
##       [ and ] change the overall opacity, - and = zoom out / in.
##       TAB opens the full-screen map: a see-through overlay over the whole HUD, centred on
##       you (- and = zoom it while it's open). The game keeps running underneath.

@export_group("Controls")
@export var toggle_key: Key = KEY_M
@export var opacity_down_key: Key = KEY_BRACKETLEFT
@export var opacity_up_key: Key = KEY_BRACKETRIGHT
@export var zoom_out_key: Key = KEY_MINUS
@export var zoom_in_key: Key = KEY_EQUAL
@export var overlay_key: Key = KEY_TAB
@export var player_group: StringName = &"players"
@export var forward_is_plus_z: bool = true       # true if your character faces +Z (Godot's default is -Z)

@export_group("Transparency")
@export_range(0.1, 1.0, 0.05) var opacity: float = 1.0:          # everything at once
	set(v):
		opacity = clampf(v, 0.1, 1.0)
		_apply_alpha()
@export_range(0.0, 1.0, 0.01) var bg_opacity: float = 0.55:      # dark panel behind the map
	set(v):
		bg_opacity = v
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var map_opacity: float = 1.0       # floors, walls and markers
@export_range(0.0, 1.0, 0.01) var frame_opacity: float = 1.0:    # glowing border
	set(v):
		frame_opacity = v
		queue_redraw()
@export var scanlines: bool = true

@export_group("Full-screen map (TAB)")
@export_range(0.0, 1.0, 0.01) var overlay_dim: float = 0.35         # dark tint over the game
@export_range(0.0, 1.0, 0.01) var overlay_map_opacity: float = 0.85  # floors, walls and markers
@export var overlay_cell_px: float = 12.0
@export var overlay_min_cell_px: float = 5.0
@export var overlay_max_cell_px: float = 30.0

@export_group("Layout")
@export var map_size := Vector2(300, 300)
@export var margin := Vector2(32, 32)
@export var cell_px: float = 8.0                 # on-screen pixels per dungeon cell (zoom)
@export var min_cell_px: float = 4.0
@export var max_cell_px: float = 18.0
@export var follow_dungeon_rotation: bool = true # auto-match the GridMap's Y rotation (-45 deg dungeon -> map turns +45)
@export var rotation_offset_deg: float = 0.0     # extra manual rotation on top of that
## On: the "N" always sits at the top of the map (the way the camera looks). Off: it points
## to the dungeon grid's own north, which turns with the map when the dungeon is rotated.
@export var north_at_top: bool = true
@export var font_scale: float = 1.0
@export var font: Font                           # empty = Courier Prime
@export var accent := Color("#00E5FF")

@export_group("Fog of war")
@export var fog_of_war: bool = true
@export var reveal_radius: int = 7               # cells revealed around the player
@export var enemy_detect_radius: float = 9.0     # enemies show only within this many cells

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const CHAMFER := 18.0
const CANVAS_INSET := Vector4(14.0, 32.0, 14.0, 28.0)    # left, top, right, bottom
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_ENEMY := Color(1.0, 0.30, 0.37)
const COL_PORTAL := Color(0.30, 1.0, 0.60)
const COL_NPC := Color(1.0, 0.82, 0.30)
const COL_QUEST := Color(1.0, 0.82, 0.30)    # quest targets: the quest tracker's gold
const COL_BG := Color(0.02, 0.05, 0.09)
## [neighbour direction, edge start, edge end] in cell units
const EDGES := [
	[Vector2i.UP, Vector2(0, 0), Vector2(1, 0)],
	[Vector2i.DOWN, Vector2(0, 1), Vector2(1, 1)],
	[Vector2i.LEFT, Vector2(0, 0), Vector2(0, 1)],
	[Vector2i.RIGHT, Vector2(1, 0), Vector2(1, 1)],
]

var _font: Font
var _director: DungeonDirector
var _grid_map: GridMap
var _enemies_root: Node3D
var _player: Node3D

var _explored := {}                    # Vector2i -> true
var _town := false                     # a town: everything revealed, no hostiles
var _dungeon_overlay_px := -1.0        # the player's full-map zoom for dungeons, kept while in town
var _npcs: Array = []                  # Node3D (DialogueNPC) shown as gold markers
var _last_cell := Vector2i(-99999, -99999)
var _center := Vector2.ZERO            # player position in (float) cell coordinates
var _facing := Vector2.UP
var _shown := true                     # the player's toggle
var _want := false                     # shown AND a dungeon is bound
var _slide := 0.0:                     # 0 = tucked off-screen, 1 = docked
	set(v):
		_slide = v
		_apply_offsets()
		_apply_alpha()
var _tween: Tween
var _hostiles := -1
var _t := 0.0

var _view: MapCanvas
var _coord_label: Label
var _hostile_label: Label
var _overlay: FullMap                  # TAB: full-screen map, a sibling on the HUD layer
var _overlay_open := false
## Set while drawing: the overlay paints with its own zoom and colours.
var _px := 8.0
var _map_alpha := 1.0
var _overlay_wait := 0.0                # the full-screen map redraws at most 30 times a second
## What the active quests still need, refreshed twice a second (see _refresh_wants):
## "kill" / "rarity" / "talk" / "recover" -> {id: true}
var _wants := {"kill": {}, "rarity": {}, "talk": {}, "recover": {}}
var _wants_wait := 0.0
var _rim: Array = []                    # [screen pos, colour] of quest targets off the map edge


func _enter_tree() -> void:
	add_to_group("minimap")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE      # never blocks clicks meant for the game
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_layout()
	_build_ui()
	_apply_offsets()
	_apply_alpha()
	visible = false                                  # slides in once a dungeon is bound


func _layout() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0


func _apply_offsets() -> void:
	var shift := (1.0 - _slide) * (map_size.x + margin.x + 20.0)
	offset_left = -(map_size.x + margin.x) + shift
	offset_right = -margin.x + shift
	offset_top = margin.y
	offset_bottom = margin.y + map_size.y


func _apply_alpha() -> void:
	modulate.a = opacity * _slide


func _build_ui() -> void:
	var title := _label("// SCAN //", 15, accent)
	title.position = Vector2(CHAMFER + 2.0, 7.0)
	add_child(title)

	_coord_label = _label("", 13, COL_DIM)
	_coord_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coord_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_coord_label.offset_left = 0.0
	_coord_label.offset_right = -16.0
	_coord_label.offset_top = 8.0
	add_child(_coord_label)

	_view = MapCanvas.new()
	_view.minimap = self
	add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.offset_left = CANVAS_INSET.x
	_view.offset_top = CANVAS_INSET.y
	_view.offset_right = -CANVAS_INSET.z
	_view.offset_bottom = -CANVAS_INSET.w

	# Footer: key hints on the left, hostile count on the right
	var hint_text := "[%s] HIDE  %s %s ALPHA  %s %s ZOOM" % [
		_key_name(toggle_key),
		_key_name(opacity_down_key), _key_name(opacity_up_key),
		_key_name(zoom_out_key), _key_name(zoom_in_key)]
	var hint := _label(hint_text, 11, COL_DIM)
	hint.clip_text = true                        # never spill into the hostile counter
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = CANVAS_INSET.x
	hint.offset_top = -22.0
	hint.offset_right = 220.0
	hint.offset_bottom = -4.0
	add_child(hint)

	_hostile_label = _label("", 12, COL_DIM)
	_hostile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hostile_label.anchor_left = 1.0
	_hostile_label.anchor_right = 1.0
	_hostile_label.anchor_top = 1.0
	_hostile_label.anchor_bottom = 1.0
	_hostile_label.offset_left = -110.0
	_hostile_label.offset_right = -(CHAMFER + 2.0)
	_hostile_label.offset_top = -22.0
	_hostile_label.offset_bottom = -4.0
	add_child(_hostile_label)

	var overlay := Scan.new()
	overlay.minimap = self
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The full-screen map lives next to the minimap on the HUD (not inside it), so it can
	# cover the whole screen and stays put when the minimap slides away.
	_overlay = FullMap.new()
	_overlay.minimap = self
	_overlay.visible = false
	get_parent().add_child.call_deferred(_overlay)


# ---------- PUBLIC ----------
## Call from dungeon.gd once generation is done. Also resets the explored area.
## options: "town" (bool) = no fog of war and a SAFE ZONE label; "npcs" (Array of Node3D) =
## people to mark on the map (names show on the full-screen map).
func bind_dungeon(director: DungeonDirector, grid_map: GridMap, enemies_root: Node3D = null,
		options: Dictionary = {}) -> void:
	_director = director
	_grid_map = grid_map
	_enemies_root = enemies_root
	var was_town := _town
	_town = bool(options.get("town", false))
	_npcs = options.get("npcs", [])
	# Towns are small: their full-screen map zooms in to fit the screen. Dungeons get back the
	# zoom the player had there.
	if _town:
		if not was_town:
			_dungeon_overlay_px = overlay_cell_px
		overlay_cell_px = _town_fit_px()
	elif was_town and _dungeon_overlay_px > 0.0:
		overlay_cell_px = _dungeon_overlay_px
	_explored.clear()
	_last_cell = Vector2i(-99999, -99999)
	_player = null
	_hostiles = -1


## Full-map zoom that fits the town's walkable cells into about 60% of the screen.
func _town_fit_px() -> float:
	var g := _director.grid if _director != null else null
	if g == null:
		return overlay_cell_px
	var lo := Vector2i(g.width, g.height)
	var hi := Vector2i(-1, -1)
	for x in g.width:
		for y in g.height:
			if g.get_tile(Vector2i(x, y)) != GridData.Tile.WALL:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return overlay_cell_px
	var cells := Vector2(hi - lo + Vector2i(3, 3))
	var screen := get_viewport_rect().size * 0.6
	return clampf(minf(screen.x / cells.x, screen.y / cells.y), overlay_min_cell_px, overlay_max_cell_px)


func set_shown(on: bool) -> void:
	_shown = on


func toggle() -> void:
	_shown = not _shown


## How far the minimap is docked: 1 = on screen, 0 = tucked away (hidden, or no dungeon).
## QuestTracker sits under it and moves up as this goes to 0.
func docked_amount() -> float:
	return _slide if visible else 0.0


## Bottom edge of the docked minimap, in screen pixels from the top.
func docked_bottom() -> float:
	return margin.y + map_size.y


func is_overlay_open() -> bool:
	return _overlay_open


func set_overlay(on: bool) -> void:
	on = on and _has_dungeon()
	if on and not _overlay_open:
		GameEvents.report("open_panel", "map")
	_overlay_open = on
	if _overlay != null:
		_overlay.visible = on
		if on:
			_overlay.queue_redraw()


func _has_dungeon() -> bool:
	return _director != null and is_instance_valid(_director) and _director.grid != null \
		and _grid_map != null and is_instance_valid(_grid_map)


# ---------- UPDATE ----------
func _process(delta: float) -> void:
	_t += delta
	if _director == null or not is_instance_valid(_director) or _director.grid == null \
			or _grid_map == null or not is_instance_valid(_grid_map):
		_set_want(false)                             # dungeon was freed (area changed)
		if _overlay_open:
			set_overlay(false)
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(player_group) as Node3D
	if _player == null:
		_set_want(false)
		return

	_center = _to_cell_f(_player.global_position)
	var cell := Vector2i(floori(_center.x), floori(_center.y))
	if cell != _last_cell:
		_last_cell = cell
		_reveal(cell)
		_coord_label.text = "%02d:%02d" % [cell.x, cell.y]

	var f := _player.global_transform.basis.z
	if not forward_is_plus_z:
		f = -f
	f = _grid_map.global_transform.basis.inverse() * f    # the map is drawn in dungeon-local space
	var flat := Vector2(f.x, f.z)
	if flat.length() > 0.01:
		_facing = flat.normalized()

	_update_hostiles()
	_wants_wait -= delta
	if _wants_wait <= 0.0:
		_wants_wait = 0.5
		_refresh_wants()
	_set_want(_shown)
	if visible:
		_view.queue_redraw()
	if _overlay_open:
		_overlay_wait -= delta
		if _overlay_wait <= 0.0:
			_overlay_wait = 1.0 / 30.0
			_overlay.queue_redraw()


## Slides the panel in or out, same motion as CharacterPanel.
func _set_want(on: bool) -> void:
	if on == _want:
		return
	_want = on
	if _tween:
		_tween.kill()
	if on:
		visible = true
	_tween = create_tween()
	_tween.tween_property(self, "_slide", 1.0 if on else 0.0, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not on:
		_tween.finished.connect(_on_slide_out_finished)


func _on_slide_out_finished() -> void:
	if not _want:
		visible = false


func _update_hostiles() -> void:
	if _town:
		if _hostiles != -2:
			_hostiles = -2
			_hostile_label.text = "SAFE ZONE"
			_hostile_label.add_theme_color_override("font_color", COL_PORTAL)
		return
	var n := 0
	if _enemies_root != null and is_instance_valid(_enemies_root):
		var limit := enemy_detect_radius * enemy_detect_radius
		for e in _enemies_root.get_children():
			var node := e as Node3D
			if node != null and (_to_cell_f(node.global_position) - _center).length_squared() <= limit:
				n += 1
	if n == _hostiles:
		return
	_hostiles = n
	_hostile_label.text = "HOSTILE %02d" % n
	_hostile_label.add_theme_color_override("font_color", COL_ENEMY if n > 0 else COL_DIM)


func _to_cell_f(pos: Vector3) -> Vector2:
	var l := _grid_map.to_local(pos)
	return Vector2(l.x / _grid_map.cell_size.x, l.z / _grid_map.cell_size.z)


func _reveal(cell: Vector2i) -> void:
	var r := reveal_radius
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				_explored[cell + Vector2i(dx, dy)] = true


func _known(cell: Vector2i) -> bool:
	return not fog_of_war or _town or _explored.has(cell)


func _walk(cell: Vector2i) -> bool:
	var g := _director.grid
	return g.in_bounds(cell) and g.get_tile(cell) != GridData.Tile.WALL


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == overlay_key:
		set_overlay(not _overlay_open)
		get_viewport().set_input_as_handled()
	elif event.keycode == toggle_key:
		_shown = not _shown
	elif event.keycode == opacity_down_key:
		opacity -= 0.1
	elif event.keycode == opacity_up_key:
		opacity += 0.1
	elif event.keycode == zoom_out_key or event.keycode == KEY_KP_SUBTRACT:
		_zoom(-1.0)
	elif event.keycode == zoom_in_key or event.keycode == KEY_KP_ADD:
		_zoom(1.0)


## - / = zoom the full-screen map while it's open, otherwise the minimap.
func _zoom(dir: float) -> void:
	if _overlay_open:
		overlay_cell_px = clampf(overlay_cell_px + dir * 2.0, overlay_min_cell_px, overlay_max_cell_px)
	else:
		cell_px = clampf(cell_px + dir, min_cell_px, max_cell_px)


# ---------- DRAWING ----------
func _draw() -> void:
	var w := size.x
	var h := size.y
	var poly := PackedVector2Array([
		Vector2(CHAMFER, 0), Vector2(w, 0), Vector2(w, h - CHAMFER),
		Vector2(w - CHAMFER, h), Vector2(0, h), Vector2(0, CHAMFER)])
	draw_colored_polygon(poly, Color(COL_BG, bg_opacity))
	var outline := PackedVector2Array(poly)
	outline.append(poly[0])
	draw_polyline(outline, Color(accent, 0.18 * frame_opacity), 7.0, true)    # glow
	draw_polyline(outline, Color(accent, frame_opacity), 2.0, true)
	# Rules under the title and above the footer, like the panel's title rule
	draw_line(Vector2(CANVAS_INSET.x, 30.0), Vector2(w - CANVAS_INSET.z, 30.0),
		Color(accent, 0.5 * frame_opacity), 2.0)
	draw_line(Vector2(CANVAS_INSET.x, h - CANVAS_INSET.w + 2.0),
		Vector2(w - CANVAS_INSET.z, h - CANVAS_INSET.w + 2.0),
		Color(accent, 0.25 * frame_opacity), 1.0)


## Canvas rotation in radians. Godot's Y rotation runs the opposite way to canvas
## rotation, so a dungeon turned -45 deg on Y needs the map turned +45 deg.
func _map_rotation() -> float:
	var r := deg_to_rad(rotation_offset_deg)
	if follow_dungeon_rotation and _grid_map != null and is_instance_valid(_grid_map):
		r -= _grid_map.global_rotation.y
	return r


## Called from MapCanvas._draw (the corner map) and FullMap._draw (TAB, `full` = true).
func _paint(c: Control, full := false) -> void:
	if _director == null or not is_instance_valid(_director) or _director.grid == null:
		return
	_px = overlay_cell_px if full else cell_px
	_map_alpha = overlay_map_opacity if full else map_opacity
	var px := _px
	var alpha := _map_alpha
	var rot := _map_rotation()
	var rotated := not is_zero_approx(rot)
	c.draw_set_transform(c.size * 0.5, rot, Vector2.ONE)    # (0,0) is now the player

	# How many cells can be on screen (more when the map is rotated)
	var ext := c.size * 0.5
	if rotated:
		ext = Vector2.ONE * c.size.length() * 0.5
	var rx := ceili(ext.x / px) + 1
	var ry := ceili(ext.y / px) + 1

	var floor_col := Color(accent, 0.16 * alpha)
	var wall_col := Color(accent, 0.85 * alpha)
	var base := Vector2i(floori(_center.x), floori(_center.y))

	# Only cells inside the dungeon (the full-screen map would otherwise walk thousands of
	# empty cells every frame)
	var g := _director.grid
	var y0 := maxi(base.y - ry, 0)
	var y1 := mini(base.y + ry, g.height - 1)
	var x0 := maxi(base.x - rx, 0)
	var x1 := mini(base.x + rx, g.width - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var cell := Vector2i(cx, cy)
			if not _known(cell) or not _walk(cell):
				continue
			var p := (Vector2(cell) - _center) * px
			c.draw_rect(Rect2(p + Vector2(0.5, 0.5),
				Vector2(px - 1.0, px - 1.0)), floor_col)
			for e in EDGES:
				if not _walk(cell + (e[0] as Vector2i)):
					c.draw_line(p + (e[1] as Vector2) * px,
						p + (e[2] as Vector2) * px, wall_col, 2.0, rotated)

	# Faint detection ring
	c.draw_arc(Vector2.ZERO, enemy_detect_radius * px, 0.0, TAU, 64,
		Color(accent, 0.12 * alpha), 1.0, true)

	# Screen-space overlays (not rotated with the map)
	if not full:
		_paint_edge_fade(c)
	_paint_compass(c, rot)

	# Map-space markers
	c.draw_set_transform(c.size * 0.5, rot, Vector2.ONE)
	_rim.clear()
	_paint_portals(c, rot)
	_paint_enemies(c, rot, full)
	_paint_quest_spots(c, rot, full)
	_paint_npcs(c, rot, full)
	_paint_player(c)
	_paint_rim_arrows(c, rot)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Soft fade so the map melts into the frame instead of being cut off.
func _paint_edge_fade(c: Control) -> void:
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var s := c.size
	var f := 22.0
	var solid := Color(COL_BG, clampf(bg_opacity + 0.25, 0.0, 1.0))
	var clear := Color(COL_BG, 0.0)
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, f), Vector2(0, f)]),
		PackedColorArray([solid, solid, clear, clear]))
	c.draw_polygon(PackedVector2Array([Vector2(0, s.y), Vector2(s.x, s.y), Vector2(s.x, s.y - f), Vector2(0, s.y - f)]),
		PackedColorArray([solid, solid, clear, clear]))
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(0, s.y), Vector2(f, s.y), Vector2(f, 0)]),
		PackedColorArray([solid, solid, clear, clear]))
	c.draw_polygon(PackedVector2Array([Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - f, s.y), Vector2(s.x - f, 0)]),
		PackedColorArray([solid, solid, clear, clear]))


## A small "N" on the rim: at the top (north_at_top), or pointing to the grid's north.
func _paint_compass(c: Control, rot: float) -> void:
	c.draw_set_transform(c.size * 0.5, 0.0, Vector2.ONE)
	var radius := minf(c.size.x, c.size.y) * 0.5 - (60.0 if c is FullMap else 11.0)
	var pos := Vector2.UP * radius if north_at_top else Vector2.UP.rotated(rot) * radius
	var f := _font if _font else ThemeDB.fallback_font
	c.draw_circle(pos, 9.0, Color(COL_BG, 0.85))
	c.draw_arc(pos, 9.0, 0.0, TAU, 20, Color(accent, 0.6 * _map_alpha), 1.0, true)
	c.draw_string(f, pos + Vector2(-9.0, 5.0), "N", HORIZONTAL_ALIGNMENT_CENTER, 18.0,
		roundi(13 * font_scale), Color(COL_TEXT, _map_alpha))


func _paint_portals(c: Control, rot: float) -> void:
	if _director.layout == null:
		return
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	var half := c.size * 0.5 - Vector2(16.0, 16.0)
	var offscreen: Array[Vector2] = []
	for p in _director.layout.portals:
		var cell: Vector2i = p.cell
		if not _known(cell):
			continue
		var pos := (Vector2(cell) + Vector2(0.5, 0.5) - _center) * _px
		var screen := pos.rotated(rot)
		if absf(screen.x) > half.x or absf(screen.y) > half.y:
			offscreen.append(screen)
			continue
		var r := 5.0
		var col := Color(COL_PORTAL, _map_alpha)
		c.draw_colored_polygon(PackedVector2Array([
			pos + Vector2(0, -r), pos + Vector2(r, 0),
			pos + Vector2(0, r), pos + Vector2(-r, 0)]), col)
		c.draw_arc(pos, r + 3.0 + pulse * 3.0, 0.0, TAU, 24,
			Color(COL_PORTAL, (0.55 - pulse * 0.4) * _map_alpha), 1.5, true)

	# Known portals that are off the map get an arrow on the rim
	if offscreen.is_empty():
		return
	c.draw_set_transform(c.size * 0.5, 0.0, Vector2.ONE)
	for screen in offscreen:
		var dir := screen.normalized()
		var k := minf(half.x / maxf(absf(screen.x), 0.001), half.y / maxf(absf(screen.y), 0.001))
		var at := screen * k
		var side := Vector2(-dir.y, dir.x)
		var a := 0.5 + 0.5 * pulse
		c.draw_colored_polygon(PackedVector2Array([
			at + dir * 7.0, at - dir * 4.0 + side * 6.0, at - dir * 4.0 - side * 6.0]),
			Color(COL_PORTAL, a * _map_alpha))
	c.draw_set_transform(c.size * 0.5, rot, Vector2.ONE)


func _paint_enemies(c: Control, rot: float, full: bool) -> void:
	if _enemies_root == null or not is_instance_valid(_enemies_root):
		return
	var limit := enemy_detect_radius * enemy_detect_radius
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	for e in _enemies_root.get_children():
		var n := e as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var rel := _to_cell_f(n.global_position) - _center
		if _is_quest_enemy(n):
			_quest_marker(c, rel * _px, rot, str(n.get_meta(&"base_name", "")) if full else "")
			continue
		if rel.length_squared() > limit:
			continue
		var pos := rel * _px
		c.draw_arc(pos, 5.5 + pulse * 3.0, 0.0, TAU, 20,
			Color(COL_ENEMY, (0.5 - pulse * 0.35) * _map_alpha), 1.0, true)
		c.draw_circle(pos, 4.5, Color(COL_ENEMY, 0.25 * _map_alpha))
		c.draw_circle(pos, 2.5, Color(COL_ENEMY, _map_alpha))


## Gold markers for the people in town. On the full-screen map their names show above them.
func _paint_npcs(c: Control, rot: float, full: bool) -> void:
	if _npcs.is_empty():
		return
	var f := _font if _font else ThemeDB.fallback_font
	var half := c.size * 0.5
	var taken: Array[Rect2] = []              # name tags already drawn (so they don't pile up)
	for n in _npcs:
		var npc := n as Node3D
		if npc == null or not is_instance_valid(npc) or not npc.is_inside_tree():
			continue
		var pos := (_to_cell_f(npc.global_position) - _center) * _px
		var screen := pos.rotated(rot)
		if _wants["talk"].has(str(npc.get("npc_id"))):
			_quest_marker(c, pos, rot, "")      # the ring, or the rim arrow when off the map
		if absf(screen.x) > half.x or absf(screen.y) > half.y:
			continue
		var mark: Array = NpcNameplates.quest_mark(npc, _player.get("quests")) \
				if npc is Interactable and _player != null else []
		if mark.is_empty():
			c.draw_circle(pos, 5.0, Color(COL_BG, 0.8 * _map_alpha))
			c.draw_circle(pos, 3.5, Color(COL_NPC, _map_alpha))
		else:
			_glyph_badge(c, pos, rot, mark[0], mark[1])
		if full:
			var who: String = str(npc.get("npc_name")) if npc.get("npc_name") != null else npc.name
			# text is drawn upright: step out of the map rotation for it
			c.draw_set_transform(c.size * 0.5, 0.0, Vector2.ONE)
			var fs := roundi(13 * font_scale)
			var w := f.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := screen + Vector2(-w * 0.5, -10.0)
			var tag := Rect2(at - Vector2(2, fs), Vector2(w + 4, fs + 4))
			for i in 4:                              # step up until it's clear of the others
				if not taken.any(func(r: Rect2) -> bool: return r.intersects(tag)):
					break
				at.y -= fs + 3
				tag.position.y -= fs + 3
			taken.append(tag)
			if at.y < screen.y - 14.0:              # moved: a thin leader line to its dot
				c.draw_line(screen + Vector2(0, -4), at + Vector2(w * 0.5, 2), Color(COL_NPC, 0.5 * _map_alpha), 1.0)
			c.draw_string_outline(f, at, who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				4, Color(COL_BG, 0.9 * _map_alpha))
			c.draw_string(f, at, who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(COL_NPC, _map_alpha))
			c.draw_set_transform(c.size * 0.5, rot, Vector2.ONE)


# ---------- QUESTS ----------
## Reads what the active quests still need from the player's QuestManager.
func _refresh_wants() -> void:
	for k in _wants:
		_wants[k].clear()
	var qm: QuestManager = _player.get("quests") if _player != null else null
	if qm == null:
		return
	var area := ""
	if _enemies_root != null and is_instance_valid(_enemies_root) and _enemies_root.owner != null:
		area = _enemies_root.owner.scene_file_path.get_file().get_basename()
	for s in qm.active.values():
		var st := s as QuestState
		if st.status != QuestState.Status.ACTIVE:
			continue
		for i in st.def.objectives.size():
			if st.objective_done(i):
				continue
			var o: Objective = st.def.objectives[i]
			if o.target != "":
				match o.kind:
					"kill":
						_wants["kill"][o.target] = true
					"kill_at":                     # "corrupted_raider@act_1_coolant_vaults"
						var parts := o.target.split("@")
						if parts.size() == 2 and parts[1] == area:
							_wants["kill"][parts[0]] = true
					"kill_rarity":
						_wants["rarity"][o.target] = true
					"talk":
						_wants["talk"][o.target] = true
					"recover":                     # a quest key, or a ward beacon
						_wants["recover"][o.target] = true
			if st.def.ordered:
				break                              # later steps don't count yet


## Ward beacons and dropped quest keys that an active quest still asks for.
func _paint_quest_spots(c: Control, rot: float, full: bool) -> void:
	if _wants["recover"].is_empty():
		return
	for group in [&"ward_beacons", &"quest_pickups"]:
		for n in get_tree().get_nodes_in_group(group):
			var spot := n as Node3D
			var id := str(spot.get("beacon_id") if group == &"ward_beacons" else spot.get("key_id"))
			if not _wants["recover"].has(id) or (spot.has_method("is_lit") and spot.is_lit()):
				continue
			_quest_marker(c, (_to_cell_f(spot.global_position) - _center) * _px, rot,
					QuestItems.name_of(id) if full else "")


func _is_quest_enemy(n: Node) -> bool:
	return _wants["kill"].has(str(n.get_meta(&"enemy_id", ""))) \
			or _wants["rarity"].has(str(n.get_meta(&"rarity", ""))) \
			or _wants["recover"].has(str(n.get_meta(&"carries_key", "")))


## A pulsing gold ring round a quest target at `pos` (map space), with its name over it on the
## full-screen map. Off the map edge it becomes an arrow on the rim instead.
func _quest_marker(c: Control, pos: Vector2, rot: float, label: String) -> void:
	var screen := pos.rotated(rot)
	var half := c.size * 0.5 - Vector2(16.0, 16.0)
	if absf(screen.x) > half.x or absf(screen.y) > half.y:
		_rim.append([screen, COL_QUEST])
		return
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	c.draw_circle(pos, 9.0 + pulse * 2.0, Color(COL_QUEST, 0.18 * _map_alpha))
	c.draw_circle(pos, 6.0, Color(COL_BG, 0.9 * _map_alpha))
	c.draw_arc(pos, 6.0, 0.0, TAU, 24, Color(COL_QUEST, _map_alpha), 2.0, true)
	c.draw_circle(pos, 3.0, Color(COL_ENEMY, _map_alpha))
	if label != "":
		_upright_tag(c, screen + Vector2(0.0, -12.0), label.to_upper(), COL_QUEST, rot)


## A quest giver's "!" or "+" on a small round badge (drawn upright, whatever the map's turn).
func _glyph_badge(c: Control, pos: Vector2, rot: float, glyph: String, col: Color) -> void:
	c.draw_set_transform(c.size * 0.5, 0.0, Vector2.ONE)
	var at := pos.rotated(rot)
	var r := 8.0
	c.draw_circle(at, r + 3.0 + sin(_t * 3.0) * 1.5, Color(col, 0.22 * _map_alpha))
	c.draw_circle(at, r, Color(COL_BG, 0.92 * _map_alpha))
	c.draw_arc(at, r - 0.75, 0.0, TAU, 24, Color(col, _map_alpha), 1.5, true)
	var f := _font if _font else ThemeDB.fallback_font
	var fs := roundi(15 * font_scale)
	var w := f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(f, (at + Vector2(-w * 0.5, fs * 0.34)).round(), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, _map_alpha))
	c.draw_set_transform(c.size * 0.5, rot, Vector2.ONE)


## Upright text centred on `at` (screen space round the map's centre), with a dark outline.
func _upright_tag(c: Control, at: Vector2, text: String, col: Color, rot: float) -> void:
	c.draw_set_transform(c.size * 0.5, 0.0, Vector2.ONE)
	var f := _font if _font else ThemeDB.fallback_font
	var fs := roundi(12 * font_scale)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := (at - Vector2(w * 0.5, 0.0)).round()
	c.draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(COL_BG, 0.9 * _map_alpha))
	c.draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, _map_alpha))
	c.draw_set_transform(c.size * 0.5, rot, Vector2.ONE)


## Arrows on the rim for quest targets off the map edge (gathered while painting).
func _paint_rim_arrows(c: Control, rot: float) -> void:
	if _rim.is_empty():
		return
	c.draw_set_transform(c.size * 0.5, 0.0, Vector2.ONE)
	var half := c.size * 0.5 - Vector2(16.0, 16.0)
	var a := 0.85 + 0.15 * sin(_t * 4.0)
	for r in _rim:
		var screen: Vector2 = r[0]
		var dir := screen.normalized()
		var k := minf(half.x / maxf(absf(screen.x), 0.001), half.y / maxf(absf(screen.y), 0.001))
		var at := screen * k
		var side := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([at + dir * 12.0, at - dir * 7.0 + side * 9.0, at - dir * 7.0 - side * 9.0])
		c.draw_circle(at, 13.0, Color(r[1], 0.18 * _map_alpha))   # glow, so it reads on any floor
		c.draw_colored_polygon(tri, Color(r[1], a * _map_alpha))
		tri.append(tri[0])
		c.draw_polyline(tri, Color(COL_BG, 0.9 * _map_alpha), 1.5, true)
	c.draw_set_transform(c.size * 0.5, rot, Vector2.ONE)


func _paint_player(c: Control) -> void:
	var side := Vector2(-_facing.y, _facing.x)
	var tip := _facing * 9.0
	var left := -_facing * 5.0 + side * 5.5
	var right := -_facing * 5.0 - side * 5.5
	c.draw_circle(Vector2.ZERO, 11.0, Color(accent, 0.14 * _map_alpha))
	c.draw_colored_polygon(PackedVector2Array([tip, left, Vector2.ZERO, right]),
		Color(1, 1, 1, _map_alpha))
	c.draw_polyline(PackedVector2Array([tip, left, Vector2.ZERO, right, tip]),
		Color(accent, _map_alpha), 1.5, true)


## Short display name for a key (the engine's names are long, e.g. "BracketLeft").
func _key_name(key: Key) -> String:
	match key:
		KEY_BRACKETLEFT: return "["
		KEY_BRACKETRIGHT: return "]"
		KEY_MINUS: return "-"
		KEY_EQUAL: return "="
		KEY_KP_ADD: return "+"
		KEY_KP_SUBTRACT: return "-"
		KEY_TAB: return "TAB"
	return OS.get_keycode_string(key)


func _label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", roundi(fsize * font_scale))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------- SMALL DRAWN WIDGETS ----------
## TAB: the whole screen as a see-through map, centred on the player. Draws under the other
## HUD panels' level only by tint; it ignores the mouse so the game plays on underneath.
class FullMap extends Control:
	var minimap     # the owning Minimap

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		z_index = -1                             # under the other HUD widgets

	func _draw() -> void:
		if minimap == null:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(minimap.COL_BG, minimap.overlay_dim))
		minimap._paint(self, true)
		# Title and key hints along the top
		var f: Font = minimap._font if minimap._font else ThemeDB.fallback_font
		var fs := roundi(15 * minimap.font_scale)
		draw_string(f, Vector2(32, 40), "// MAP //", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20 * minimap.font_scale),
			minimap.accent)
		draw_string(f, Vector2(32, 64), "[%s] CLOSE   %s %s ZOOM" % [minimap._key_name(minimap.overlay_key),
			minimap._key_name(minimap.zoom_out_key), minimap._key_name(minimap.zoom_in_key)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(minimap.COL_DIM, 0.9))

## The clipped area the tiles are drawn on.
class MapCanvas extends Control:
	var minimap     # the owning Minimap

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		if minimap:
			minimap._paint(self)


## CRT scanlines and a slow sweep, like the character panel.
class Scan extends Control:
	var minimap
	var t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if minimap and minimap.scanlines and is_visible_in_tree():
			t += delta
			queue_redraw()

	func _draw() -> void:
		if minimap == null or not minimap.scanlines:
			return
		var inset := 14.0
		var y := 30.0
		while y < size.y - 26.0:
			draw_line(Vector2(inset, y), Vector2(size.x - inset, y), Color(0, 0, 0, 0.13), 1.0)
			y += 3.0
		var sweep_y := fposmod(t * 70.0, size.y + 120.0) - 60.0
		draw_line(Vector2(inset, sweep_y), Vector2(size.x - inset, sweep_y), Color(1, 1, 1, 0.05), 6.0)
