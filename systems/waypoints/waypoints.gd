class_name Waypoints
extends RefCounted
## Which waypoints the party has discovered, and teleporting to them.
##
## A waypoint is discovered the first time a player arrives in its scene (AreaManager calls
## arrived()). Discoveries are kept in the host's save (seat 0) under "waypoints" and copied to
## every seated character, so they survive quitting.
##
## The acts are read from ACT_FOLDER: every WaypointAct .tres there, ordered by act_number.
## To add Act II: make data/waypoints/act_2.tres with its towns and dungeons. Nothing else.

const ACT_FOLDER := "res://data/waypoints/"
const SAVE_KEY := "waypoints"
## Convoy stops whose exit portal has been reached (Portal.clears_stop), saved like the waypoints.
const SAVE_KEY_CLEARED := "route_cleared"

static var _acts: Array[WaypointAct] = []
static var _visited: Dictionary = {}          # waypoint id -> true
static var _cleared: Dictionary = {}          # convoy stop id -> true
static var _loaded_for := -2                  # save slot _visited was read from (-1 = no save)


# ---------- ACTS ----------
static func acts() -> Array[WaypointAct]:
	if _acts.is_empty():
		var dir := DirAccess.open(ACT_FOLDER)
		if dir == null:
			push_warning("Waypoints: no folder %s" % ACT_FOLDER)
			return _acts
		for file in dir.get_files():
			var f := file.trim_suffix(".remap")          # exported builds rename resources
			if not f.ends_with(".tres"):
				continue
			var act := load(ACT_FOLDER.path_join(f)) as WaypointAct
			if act != null:
				_acts.append(act)
		_acts.sort_custom(func(a: WaypointAct, b: WaypointAct) -> bool:
			return a.act_number < b.act_number)
	return _acts


## The waypoint for a scene, in whichever act lists it (null if none does).
static func for_scene(scene_path: String) -> Waypoint:
	for act in acts():
		var w := act.find_by_scene(scene_path)
		if w != null:
			return w
	return null


## The highest dungeon level on an act's map (Act I: 10, Act II: 20). Town shops stock at it.
static func top_level(act: WaypointAct) -> int:
	var best := 0
	if act != null:
		for w in act.waypoints:
			best = maxi(best, w.dungeon_level)
	return best


static func act_of_scene(scene_path: String) -> WaypointAct:
	for act in acts():
		if act.find_by_scene(scene_path) != null:
			return act
	return null


# ---------- DISCOVERY ----------
static func is_discovered(w: Waypoint) -> bool:
	_ensure_loaded()
	return w != null and _visited.has(w.id)


## Called by AreaManager every time a player is placed in an area.
## Returns true when this visit discovered a new waypoint.
static func arrived(scene_path: String) -> bool:
	_ensure_loaded()
	var w := for_scene(scene_path)
	if w == null or _visited.has(w.id):
		return false
	_visited[w.id] = true
	_write_to_saves()
	print("[Waypoints] discovered %s" % w.display_name)
	return true


static func _ensure_loaded() -> void:
	var slot: int = SaveManager.party[0] if not SaveManager.party.is_empty() else -1
	if slot == _loaded_for:
		return
	_loaded_for = slot
	_visited.clear()
	_cleared.clear()
	if slot < 0:
		return                                    # no character loaded (running a scene with F6)
	for id in SaveManager.get_data(slot).get(SAVE_KEY, []):
		_visited[str(id)] = true
	for id in SaveManager.get_data(slot).get(SAVE_KEY_CLEARED, []):
		_cleared[str(id)] = true


static func _write_to_saves() -> void:
	var ids: Array = _visited.keys()
	var cleared: Array = _cleared.keys()
	for slot in SaveManager.party:
		SaveManager.get_data(slot)[SAVE_KEY] = ids.duplicate()
		SaveManager.get_data(slot)[SAVE_KEY_CLEARED] = cleared.duplicate()


# ---------- THE CONVOY ROUTE ----------
## A dungeon on a convoy act: reached from the route terminal, not the waypoint map.
static func is_convoy_stop(w: Waypoint) -> bool:
	if w == null or w.kind == Waypoint.Kind.TOWN:
		return false
	var act := act_of_scene(w.scene)
	return act != null and act.convoy_route


static func is_cleared(w: Waypoint) -> bool:
	_ensure_loaded()
	return w != null and _cleared.has(w.id)


## True when the route terminal can send the party to this stop: the first stop always, the
## others once the stop before them (route_after) is cleared.
static func route_open(w: Waypoint) -> bool:
	if not is_convoy_stop(w):
		return false
	if w.route_after == "":
		return true
	var act := act_of_scene(w.scene)
	return is_cleared(act.find(w.route_after))


## Marks a convoy stop cleared (its exit portal was reached). Returns the stops this opened, so
## the portal can say so; empty when it was already cleared.
static func clear_stop(id: String) -> Array[Waypoint]:
	_ensure_loaded()
	var opened: Array[Waypoint] = []
	if id == "" or _cleared.has(id):
		return opened
	_cleared[id] = true
	_write_to_saves()
	for act in acts():
		for w in act.waypoints:
			if w.route_after == id:
				opened.append(w)
	return opened


## Why the route terminal can't send the party to `w` now, or "" if it can.
static func route_blocked_reason(w: Waypoint, tree: SceneTree) -> String:
	if not route_open(w):
		var act := act_of_scene(w.scene)
		var before := act.find(w.route_after) if act != null else null
		return "LOCKED: CLEAR %s FIRST" % (before.display_name.to_upper() if before else "THE STOP BEFORE")
	var am := tree.get_first_node_in_group("area_manager") as AreaManager
	if am == null:
		return "NO AREA MANAGER"
	if am.is_busy():
		return "TRAVELLING..."
	return ""


## Sends the party from the route terminal to a stop's entrance. Rejoins its open instance like
## walking in through a portal, but always at the entrance, not where they last stood.
static func sail(w: Waypoint, tree: SceneTree) -> bool:
	if route_blocked_reason(w, tree) != "":
		return false
	var am := tree.get_first_node_in_group("area_manager") as AreaManager
	am.go_to(w.scene, w.spawn_id, w.dungeon_level)
	return true


# ---------- TRAVEL ----------
## Why `w` can't be travelled to right now, or "" if it can.
## new_instance: Ctrl + click, which may also reroll the dungeon you are standing in.
static func blocked_reason(w: Waypoint, tree: SceneTree, new_instance := false) -> String:
	if not is_discovered(w):
		return "UNDISCOVERED"
	if is_convoy_stop(w):
		return "BOARD THE CONVOY: USE ITS ROUTE TERMINAL"
	var am := tree.get_first_node_in_group("area_manager") as AreaManager
	if am == null:
		return "NO AREA MANAGER"
	if am.is_busy():
		return "TRAVELLING..."
	if normalize(am.current_scene_path()) == normalize(w.scene) and not (new_instance and is_instanced(w)):
		return "YOU ARE HERE"
	for p in tree.get_nodes_in_group("players"):
		var h = p.get("health")
		if h != null and h.current_health <= 0.0:
			return "YOU ARE DEAD"
	return ""


## Teleports the party to a discovered waypoint. Dungeons rejoin their open instance
## (same layout, dead enemies stay dead), like walking back in through the portal.
## new_instance (Ctrl + click, like Path of Exile): always a fresh dungeon instance instead.
static func travel(w: Waypoint, tree: SceneTree, new_instance := false) -> bool:
	if blocked_reason(w, tree, new_instance) != "":
		return false
	var am := tree.get_first_node_in_group("area_manager") as AreaManager
	am.travel(w.scene, w.spawn_id, w.dungeon_level, new_instance and is_instanced(w))
	return true


## Dungeons (anything with a level) have instances; towns don't.
static func is_instanced(w: Waypoint) -> bool:
	return w != null and w.dungeon_level > 0


## "uid://..." and "res://..." spellings of the same scene compare equal after this.
static func normalize(path: String) -> String:
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return path
