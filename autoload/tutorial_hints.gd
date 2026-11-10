extends CanvasLayer
## Tutorial hints. Follows two quests, in order:
##   BASIC TRAINING (tut_basics)              moving, the map, gear, gems, binding, attacking
##   PROXIMITY TRIGGER (q00_proximity_trigger) the first script, step by step, then a fight
## Plus short lessons outside the quests:
##   SUPPORT GEMS   after picking the training reward: socket it next to the skill, see what it does
##   WAYPOINTS      the first time the player is in a dungeon: open the map, see how travel works
##   QUESTS         as soon as a new character has their first quest, before anything else:
##                  the tracker under the minimap, and the quest log it opens
##   ROUTE TERMINAL the first time on a convoy (an act with a route): use the terminal to pick
##                  a stop, then what the route map shows. Ends when the route map is closed.
##   RANK EXAMS     once the first exam (Operator) opens up: what exams are, what a rank gives,
##                  then sitting it in Sudo's sandbox and handing it in. Ends when it's passed.
##   LOOT           the first time a drop lies near the player: hold the pickup key, point at it,
##                  left-click. Ends on the first drop picked up.
##   SCRIPTING GUIDE opens by itself (ScriptGuide) the first time the scripting lesson reaches the
##                  editor; the lesson waits until it's closed.
##   AREA CLEARS    in a dungeon, once training is done: clearing every enemy in an area gives
##                  every skill a script point (ScriptBudget). Shown for CLEAR_HINT_TIME seconds.
## Shows a banner with the next thing to do and a second line saying why, outlines the UI to
## click, and points an arrow at things in the world (Warden Brack, a dungeon portal).
## The step shown is the quest's first objective that isn't done yet, and the scripting steps
## also read the editor (is the rule there, does it have an effect, does it compile...), so the
## hints always match what the player actually has.
##
## The panels don't know about the tutorial: each has small tutorial_target(id) /
## tutorial_state() functions. Set `enabled = false` to hide every hint.

const QUEST_BASICS := "tut_basics"
const QUEST_SCRIPT := "q00_proximity_trigger"
const GUIDE_NPC_ID := "brack"
## Lessons that aren't quests, kept in the character's save once seen.
const SAVE_KEY_DONE := "tutorials_done"
const LESSON_WAYPOINTS := "waypoints"
const LESSON_SUPPORTS := "support_gems"
const LESSON_QUESTS := "quest_tracker"
const LESSON_EXAMS := "rank_exams"
const LESSON_ROUTE := "route_terminal"
const LESSON_CLEARS := "area_clears"
const LESSON_GUIDE := "script_guide"       # the SCRIPTING GUIDE opened once, at the scripting lesson
const LESSON_LOOT := "loot_pickup"
const CLEAR_HINT_TIME := 12.0             # seconds the area-clear lesson stays up
const LOOT_ARROW_HEIGHT := 1.6            # metres: over a drop and its name
const LOOT_HINT_RANGE := 14.0              # metres: a drop this close starts the loot lesson
const FIRST_EXAM := "exam_operator"
const EXAMINER_NPC_ID := "sudo"
const FONT_PATH := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_SUB := Color(0.62, 0.80, 0.86)
const COL_BG := Color(0.02, 0.06, 0.08, 0.90)
const COL_HINT := Color(0.30, 0.95, 0.60)
const BANNER_Y := 96.0                     # px from the top of the screen
const BANNER_MAX_WIDTH := 860.0            # the second line wraps past this
const ARROW_HEIGHT := 3.6                  # metres above the target's feet (clears name plates)
const EDGE_MARGIN := 48.0                  # off-screen arrows stay this far from the edge

var enabled := true

var _player: Node
var _guide: Node3D
var _guide_search_wait := 0.0
var _examiner: Node3D
var _terminal: Node3D
var _terminal_search_wait := 0.0
var _examiner_search_wait := 0.0
var _banner: PanelContainer
var _label: Label
var _sub: Label
var _canvas: Control                       # draws the outlines round the UI
## The arrow over a world target is drawn on its own layer, just over the name plates (5) and
## under the HUD (20), so a panel opened over it (dialogue, shop, inventory) covers it.
const WORLD_LAYER := 6
var _world_canvas: Control
var _targets: Array[Control] = []
var _world_target: Node3D
var _world_height := ARROW_HEIGHT          # metres above the world target ("world_height" in a hint)
var _time := 0.0
## Hands-on steps of the scripting lesson, done once tried (even if the player changes the
## values back afterwards): "raised_knob", "changed_condition", "lowered_knob", "spent_points".
## Not saved: a restarted game simply shows them again.
var _lesson_done: Dictionary = {}
var _points_when_lowered := 0.0           # buff points spent when the trade-off knob went below 0
var _lesson_start_params: Array = []      # the condition's values when the rule was made
var _waypoint_map_seen := false           # the map was opened during the waypoint lesson
var _support_lesson_shown := false        # the "socket your support gem" steps were shown
var _quest_log_seen := false               # the quest lesson's log step was reached
var _route_map_seen := false               # the route lesson's map step was reached
var _clear_hint_until := -1.0              # when the area-clear lesson goes away (-1 = not shown yet)


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps running while paused, to hide the hints
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_on_canvas_draw)
	add_child(_canvas)
	var world_layer := CanvasLayer.new()
	world_layer.layer = WORLD_LAYER
	add_child(world_layer)
	_world_canvas = Control.new()
	_world_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_canvas.draw.connect(_on_world_canvas_draw)
	world_layer.add_child(_world_canvas)

	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG
	sb.border_color = COL_HINT
	sb.set_border_width_all(2)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	_banner.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_banner.add_child(box)
	var font: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	_label = _make_label(font, 20, COL_TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_label)
	_sub = _make_label(font, 15, COL_SUB)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_sub)
	_banner.visible = false
	add_child(_banner)


func _make_label(font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


func _process(delta: float) -> void:
	_time += delta
	# Paused (pause menu, the quit prompt, a game over): no hints over the menus.
	# Travelling (faded out, maybe loading): none over the black screen either.
	var hint: Dictionary = _current_hint() if enabled and not get_tree().paused \
			and not RewardChoice.is_open() and not _travelling() else {}
	var text: String = hint.get("text", "")
	var sub: String = hint.get("sub", "")
	if _label.text != text or _sub.text != sub:
		_label.text = text
		_sub.text = sub
		_sub.visible = sub != ""
		# The second line wraps at a fixed width (the first line's, within limits), so its
		# height doesn't depend on the banner's previous size
		var font := _label.get_theme_font("font")
		var line_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x if font else 400.0
		var wrap_w := clampf(line_w, 420.0, BANNER_MAX_WIDTH)
		_sub.custom_minimum_size.x = wrap_w
		_sub.size.x = wrap_w
	_banner.visible = text != ""
	if _banner.visible:
		# A wrapping label only knows its height once it has its width, which can take a frame.
		# Shrinking to the content every frame lets the banner settle at the right size
		# instead of keeping a too-tall first measurement.
		_banner.reset_size()
		var screen := _canvas.get_viewport_rect().size
		_banner.position = Vector2((screen.x - _banner.size.x) * 0.5, BANNER_Y).round()
	_targets.assign(hint.get("targets", []))
	_world_target = hint.get("world")
	_world_height = hint.get("world_height", ARROW_HEIGHT)
	_canvas.queue_redraw()
	_world_canvas.queue_redraw()


# ---------- WHICH QUEST, WHICH STEP ----------
func _current_hint() -> Dictionary:
	var player := _get_player()
	if player == null:
		return {}
	var qm: QuestManager = player.get("quests")
	if qm == null:
		return {}

	# The very first lesson: where quests live, before training's own steps
	var quests_hint := _quests_hint(qm)
	if not quests_hint.is_empty():
		return quests_hint

	# The first drop near the player: how to pick it up. Short, so it goes before the rest
	var loot_hint := _loot_hint()
	if not loot_hint.is_empty():
		return loot_hint

	# Short and only in a dungeon, so it goes before a quest step that may be waiting there
	var waypoint_hint := _waypoint_hint()
	if not waypoint_hint.is_empty():
		return waypoint_hint

	# After the waypoint lesson, in a dungeon: why clearing it is worth it
	var clear_hint := _clear_hint(qm)
	if not clear_hint.is_empty():
		return clear_hint

	# A hull breach has its own panel in the same spot: no convoy hints over it
	for b in get_tree().get_nodes_in_group("hull_breach"):
		if b.has_method("is_running") and b.is_running():
			return {}

	# On the convoy before its rank exam: Sudo first, then the road
	var road_exam := _road_exam_hint()
	if not road_exam.is_empty():
		return road_exam

	# The first time on the convoy: how its dungeons are reached
	var route_hint := _route_hint()
	if not route_hint.is_empty():
		return route_hint

	# Right after the training reward, before the nudge towards the scripting lesson
	var support_hint := _support_hint(qm)
	if not support_hint.is_empty():
		return support_hint

	var basics := qm.get_def(QUEST_BASICS)
	if basics != null and not qm.is_completed(QUEST_BASICS):
		var s: QuestState = qm.get_state(QUEST_BASICS)
		if s == null:
			# Only nudge brand-new characters; an older save that skipped training is left alone.
			if qm.can_start(basics) and qm.active.is_empty() and qm.completed_ids.is_empty():
				return {"text": "Talk to Warden Brack to start your training",
					"sub": "Walk up to him and press [%s], or click him." % Interactable.key_name(),
					"world": _get_guide()}
			return {}
		return _quest_hint(s, "Training complete. Return to Warden Brack")

	var lesson := qm.get_def(QUEST_SCRIPT)
	if lesson != null and not qm.is_completed(QUEST_SCRIPT):
		var s: QuestState = qm.get_state(QUEST_SCRIPT)
		if s == null:
			if qm.can_start(lesson) and qm.is_completed(QUEST_BASICS):
				return {"text": "Talk to Warden Brack for your first scripting lesson",
					"sub": "A green + over someone's head means they have a quest for you.",
					"world": _get_guide()}
			return {}
		return _quest_hint(s, "Lesson complete. Return to Warden Brack")
	return _exam_hint(qm)


# ---------- THE AREA CLEAR LESSON ----------
## The first time the player is in a dungeon after training (and after the waypoint lesson):
## clearing every enemy there makes every skill's script stronger. Stays up for
## CLEAR_HINT_TIME seconds, then never again; clearing an area before that ends it too.
func _clear_hint(qm: QuestManager) -> Dictionary:
	if _lesson_seen(LESSON_CLEARS):
		return {}
	if not ScriptBudget.cleared_areas(qm).is_empty():
		_mark_lesson_seen(LESSON_CLEARS)              # they found out by themselves
		return {}
	if not qm.is_completed(QUEST_BASICS) or not _lesson_seen(LESSON_WAYPOINTS) or not _in_waypoint_dungeon():
		return {}
	if _clear_hint_until < 0.0:
		_clear_hint_until = _time + CLEAR_HINT_TIME
	elif _time >= _clear_hint_until:
		_mark_lesson_seen(LESSON_CLEARS)
		return {}
	var sp := get_tree().get_first_node_in_group("skill_panel") as SkillPanel
	var sp_key := OS.get_keycode_string(sp.toggle_key) if sp != null else "K"
	var pts := ScriptBudget.POINTS_PER_CLEAR
	var waves := get_tree().get_nodes_in_group(DungeonPopulator.WAVE_EVENTS).any(
			func(n: Node) -> bool: return n.has_method("wave_event_done") and not n.wave_event_done())
	return {"text": "Clear every enemy here for +%s script point on every skill" % (
			str(int(pts)) if is_equal_approx(pts, roundf(pts)) else "%.1f" % pts),
		"sub": "Once per area%s. HOSTILE on your map counts the enemies near you. Your bonus points show in the script editor [%s]."
			% [", and this area's ward beacon must be rebooted too" if waves else "", sp_key],
		"targets": _minimap_target()}


func _minimap_target() -> Array:
	var mm := get_tree().get_first_node_in_group("minimap") as Control
	return [mm] if mm != null and mm.is_visible_in_tree() else []


# ---------- THE LOOT LESSON ----------
## The first time loot lies on the ground near the player: an arrow over the nearest drop, then
## hold the pickup key, point at it, left-click. Ends (for good) on the first drop picked up,
## which also ends it for a player who found out by themselves before it ever showed.
func _loot_hint() -> Dictionary:
	if _lesson_seen(LESSON_LOOT):
		return {}
	if LootPickup.taken > 0:
		_mark_lesson_seen(LESSON_LOOT)
		return {}
	var player := _get_player() as Node3D
	if player == null:
		return {}
	var drop := _nearest_drop(player)
	if drop == null:
		return {}
	for group in ["inventory_panel", "skill_panel"]:
		var p := get_tree().get_first_node_in_group(group)
		if p != null and p.has_method("is_open") and p.is_open():
			return {}                                 # not over the menus
	var dialogue := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if dialogue != null and dialogue.is_open():
		return {}
	var key := GemText.key_label(PickupController.PICKUP_ACTION)
	var pc := player.get_node_or_null("PickupController") as PickupController
	var hovered: LootPickup = pc.hovered() if pc != null else null
	if hovered != null:
		var inv: InventoryComponent = player.get("inventory")
		if inv != null and inv.is_full():
			var inv_panel := get_tree().get_first_node_in_group("inventory_panel") as InventoryPanel
			return {"text": "Your backpack is full",
				"sub": "Open it [%s] and sell or drop something to make room, then come back for this."
					% (OS.get_keycode_string(inv_panel.toggle_key) if inv_panel != null else "I"),
				"world": hovered, "world_height": LOOT_ARROW_HEIGHT}
		if pc.is_too_far(hovered):
			return {"text": "Walk closer to pick it up",
				"sub": "Drops can be picked up from %s m away. Keep holding [%s]." % [_num(pc.pickup_range), key],
				"world": hovered, "world_height": LOOT_ARROW_HEIGHT}
		return {"text": "Left-click to pick it up",
			"sub": "It goes into your backpack. Its stats are in the card next to the mouse: hover gear there later and hold CTRL to compare it with what you wear.",
			"world": hovered, "world_height": LOOT_ARROW_HEIGHT}
	if Input.is_action_pressed(PickupController.PICKUP_ACTION):
		return {"text": "Keep holding [%s] and point at the drop" % key,
			"sub": "Its name lights up and its stats show when the mouse is on it.",
			"world": drop, "world_height": LOOT_ARROW_HEIGHT}
	var labels := get_tree().get_first_node_in_group("loot_labels")
	var names_shown: bool = labels != null and bool(labels.get("always_show"))
	return {"text": "Loot dropped: hold [%s] and point at it" % key,
		"sub": ("Names of drops are on the ground already. " if names_shown
				else "Holding [%s] shows the names of the drops around you. " % key)
			+ "Gear, gems and items for your build come from enemies and chests.",
		"world": drop, "world_height": LOOT_ARROW_HEIGHT}


## The closest drop within LOOT_HINT_RANGE of the player, null for none.
func _nearest_drop(player: Node3D) -> LootPickup:
	var best: LootPickup = null
	var best_d := LOOT_HINT_RANGE
	for n in get_tree().get_nodes_in_group(LootPickup.GROUP):
		var p := n as LootPickup
		if p == null or not p.is_inside_tree() or p.is_queued_for_deletion():
			continue
		var d := player.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


static func _num(v: float) -> String:
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


# ---------- THE ROUTE TERMINAL LESSON ----------
## Starts the first time the player stands on a convoy (a town in an act with a route,
## WaypointAct.convoy_route): points at the route terminal, then explains the route map once
## it's open. Ends when they close the route map after opening it once.
func _route_hint() -> Dictionary:
	if _lesson_seen(LESSON_ROUTE):
		return {}
	var panel := get_tree().get_first_node_in_group("waypoint_panel") as WaypointPanel
	if panel == null:
		return {}
	if panel.is_route_open():
		_route_map_seen = true
		return {"text": "Pick a stop: the convoy drops you at its entrance",
			"sub": "Both portals in a stop lead back to the convoy. Reach a stop's exit to open the next one on the route.",
			"targets": panel.tutorial_target("map")}
	if _route_map_seen:
		_mark_lesson_seen(LESSON_ROUTE)
		return {}
	if not _in_town():
		return {}
	var act := Waypoints.act_of_scene(_current_scene_path())
	if act == null or not act.convoy_route:
		return {}
	var dialogue := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if dialogue != null and dialogue.is_open():
		return {}
	var term := _get_terminal()
	if term == null:
		return {}
	return {"text": "The convoy travels by route: use the ROUTE TERMINAL",
		"sub": "This act's dungeons are stops on the convoy's route. Walk up and press [%s], or click it. It's the R on your map."
			% Interactable.key_name(),
		"world": term}


## On a convoy whose route terminal wants a rank exam (RouteTerminal.required_exam) that the
## player hasn't passed yet: point at Examiner Sudo, not the terminal.
func _road_exam_hint() -> Dictionary:
	if not _in_town():
		return {}
	var term := _get_terminal() as RouteTerminal
	var player := get_tree().get_first_node_in_group("players") as Node3D
	if term == null or player == null or term.exam_needed(player) == "":
		return {}
	var dialogue := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if dialogue != null and dialogue.is_open():
		return {}
	return {"text": "Before the road: see Examiner Sudo",
		"sub": term.exam_needed(player) + " The route terminal stays locked until then.",
		"world": _get_examiner()}


func _get_terminal() -> Node3D:
	if _terminal != null and is_instance_valid(_terminal) and _terminal.is_inside_tree():
		return _terminal
	_terminal = null
	if _time < _terminal_search_wait:
		return null
	_terminal_search_wait = _time + 1.0
	var found := get_tree().root.find_children("*", "RouteTerminal", true, false)
	if not found.is_empty():
		_terminal = found[0] as Node3D
	return _terminal


# ---------- THE RANK EXAM LESSON ----------
## The first rank exam is a big step (it's how scripting grows), so it gets its own lesson: from
## the moment Sudo can give it, through sitting it, to handing it in. Only in town, where Sudo
## is (the sandbox shows its own spec card), and never over a conversation.
func _exam_hint(qm: QuestManager) -> Dictionary:
	if _lesson_seen(LESSON_EXAMS):
		return {}
	if qm.is_completed(FIRST_EXAM):
		_mark_lesson_seen(LESSON_EXAMS)
		return {}
	var def := qm.get_def(FIRST_EXAM)
	if def == null or not _in_town():
		return {}
	var dialogue := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if dialogue != null and dialogue.is_open():
		return {}
	var rank := Ranks.LADDER[1]["name"]
	var s: QuestState = qm.get_state(FIRST_EXAM)
	if s == null:
		if not qm.can_start(def):
			return {}
		return {"text": "RANK EXAM UNLOCKED: talk to Examiner Sudo",
			"sub": "Exams test your scripts, not your gear. Pass one to rank up to %s and unlock: %s. Exams have a purple marker."
				% [rank, ", ".join(Ranks.unlock_lines(1))],
			"world": _get_examiner()}
	if s.status == QuestState.Status.READY_TO_TURN_IN:
		return {"text": "Exam passed. Report to Examiner Sudo for your rank",
			"sub": "Your grade is kept. You can retake the exam later for a better one.",
			"world": _get_examiner()}
	return {"text": "Sit the %s exam: ask Sudo to open the sandbox" % rank,
		"sub": "Inside, a spec card says what your script must do. Edit it with [K], then press [%s] at the terminal to start. Graded PASS, MERIT or DISTINCTION."
			% Interactable.key_name(),
		"world": _get_examiner()}


func _quest_hint(s: QuestState, done_text: String) -> Dictionary:
	if s.status == QuestState.Status.READY_TO_TURN_IN:
		return {"text": done_text, "sub": "Turn the quest in to collect your reward.", "world": _get_guide()}
	for i in s.def.objectives.size():
		if not s.objective_done(i):
			return _hint_for(s.def.objectives[i], s.progress[i])
	return {}


func _hint_for(obj: Objective, progress: int) -> Dictionary:
	var inv := get_tree().get_first_node_in_group("inventory_panel") as InventoryPanel
	var sp := get_tree().get_first_node_in_group("skill_panel") as SkillPanel
	var inv_open := inv != null and inv.is_open()
	var sp_open := sp != null and sp.is_open()
	var inv_key := OS.get_keycode_string(inv.toggle_key) if inv != null else "I"
	var sp_key := OS.get_keycode_string(sp.toggle_key) if sp != null else "K"
	var sp_state: Dictionary = sp.tutorial_state() if sp != null else {}

	match obj.kind:
		"walk":
			return {"text": "Move with [%s] [%s] [%s] [%s]   %d/%d" % [
					GemText.key_label(&"forward"), GemText.key_label(&"left"),
					GemText.key_label(&"backward"), GemText.key_label(&"right"),
					progress, obj.required],
				"sub": "Try each direction. Your character turns to face the mouse."}

		"open_panel":
			match obj.target:
				"map":
					var mm := get_tree().get_first_node_in_group("minimap")
					var key := OS.get_keycode_string(int(mm.get("overlay_key"))) if mm != null else "TAB"
					return {"text": "Press [%s] to open the full map" % key,
						"sub": "It shows the whole area. Press [%s] again to close it." % key}
				"inventory":
					return {"text": "Press [%s] to open your backpack" % inv_key,
						"sub": "Your backpack holds your gear, skill gems and loot."}
				"skills":
					return {"text": "Press [%s] to open your skills" % sp_key,
						"sub": "Skill gems go into sockets here. Each socketed gem is a skill you can use."}

		"equip_slot":
			if not inv_open:
				return {"text": "Press [%s] to open your backpack" % inv_key}
			return {"text": "Right-click your weapon to equip it",
				"sub": "Double-click works too. Hold CTRL over an item to compare it with what you wear.",
				"targets": inv.tutorial_target("weapon_item") + inv.tutorial_target("weapon_slot")}

		"socket_skill":
			if sp_open:
				if sp_state.get("tab") != "sockets":
					return {"text": "Open the SOCKETS tab", "targets": sp.tutorial_target("tab_sockets")}
				if sp_state.get("picker", false):
					return {"text": "Pick your skill gem",
						"sub": "Only gems that fit this socket are listed.",
						"targets": sp.tutorial_target("picker")}
				return {"text": "Click an empty skill socket [+]",
					"sub": "A socketed skill gem becomes a skill. The small cells next to it are for support gems.",
					"targets": sp.tutorial_target("empty_socket")}
			if inv_open:
				return {"text": "Right-click the skill gem to socket it",
					"sub": "It goes into the first free skill socket.",
					"targets": inv.tutorial_target("skill_gem_item")}
			return {"text": "Press [%s] to open your skills" % sp_key}

		"bind_skill":
			var key := GemText.key_label(StringName(obj.target))
			if not sp_open:
				return {"text": "Press [%s] to open your skills" % sp_key}
			if sp_state.get("tab") != "sockets":
				return {"text": "Open the SOCKETS tab", "targets": sp.tutorial_target("tab_sockets")}
			if sp_state.get("pending") != StringName(obj.target):
				return {"text": "Click the [%s] hotkey slot" % key,
					"sub": "The row at the top is your hotkeys. Pick one, then pick the skill to put on it.",
					"targets": sp.tutorial_target("hotkey_" + obj.target)}
			return {"text": "Now click your skill to put it on [%s]" % key,
				"sub": "Right-click a hotkey slot later to clear it.",
				"targets": sp.tutorial_target("filled_socket")}

		"cast":
			if inv_open or sp_open:
				return {"text": "Close the menus [ESC], then use your skill"}
			var key := GemText.key_label(StringName(obj.target)) if obj.target != "" else "your skill key"
			return {"text": "Press [%s] to use your skill   %d/%d" % [key, progress, obj.required],
				"sub": "Each use costs mana (the blue bar). It refills over time."}

		"program_condition":
			var warn := _skill_missing_hint(obj, false, inv, sp, inv_open, sp_open, sp_key, sp_state)
			if not warn.is_empty():
				return warn
			return _script_hint(obj, sp, sp_open, sp_key, sp_state)

		"rule_triggered":
			var warn := _skill_missing_hint(obj, true, inv, sp, inv_open, sp_open, sp_key, sp_state)
			if not warn.is_empty():
				return warn
			return _fight_hint(obj, progress, inv_open or sp_open)

		"program_applied":
			var warn := _skill_missing_hint(obj, false, inv, sp, inv_open, sp_open, sp_key, sp_state)
			if not warn.is_empty():
				return warn
			if not sp_open:
				return {"text": "Press [%s], then open the SCRIPTING tab" % sp_key}
			if sp_state.get("tab") != "scripting":
				return {"text": "Open the SCRIPTING tab", "targets": sp.tutorial_target("tab_script")}
			return {"text": "Click a snippet to add a rule, then press apply()",
				"targets": sp.tutorial_target("script_palette") + sp.tutorial_target("script_apply")}

	return {"text": obj.description}


# ---------- THE SCRIPTING LESSON ----------
## Walks the player through writing  when <condition>(): damage += ...  and applying it.
## Each step checks the editor, so going back (deleting the rule, breaking it) shows the
## right step again.
func _script_hint(obj: Objective, sp: SkillPanel, sp_open: bool, sp_key: String, sp_state: Dictionary) -> Dictionary:
	var cond := obj.target
	var fn := cond + "()"
	if not sp_open:
		return {"text": "Press [%s] to open your skills" % sp_key,
			"sub": "Scripts are written in the skill menu. You'll make your skill hit harder when enemies crowd you."}
	if sp_state.get("tab") != "scripting":
		return {"text": "Open the SCRIPTING tab",
			"sub": "A script is a few small rules that change how a skill behaves.",
			"targets": sp.tutorial_target("tab_script")}
	# The first time the lesson reaches the editor: the SCRIPTING GUIDE opens by itself
	if not _lesson_seen(LESSON_GUIDE):
		_mark_lesson_seen(LESSON_GUIDE)
		sp.open_script_guide("start")
	if sp.script_guide_open():
		return {"text": "Read the SCRIPTING GUIDE, or press [ESC] to skip it",
			"sub": "Skipping is fine: tips show in OUTPUT as you build. guide() at the top of the editor opens the guide any time.",
			"targets": sp.tutorial_target("script:guide")}
	var st: Dictionary = sp.tutorial_script_state(cond)
	if not st.get("has_socket", false):
		return {"text": "Socket a skill gem first",
			"sub": "Go back to the SOCKETS tab: only a socketed skill can be scripted."}
	if st.get("owner", "") != "":
		return {"text": "Click your skill's file at the top of the list",
			"sub": "The list on the left works like files: your skill, and under it any support gems.",
			"targets": sp.tutorial_target("script:skill_file")}
	if not st.get("rule", false):
		return {"text": "Click  %s  in SNIPPETS on the right" % fn,
			"sub": "It starts a new rule:  when %s:  Whatever you put under it only happens while 3+ enemies are within 4 m of you." % fn,
			"targets": sp.tutorial_target("script:cond:" + cond)}
	if st.get("effects", 0) == 0:
		if not st.get("selected", false):
			return {"text": "Click your  when %s  line to select the rule" % fn,
				"sub": "Snippets you click go into the selected rule. It's marked with a bar on its left.",
				"targets": sp.tutorial_target("script:rule_line:" + cond)}
		return {"text": "Now click  damage  in SNIPPETS, under knobs",
			"sub": "Knobs are what a rule changes. This adds  damage += ...  under your rule: more damage, but only while enemies are close.",
			"targets": sp.tutorial_target("script:knob:damage")}

	# Hands-on: change a knob, then the condition, and watch what each does to the cost
	var points := "%.1f of %.1f points used" % [st.get("points", 0.0), st.get("budget", 0.0)]
	var params: Array = st.get("params", [])
	if _lesson_start_params.is_empty() or _lesson_start_params.size() != params.size():
		_lesson_start_params = params.duplicate()
	if not _lesson_done.has("raised_knob"):
		if int(st.get("knob_steps", 0)) >= 2:
			_lesson_done["raised_knob"] = true
		else:
			return {"text": "Click the orange number on the damage line to raise it",
				"sub": "Numbers are buttons: click raises, right-click lowers, the wheel does both. Each step adds damage and costs more points. Now: %s." % points,
				"targets": sp.tutorial_target("script:knob_number:%s:damage" % cond)}
	if not _lesson_done.has("changed_condition"):
		if params != _lesson_start_params:
			_lesson_done["changed_condition"] = true
		else:
			var why := "Needing more enemies makes the rule rarer, so its buffs get cheaper: now buffs x%.2f. A wider radius does the opposite." \
				% float(st.get("discount", 1.0))
			if st.get("over", false):
				why = "You're over budget (%s). Needing more enemies makes buffs cheaper, which can bring you back under: now buffs x%.2f." \
					% [points, float(st.get("discount", 1.0))]
			return {"text": "Now click the enemy count in  when %s" % fn,
				"sub": why,
				"targets": sp.tutorial_target("script:cond_numbers:" + cond)}
	# Trade-off: lowering a knob in an always: rule pays points back, for any other knob
	var trade: String = st.get("trade_knob", "attack_speed")
	var trade_name := trade.replace("_", " ")
	if not _lesson_done.has("lowered_knob"):
		if float(st.get("drawback_points", 0.0)) > 0.0:
			_lesson_done["lowered_knob"] = true
			_points_when_lowered = float(st.get("points", 0.0))
		elif not st.get("always_rule", false):
			if st.get("any_selected", false):
				return {"text": "Click the  drop a snippet here  line to start a new rule",
					"sub": "Knobs can cost points, or give them back. Next you'll trade a little %s for more damage." % trade_name,
					"targets": sp.tutorial_target("script:new_rule")}
			return {"text": "Click  %s  in SNIPPETS" % trade,
				"sub": "A rule with no condition is  always:  it's on all the time. %s can only be changed in an always: rule." % trade_name.capitalize(),
				"targets": sp.tutorial_target("script:knob:" + trade)}
		elif not st.get("trade_line", false) and not st.get("always_selected", false):
			return {"text": "Click your  always:  line to select it",
				"sub": "Then  %s  in SNIPPETS goes into that rule." % trade,
				"targets": sp.tutorial_target("script:always_line")}
		elif not st.get("trade_line", false):
			return {"text": "Click  %s  in SNIPPETS" % trade,
				"sub": "It goes into your always: rule. %s can only be changed there." % trade_name.capitalize(),
				"targets": sp.tutorial_target("script:knob:" + trade)}
		else:
			var at := int(st.get("trade_steps", 0))
			var left := "It's at 0 now: one more right-click." if at == 0 					else "%d more right-clicks." % (at + 1)
			return {"text": "Right-click the  %s  number until it goes below 0" % trade,
				"sub": "%s Lowering a knob is a drawback: your skill gets a little slower, and you get points back that ANY rule can spend. Now: %s." % [left, points],
				"targets": sp.tutorial_target("script:always_knob_number:" + trade)}
	if not _lesson_done.has("spent_points"):
		if float(st.get("points", 0.0)) > _points_when_lowered + 0.01:
			_lesson_done["spent_points"] = true
		else:
			return {"text": "Spend them: click the damage number in  when %s  again" % fn,
				"sub": "You gave up some %s for more damage when you're crowded. Any knob trades the same way: lower what you need least, raise what you need most. Now: %s." % [trade_name, points],
				"targets": sp.tutorial_target("script:knob_number:%s:damage" % cond)}
	if not st.get("valid", false):
		var fix := "Hover the red line in the code to see how to fix it."
		if st.get("over", false):
			fix = "Over budget (%s): right-click the damage number to lower it, or raise the enemy count for a bigger discount." % points
		return {"text": "Your script has an error: read OUTPUT", "sub": fix,
			"targets": sp.tutorial_target("script:output")}
	if st.get("dirty", false):
		return {"text": "Press  apply()  to run your script",
			"sub": "Until then it's only a draft. Your rule uses %s, with buffs at x%.2f because it doesn't always fire." \
				% [points, float(st.get("discount", 1.0))],
			"targets": sp.tutorial_target("script:apply") + sp.tutorial_target("script:rule_line:" + cond)}
	return {"text": "Press  apply()  to run your script", "targets": sp.tutorial_target("script:apply")}


# ---------- THE QUEST LESSON ----------
## Once a new character has their first quest (training, from Brack): the tracker, then the
## quest log it opens. Closing the log ends it. Characters that already finished a quest skip it.
func _quests_hint(qm: QuestManager) -> Dictionary:
	if _lesson_seen(LESSON_QUESTS) or qm.active.is_empty():
		return {}
	if not qm.completed_ids.is_empty():
		_mark_lesson_seen(LESSON_QUESTS)          # an older save: they know the tracker already
		return {}
	var dialogue := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if dialogue != null and dialogue.is_open():
		return {}                                 # wait until Brack has finished talking
	var tracker := get_tree().get_first_node_in_group("quest_tracker") as QuestTracker
	var log_panel := get_tree().get_first_node_in_group("quest_log") as QuestLogPanel
	if tracker == null or log_panel == null:
		return {}
	if log_panel.is_open():
		_quest_log_seen = true
		return {"text": "The quest log: every quest you have, and what's left to do",
			"sub": "Pick a quest on the left to read it in full. Press [J] or [ESC] to close it.",
			"targets": [log_panel]}
	if _quest_log_seen:
		_mark_lesson_seen(LESSON_QUESTS)
		return {}
	return {"text": "This is your quest tracker",
		"sub": "It shows your quests and what each one needs next. Click it, or press [J], to open the quest log.",
		"targets": tracker.tutorial_target()}


# ---------- THE SUPPORT GEM LESSON ----------
## Starts once training is turned in and its support gem is picked (it lands in the backpack).
## Walks the player through socketing it next to their skill, then shows what it changed and
## points at the SCRIPTING tab: opening it starts Brack's scripting lesson on the spot
## (_start_script_lesson). Closing the menu instead ends it; Brack offers the lesson as usual.
func _support_hint(qm: QuestManager) -> Dictionary:
	if _lesson_seen(LESSON_SUPPORTS) or not qm.is_completed(QUEST_BASICS) or not qm.pending_choices.is_empty():
		return {}
	var player := _get_player()
	var skills: SkillComponent = player.get("skills")
	var inv_comp: InventoryComponent = player.get("inventory")
	if skills == null or inv_comp == null:
		return {}
	var inv := get_tree().get_first_node_in_group("inventory_panel") as InventoryPanel
	var sp := get_tree().get_first_node_in_group("skill_panel") as SkillPanel
	var inv_open := inv != null and inv.is_open()
	var sp_open := sp != null and sp.is_open()
	var sp_key := OS.get_keycode_string(sp.toggle_key) if sp != null else "K"
	var sp_state: Dictionary = sp.tutorial_state() if sp != null else {}

	var socketed: ItemInstance = null            # a support gem already next to a skill
	var has_skill := false
	for s in skills.sockets:
		has_skill = has_skill or s.gem != null
		if socketed == null and not s.supports.is_empty():
			socketed = s.supports[0]
	var in_backpack := false
	for it in inv_comp.items:
		if it != null and it.definition.support_gem != null:
			in_backpack = true
			break

	if socketed != null:
		if not _support_lesson_shown:
			_mark_lesson_seen(LESSON_SUPPORTS)   # socketed before the lesson ever showed (older save)
			return {}
		if not sp_open:
			_mark_lesson_seen(LESSON_SUPPORTS)
			return {}
		if sp_state.get("tab") == "scripting":
			# Straight on to the scripting lesson, without closing the menu to fetch it from Brack
			_mark_lesson_seen(LESSON_SUPPORTS)
			_start_script_lesson(qm)
			return {}
		return {"text": "%s now changes your skill" % socketed.definition.support_gem.display_name,
			"sub": "Hover it to read what it does. Right-click it to take it out again. Next, your first script: open the SCRIPTING tab.",
			"targets": sp.tutorial_target("filled_support") + sp.tutorial_target("tab_script")}

	if not in_backpack:
		return {}                                # sold or not picked: nothing to teach with
	_support_lesson_shown = true
	var why := "Support gems go in the small cells next to a skill and change how that skill works."
	if not has_skill:
		return {"text": "Socket your skill gem first", "sub": why}
	if sp_open:
		if sp_state.get("tab") != "sockets":
			return {"text": "Open the SOCKETS tab", "sub": why, "targets": sp.tutorial_target("tab_sockets")}
		if sp_state.get("picker", false):
			return {"text": "Pick your support gem",
				"sub": "Only supports that work with this skill are listed.",
				"targets": sp.tutorial_target("picker")}
		return {"text": "Click an empty support cell next to your skill", "sub": why,
			"targets": sp.tutorial_target("empty_support")}
	if inv_open:
		var gem := inv.tutorial_target("support_gem_item")
		if not gem.is_empty():
			return {"text": "Right-click the support gem to socket it",
				"sub": "It goes next to the first skill it works with.", "targets": gem}
	return {"text": "You got a support gem: press [%s] to socket it" % sp_key, "sub": why}


## Starts PROXIMITY TRIGGER (Brack's scripting lesson) from the skill menu, with Brack's
## opening line as a toast. Turned in to Brack as usual once it's done.
func _start_script_lesson(qm: QuestManager) -> void:
	var lesson := qm.get_def(QUEST_SCRIPT)
	if lesson == null or not qm.can_start(lesson):
		return
	qm.start(lesson)
	QuestItems.toast(get_tree(), "WARDEN BRACK: Before you face anything real, teach your skill to think.\nYour first script: make it fire when enemies close in.")


# ---------- THE WAYPOINT LESSON ----------
## Starts the first time the player stands in a dungeon that has a waypoint (arriving there
## just unlocked it), and ends when they close the waypoint map after opening it once.
func _waypoint_hint() -> Dictionary:
	if _lesson_seen(LESSON_WAYPOINTS):
		return {}
	var panel := get_tree().get_first_node_in_group("waypoint_panel") as WaypointPanel
	if panel == null:
		return {}
	var key := GemText.key_label(WaypointPanel.ACTION)
	if panel.is_open():
		if not _waypoint_map_seen and not _in_waypoint_dungeon():
			return {}                             # opened in town before ever reaching a dungeon
		_waypoint_map_seen = true
		return {"text": "Lit places are unlocked. Click one to travel there",
			"sub": "Use it to get back to town and return to a dungeon later. Ctrl + click a dungeon for a fresh layout. Press [%s] to close." % key,
			"targets": panel.tutorial_target("map")}
	if _waypoint_map_seen:
		_mark_lesson_seen(LESSON_WAYPOINTS)
		return {}
	if not _in_waypoint_dungeon():
		return {}
	var w := Waypoints.for_scene(_current_scene_path())
	return {"text": "Waypoint unlocked: %s" % w.display_name,
		"sub": "Every area you reach is added to your waypoint map. Press [%s] to open it." % key}


func _in_waypoint_dungeon() -> bool:
	if _in_town():
		return false
	var w := Waypoints.for_scene(_current_scene_path())
	return w != null and w.kind != Waypoint.Kind.TOWN and Waypoints.is_discovered(w)


func _current_scene_path() -> String:
	var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
	return am.current_scene_path() if am != null else ""


## Lessons outside the quests are saved with the host's character (seat 0).
func _lesson_seen(id: String) -> bool:
	if SaveManager.party.is_empty():
		return false
	return id in SaveManager.get_data(SaveManager.party[0]).get(SAVE_KEY_DONE, [])


func _mark_lesson_seen(id: String) -> void:
	for slot in SaveManager.party:
		var data: Dictionary = SaveManager.get_data(slot)
		var done: Array = data.get(SAVE_KEY_DONE, [])
		if not id in done:
			done.append(id)
		data[SAVE_KEY_DONE] = done


## Warns while the scripting lesson can't go on: no skill gem in any socket, or (need_hotkey,
## the fight step) the scripted skill isn't on a hotkey so it can't be used. {} when all is set.
func _skill_missing_hint(obj: Objective, need_hotkey: bool, inv: InventoryPanel, sp: SkillPanel,
		inv_open: bool, sp_open: bool, sp_key: String, sp_state: Dictionary) -> Dictionary:
	var player := _get_player()
	var skills: SkillComponent = player.get("skills") if player != null else null
	if skills == null:
		return {}

	var socketed := -1                         # the scripted socket, else the first with a gem
	for i in skills.sockets.size():
		var s := skills.sockets[i]
		if s.gem == null:
			continue
		if socketed < 0:
			socketed = i
		if s.program != null and _program_uses(s.program, obj.target):
			socketed = i
			break

	if socketed < 0:
		var why := "Scripts change how a skill behaves, so you need a skill gem in a socket first."
		if sp_open:
			if sp_state.get("tab") != "sockets":
				return {"text": "No skill equipped: open the SOCKETS tab", "sub": why,
					"targets": sp.tutorial_target("tab_sockets")}
			if sp_state.get("picker", false):
				return {"text": "Pick your skill gem", "sub": why, "targets": sp.tutorial_target("picker")}
			return {"text": "No skill equipped: click an empty skill socket [+]", "sub": why,
				"targets": sp.tutorial_target("empty_socket")}
		if inv_open:
			var gem := inv.tutorial_target("skill_gem_item")
			if not gem.is_empty():
				return {"text": "No skill equipped: right-click the skill gem to socket it", "sub": why,
					"targets": gem}
		return {"text": "No skill equipped: press [%s] and socket a skill gem" % sp_key, "sub": why}

	if not need_hotkey or skills.action_of(socketed) != &"":
		return {}
	var why_key := "Your rule only fires when you use the skill, and a skill needs a hotkey to be used."
	if not sp_open:
		return {"text": "Your skill isn't on a hotkey: press [%s]" % sp_key, "sub": why_key}
	if sp_state.get("tab") != "sockets":
		return {"text": "Open the SOCKETS tab", "sub": why_key, "targets": sp.tutorial_target("tab_sockets")}
	if sp_state.get("pending", &"") == &"":
		var slots: Array[Control] = []
		for action in SkillComponent.ACTIONS:
			slots.append_array(sp.tutorial_target("hotkey_" + String(action)))
		return {"text": "Click a hotkey slot for your skill", "sub": why_key, "targets": slots}
	return {"text": "Now click your skill to put it on [%s]" % GemText.key_label(sp_state.get("pending")),
		"sub": why_key, "targets": sp.tutorial_target("filled_socket")}


func _program_uses(program: SkillProgram, condition_id: String) -> bool:
	for rule in program.rules:
		for c in rule.conditions:
			if c.type_id() == condition_id:
				return true
	return false


func _fight_hint(obj: Objective, progress: int, menus_open: bool) -> Dictionary:
	var condition_text := _rule_condition_text(obj.target)
	if menus_open:
		return {"text": "Close the menus [ESC] and find a fight",
			"sub": "Your rule only fires in combat, when %s." % condition_text}
	if _in_town():
		return {"text": "Take a portal to a dungeon",
			"sub": "Your rule needs enemies. It fires when %s, and the town is safe." % condition_text,
			"world": _nearest_dungeon_portal()}
	return {"text": "Use your skill with %s   %d/%d" % [condition_text, progress, obj.required],
		"sub": "Let a group close in, then attack: each use while the rule is true counts."}


## "3+ enemies within 4.0 m", read from the player's applied script.
func _rule_condition_text(condition_id: String) -> String:
	var player := _get_player()
	var skills: SkillComponent = player.get("skills") if player != null else null
	if skills != null:
		for s in skills.sockets:
			if s.program == null:
				continue
			for rule in s.program.rules:
				for c in rule.conditions:
					if c.type_id() == condition_id:
						return c.describe().trim_prefix("WHEN ")
	return "enough enemies are close"


func _travelling() -> bool:
	var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
	return am != null and am.is_busy()


func _in_town() -> bool:
	var am := get_tree().get_first_node_in_group("area_manager")
	return am != null and am.get("current_area") is TownArea


## The closest portal that leads into a dungeon (not another town).
func _nearest_dungeon_portal() -> Node3D:
	var player := _get_player() as Node3D
	if player == null:
		return null
	var best: Node3D = null
	var best_d := INF
	for p in NpcNameplates.portals():
		if not is_instance_valid(p) or not p.is_inside_tree():
			continue
		var w: Waypoint = Waypoints.for_scene(p.target_area) if p.target_area != "" else null
		if p.dungeon_level <= 0 and (w == null or w.kind == Waypoint.Kind.TOWN):
			continue
		var d := player.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


# ---------- FINDING THINGS ----------
func _get_player() -> Node:
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("players")
	return _player


## Warden Brack's NPC node, searched for at most once a second while it's missing
## (he only exists in town).
func _get_guide() -> Node3D:
	if _guide != null and is_instance_valid(_guide) and _guide.is_inside_tree():
		return _guide
	_guide = null
	if _time < _guide_search_wait:
		return null
	_guide_search_wait = _time + 1.0
	for n in get_tree().root.find_children("*", "Area3D", true, false):
		if n.get("npc_id") == GUIDE_NPC_ID:
			_guide = n as Node3D
			break
	return _guide


## Examiner Sudo's NPC node, found the same way as Brack's.
func _get_examiner() -> Node3D:
	if _examiner != null and is_instance_valid(_examiner) and _examiner.is_inside_tree():
		return _examiner
	_examiner = null
	if _time < _examiner_search_wait:
		return null
	_examiner_search_wait = _time + 1.0
	for n in get_tree().root.find_children("*", "Area3D", true, false):
		if n.get("npc_id") == EXAMINER_NPC_ID:
			_examiner = n as Node3D
			break
	return _examiner


# ---------- DRAWING ----------
func _on_canvas_draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	var line := Color(COL_HINT, 0.55 + 0.45 * pulse)
	for t in _targets:
		if not is_instance_valid(t) or not t.is_visible_in_tree():
			continue
		var r := _screen_rect(t).grow(4.0 + 3.0 * pulse)
		_canvas.draw_rect(r, Color(COL_HINT, 0.10 * pulse), true)
		_canvas.draw_rect(r, line, false, 3.0)


func _on_world_canvas_draw() -> void:
	var line := Color(COL_HINT, 0.55 + 0.45 * (0.5 + 0.5 * sin(_time * 5.0)))
	if _world_target != null and is_instance_valid(_world_target):
		_draw_world_arrow(_world_target.global_position + Vector3.UP * _world_height, line,
				NpcNameplates.top_of(_world_target))


## A control's rectangle on screen, through any CanvasLayer it sits in.
func _screen_rect(c: Control) -> Rect2:
	var xf := c.get_global_transform_with_canvas()
	return Rect2(xf.origin, c.size * xf.get_scale())


## A bobbing arrow over a point in the world, or an arrow on the screen edge pointing
## towards it when it's off camera. `above_y` (screen y, NAN for none) is the top of an NPC's
## name plate and quest badge: the arrow stays over it instead of covering it.
func _draw_world_arrow(pos: Vector3, col: Color, above_y: float = NAN) -> void:
	var pr: Dictionary = NpcNameplates.project(pos)   # same projection as the name plates
	if pr.is_empty():
		return
	var screen := _world_canvas.get_viewport_rect().size
	var behind: bool = pr["behind"]
	var p: Vector2 = pr["pos"]
	var inner := Rect2(Vector2(EDGE_MARGIN, EDGE_MARGIN), screen - Vector2(EDGE_MARGIN, EDGE_MARGIN) * 2.0)

	if not behind and not is_nan(above_y):
		p.y = minf(p.y, above_y - 18.0)        # 18 = the bob below plus a small gap
	if not behind and inner.has_point(p):
		var tip := p + Vector2(0.0, sin(_time * 4.0) * 6.0)
		_world_canvas.draw_colored_polygon(PackedVector2Array([
			tip, tip + Vector2(-14.0, -24.0), tip + Vector2(14.0, -24.0)]), col)
		return

	var centre := screen * 0.5
	var dir := p - centre
	if behind:
		dir = -dir
	if dir.length() < 1.0:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var half := inner.size * 0.5
	var reach := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var tip := centre + dir * reach
	var side := dir.orthogonal()
	_world_canvas.draw_colored_polygon(PackedVector2Array([
		tip, tip - dir * 26.0 + side * 15.0, tip - dir * 26.0 - side * 15.0]), col)
