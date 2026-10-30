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

static var _acts: Array[WaypointAct] = []
static var _visited: Dictionary = {}          # waypoint id -> true
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
	if slot < 0:
		return                                    # no character loaded (running a scene with F6)
	for id in SaveManager.get_data(slot).get(SAVE_KEY, []):
		_visited[str(id)] = true


static func _write_to_saves() -> void:
	var ids: Array = _visited.keys()
	for slot in SaveManager.party:
		SaveManager.get_data(slot)[SAVE_KEY] = ids.duplicate()


# ---------- TRAVEL ----------
## Why `w` can't be travelled to right now, or "" if it can.
## new_instance: Ctrl + click, which may also reroll the dungeon you are standing in.
static func blocked_reason(w: Waypoint, tree: SceneTree, new_instance := false) -> String:
	if not is_discovered(w):
		return "UNDISCOVERED"
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
