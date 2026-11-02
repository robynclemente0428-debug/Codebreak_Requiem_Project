extends CanvasLayer
## NPC name plates: each NPC's name, and their role (Interactable.info_title) under it, float
## over their head. A quest marker sits above the name when they have something for you:
##   !  gold   a quest ready to turn in
##   +  green  a new quest available
## Same symbols and colours as the NPC info card. Names fade out with distance.
##
## Hovering a portal shows a card over it with where it leads (the waypoint's name, whether
## it's a town, dungeon or boss area, and its level).
##
## Drawn as normal 2D text over the world, like LootLabels, so it stays sharp even though the
## world renders at a third of the resolution. project() is shared with TutorialHints.

const FONT_PATH := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const SHOW_DISTANCE := 22.0       # metres: names past this are hidden
const FADE_DISTANCE := 4.0        # metres before SHOW_DISTANCE where names start fading
const HEAD_GAP := 0.3             # metres above the NPC's prompt_height
const NAME_SIZE := 20
const ROLE_SIZE := 14
## The quest marker: the symbol on a round badge that floats just above the name plate. It only
## bobs upwards from its resting spot, so it never dips into the plate.
const MARK_SIZE := 40
const MARK_RADIUS := 21.0         # the badge, in pixels
const MARK_RING := 3.0
const MARK_GAP := 6.0             # pixels between the badge and the plate's top edge
const MARK_BOB := 5.0             # how far it bobs up
const OUTLINE := 6
## The dark plate behind each name, so it stands out from busy floors.
const PLATE_PAD := Vector2(12.0, 5.0)    # space around the text, in pixels
const COL_PLATE := Color(0.01, 0.03, 0.05, 0.80)
const COL_PLATE_EDGE := Color(0.0, 0.90, 1.0, 0.55)
const COL_NAME := Color(0.80, 0.98, 1.0)  # near-white cyan: reads on light and dark floors
const COL_ROLE := Color(0.62, 0.84, 0.90)
const PORTAL_TITLE_SIZE := 18
const PORTAL_SUB_SIZE := 13
const THREAT_SEP := "  ·  "
const COL_CARD := Color(0.02, 0.06, 0.08, 0.88)

var enabled := true
var show_roles := true

var _font: Font
var _canvas: Control
var _npcs: Array[Interactable] = []
var _quest_ids: Dictionary = {}           # Interactable -> PackedStringArray (cached on rescan)
var _portals: Array[Portal] = []
var _hover_portal: Portal
var _container: SubViewportContainer
var _viewport: SubViewport
var _rescan_wait := 0.0
var _tops: Dictionary = {}                # Interactable -> screen y of the top of its plate/badge
var _time := 0.0


func _ready() -> void:
	layer = 5                             # over the world, under the area fade (10) and the HUD (20)
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_on_canvas_draw)
	add_child(_canvas)


func _process(delta: float) -> void:
	_time += delta
	if _time >= _rescan_wait:
		_rescan_wait = _time + 1.0        # NPCs come and go with area changes
		_rescan()
	_hover_portal = _portal_under_mouse()
	_canvas.queue_redraw()


## World point -> screen point, through the low-resolution world SubViewport when there is one.
## Returns {"pos": Vector2, "behind": bool}, or {} when there's no camera.
func project(world_pos: Vector3) -> Dictionary:
	_find_view()
	var cam: Camera3D = _viewport.get_camera_3d() if _viewport != null else get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var p := cam.unproject_position(world_pos)
	if _viewport != null and _container != null:
		p = p * (_container.size / Vector2(_viewport.size)) + _container.global_position
	return {"pos": p, "behind": cam.is_position_behind(world_pos)}


func _find_view() -> void:
	if _container != null and is_instance_valid(_container) and _container.is_inside_tree():
		return
	_container = null
	_viewport = null
	var scene := get_tree().current_scene
	if scene == null:
		return
	_container = scene.find_child("SubViewportContainer", true, false) as SubViewportContainer
	if _container != null:
		for c in _container.get_children():
			if c is SubViewport:
				_viewport = c
				break


func _rescan() -> void:
	_npcs.clear()
	_quest_ids.clear()
	_portals.clear()
	for n in get_tree().root.find_children("*", "Area3D", true, false):
		if n is DialogueNPC or n is QuestGiverNPC:
			_npcs.append(n)
			_quest_ids[n] = NpcInfoPanel.quests_of(n)
		elif n is Portal:
			_portals.append(n)


# ---------- DRAWING ----------
func _on_canvas_draw() -> void:
	if not enabled:
		return
	var player := get_tree().get_first_node_in_group("players") as Node3D
	if player == null:
		return
	var qm: QuestManager = player.get("quests")
	# The full map covers the screen with a see-through overlay: names would show through it.
	var minimap := get_tree().get_first_node_in_group("minimap") as Control
	if minimap != null and minimap.has_method("is_overlay_open") and minimap.is_overlay_open():
		return
	# The "[T] TALK" prompt sits right above the NPC it belongs to: lift that NPC's plate over it.
	var prompt := get_tree().get_first_node_in_group("interact_prompt") as Control
	_tops.clear()
	for npc in _npcs:
		if not is_instance_valid(npc) or not npc.is_inside_tree() or not npc.is_visible_in_tree():
			continue
		var dist := player.global_position.distance_to(npc.global_position)
		if dist > SHOW_DISTANCE:
			continue
		var alpha := clampf((SHOW_DISTANCE - dist) / FADE_DISTANCE, 0.0, 1.0)
		var pr := project(npc.global_position + Vector3.UP * (npc.prompt_height + HEAD_GAP))
		if pr.is_empty() or pr["behind"]:
			continue
		var at: Vector2 = pr["pos"]
		if minimap != null and minimap.visible and minimap.get_global_rect().has_point(at):
			continue                        # under the corner map: it would show through it
		var bottom := at.y                 # the plate's bottom edge; it grows upwards from here
		if prompt != null and prompt.visible and prompt.get("_target") == npc:
			bottom -= prompt.size.y + 6.0
		var top := _draw_plate(NpcInfoPanel._npc_name(npc),
			npc.info_title if show_roles else "", at.x, bottom, alpha)
		var mark := quest_mark(npc, qm)
		if not mark.is_empty():
			_draw_mark(mark[0], mark[1], at.x, top, alpha)
			top -= MARK_GAP + MARK_RADIUS * 2.0 + MARK_BOB
		_tops[npc] = top

	if _hover_portal != null and is_instance_valid(_hover_portal):
		_draw_portal_card(_hover_portal)


## Screen y of the top of what's drawn over this NPC (its plate, and the quest badge at the
## top of its bob), or NAN when nothing is. TutorialHints keeps its arrow above it.
func top_of(npc: Node) -> float:
	return _tops.get(npc, NAN)


# ---------- PORTALS ----------
## Portals in the current area (refreshed once a second). Used by TutorialHints.
func portals() -> Array[Portal]:
	return _portals


## The portal under the mouse, unless the mouse is over the HUD or a menu.
func _portal_under_mouse() -> Portal:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and not hovered is SubViewportContainer:
		return null
	var mouse := get_viewport().get_mouse_position()
	for portal in _portals:
		if is_instance_valid(portal) and portal.is_inside_tree() \
				and _portal_screen_rect(portal).grow(6.0).has_point(mouse):
			return portal
	return null


## The portal's collision box, projected to a rectangle on screen (empty if off camera).
func _portal_screen_rect(portal: Portal) -> Rect2:
	var shape_node := portal.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var box := shape_node.shape as BoxShape3D if shape_node != null else null
	if box == null:
		return Rect2()
	var xf := shape_node.global_transform
	var half := box.size * 0.5
	var rect := Rect2()
	for i in 8:
		var corner := Vector3(half.x if i & 1 else -half.x, half.y if i & 2 else -half.y,
				half.z if i & 4 else -half.z)
		var pr := project(xf * corner)
		if pr.is_empty() or pr["behind"]:
			return Rect2()
		rect = Rect2(pr["pos"], Vector2.ZERO) if i == 0 else rect.expand(pr["pos"])
	return rect


## "-> THE BREACH" with "DUNGEON  ·  LEVEL 1" under it, in a small card over the portal.
func _draw_portal_card(portal: Portal) -> void:
	var rect := _portal_screen_rect(portal)
	if rect.size == Vector2.ZERO:
		return
	var lines := _portal_lines(portal)
	var title: String = lines[0]
	var sub: String = lines[1]
	# What the fights there favour, as coloured tags ("SWARM  ·  REFLECTOR"), so players can
	# swap scripts before stepping through
	var threats := DungeonThreats.preview(portal.target_area, portal.dungeon_level, portal.instance_id == -1) \
			if portal.target_area != "" else PackedStringArray()
	var tag_gap := _font.get_string_size(THREAT_SEP, HORIZONTAL_ALIGNMENT_LEFT, -1, PORTAL_SUB_SIZE).x
	var tag_w := 0.0
	for id in threats:
		tag_w += _font.get_string_size(DungeonThreats.label(id), HORIZONTAL_ALIGNMENT_LEFT, -1, PORTAL_SUB_SIZE).x
	tag_w += tag_gap * maxi(threats.size() - 1, 0)
	var tw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, PORTAL_TITLE_SIZE).x
	var sw := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, PORTAL_SUB_SIZE).x if sub != "" else 0.0
	var height := PORTAL_TITLE_SIZE + 16.0 + (PORTAL_SUB_SIZE + 6.0 if sub != "" else 0.0) \
			+ (PORTAL_SUB_SIZE + 8.0 if not threats.is_empty() else 0.0)
	var size := Vector2(maxf(maxf(tw, sw), tag_w) + 28.0, height)
	var card := Rect2(Vector2(rect.get_center().x - size.x * 0.5, rect.position.y - size.y - 10.0), size).abs()
	card.position = card.position.round()

	var accent := Portal.SEALED_A if portal.is_sealed() else NpcInfoPanel.ACCENT   # red when sealed
	_canvas.draw_rect(rect.grow(4.0), Color(accent, 0.6), false, 2.0)   # the portal itself
	_canvas.draw_rect(card, COL_CARD, true)
	_canvas.draw_rect(card, accent, false, 2.0)
	var cx := card.get_center().x
	var y := card.position.y + 8.0 + PORTAL_TITLE_SIZE
	_text(title, cx, y, PORTAL_TITLE_SIZE, accent)
	if sub != "":
		y += PORTAL_SUB_SIZE + 6.0
		_text(sub, cx, y, PORTAL_SUB_SIZE, NpcInfoPanel.COL_DIM)
	if not threats.is_empty():
		y += PORTAL_SUB_SIZE + 8.0
		var x := cx - tag_w * 0.5
		for i in threats.size():
			if i > 0:
				_canvas.draw_string(_font, Vector2(x, y), THREAT_SEP, HORIZONTAL_ALIGNMENT_LEFT, -1,
						PORTAL_SUB_SIZE, NpcInfoPanel.COL_DIM)
				x += tag_gap
			var tag := DungeonThreats.label(threats[i])
			_canvas.draw_string(_font, Vector2(x, y), tag, HORIZONTAL_ALIGNMENT_LEFT, -1,
					PORTAL_SUB_SIZE, DungeonThreats.color(threats[i]))
			x += _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, PORTAL_SUB_SIZE).x


## [title, subtitle] for where a portal leads. Uses the waypoint list for the area's name,
## and falls back to the scene's file name for areas without a waypoint.
func _portal_lines(portal: Portal) -> Array:
	if portal.target_area == "":
		return ["-> NOWHERE", "NO TARGET SET"]
	var w := Waypoints.for_scene(portal.target_area)
	var title := w.display_name if w != null and w.display_name != "" \
			else Waypoints.normalize(portal.target_area).get_file().get_basename().replace("_", " ")
	var parts: PackedStringArray = []
	if w != null:
		parts.append(["TOWN", "DUNGEON", "BOSS"][w.kind] if w.kind >= 0 and w.kind <= 2 else "AREA")
	var level := portal.dungeon_level if portal.dungeon_level > 0 else (w.dungeon_level if w != null else 0)
	if level > 0:
		parts.append("LEVEL %d" % level)
	if portal.instance_id == -1:
		parts.append("NEW INSTANCE")
	if portal.is_sealed():
		return ["SEALED: " + title.to_upper(), "NEEDS THE " + QuestItems.name_of(portal.sealed_by_key)]
	return ["-> " + title.to_upper(), "  ·  ".join(parts)]


## ["!", gold] when a quest is ready to turn in here, ["+", green] when one can be started.
## The minimap shows the same marks.
func quest_mark(npc: Interactable, qm: QuestManager) -> Array:
	if qm == null:
		return []
	var fresh := false
	for id in _quest_ids.get(npc, PackedStringArray()):
		var def := qm.get_def(id)
		if def == null:
			continue
		var st := qm.get_state(id)
		if st != null and st.status == QuestState.Status.READY_TO_TURN_IN:
			return ["!", NpcInfoPanel.COL_READY]
		if st == null and qm.can_start(def):
			fresh = true
	return ["+", NpcInfoPanel.COL_NEW] if fresh else []


## The quest marker's badge, resting MARK_GAP above `plate_top` and bobbing up from there.
func _draw_mark(glyph: String, col: Color, x: float, plate_top: float, alpha: float) -> void:
	var wave := (sin(_time * 3.0) + 1.0) * 0.5
	var center := Vector2(x, plate_top - MARK_GAP - MARK_RADIUS - wave * MARK_BOB).round()
	_canvas.draw_circle(center, MARK_RADIUS + 4.0 + wave * 3.0, Color(col, 0.20 * alpha))   # glow
	_canvas.draw_circle(center, MARK_RADIUS, Color(COL_PLATE, 0.95 * alpha))
	_canvas.draw_arc(center, MARK_RADIUS - MARK_RING * 0.5, 0.0, TAU, 40, Color(col, alpha), MARK_RING, true)
	# Capital-height symbols: their middle sits about a third of the font size above the baseline.
	_text(glyph, center.x, center.y + MARK_SIZE * 0.32, MARK_SIZE, Color(col, alpha))


## Name (and role under it) on a dark plate, centred on x with its bottom edge at `bottom`.
## Returns the plate's top edge, for the quest marker above it.
func _draw_plate(title: String, role: String, x: float, bottom: float, alpha: float) -> float:
	var name_w := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
	var role_w := _font.get_string_size(role, HORIZONTAL_ALIGNMENT_LEFT, -1, ROLE_SIZE).x if role != "" else 0.0
	var name_h := _font.get_ascent(NAME_SIZE) + _font.get_descent(NAME_SIZE)
	var role_h := _font.get_ascent(ROLE_SIZE) + _font.get_descent(ROLE_SIZE) if role != "" else 0.0
	var gap := 2.0 if role != "" else 0.0
	var size := Vector2(maxf(name_w, role_w), name_h + gap + role_h) + PLATE_PAD * 2.0
	var rect := Rect2(Vector2(x - size.x * 0.5, bottom - size.y), size)
	rect.position = rect.position.round()
	_canvas.draw_rect(rect, Color(COL_PLATE, COL_PLATE.a * alpha), true)
	_canvas.draw_rect(rect, Color(COL_PLATE_EDGE, COL_PLATE_EDGE.a * alpha), false, 1.0)
	var name_base := rect.position.y + PLATE_PAD.y + _font.get_ascent(NAME_SIZE)
	_text(title, x, name_base, NAME_SIZE, Color(COL_NAME, alpha))
	if role != "":
		_text(role, x, name_base + _font.get_descent(NAME_SIZE) + gap + _font.get_ascent(ROLE_SIZE),
			ROLE_SIZE, Color(COL_ROLE, alpha))
	return rect.position.y


## Text centred on x, with its baseline at y. Whole pixels, so it doesn't shimmer.
func _text(text: String, x: float, y: float, size: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(x - w * 0.5, y).round()
	_canvas.draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, OUTLINE,
			Color(0.0, 0.0, 0.0, 0.85 * col.a))
	_canvas.draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
