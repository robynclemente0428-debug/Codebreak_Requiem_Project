class_name Waypoints
extends RefCounted

const ACT_FOLDER := "res://data/waypoints/"
const SAVE_KEY := "waypoints"
const SAVE_KEY_CLEARED := "route_cleared"
const FINISH_DEED := "stop_finished"

static var _acts: Array[WaypointAct] = []
static var _visited: Dictionary = {}
static var _cleared: Dictionary = {}
static var _loaded_for := -2


const DOCKED_QUEST := "q04c_the_last_mile"


static func acts() -> Array[WaypointAct]:
	if _acts.is_empty():
		var dir := DirAccess.open(ACT_FOLDER)
		if dir == null:
			push_warning("Waypoints: no folder %s" % ACT_FOLDER)
			return _acts
		for file in dir.get_files():
			var f := file.trim_suffix(".remap")
			if not f.ends_with(".tres"):
				continue
			var act := load(ACT_FOLDER.path_join(f)) as WaypointAct
			if act != null:
				_acts.append(act)
		_acts.sort_custom(func(a: WaypointAct, b: WaypointAct) -> bool:
			return a.act_number < b.act_number)
	return _acts


static func for_scene(scene_path: String) -> Waypoint:
	for act in acts():
		var w := act.find_by_scene(scene_path)
		if w != null:
			return w
	return null


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


static func is_discovered(w: Waypoint) -> bool:
	_ensure_loaded()
	return w != null and _visited.has(w.id)


static func arrived(scene_path: String) -> bool:
	_ensure_loaded()
	var w := for_scene(scene_path)
	if w == null or _visited.has(w.id):
		return false
	if Coop.visiting:
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
		return
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


static func is_convoy_stop(w: Waypoint) -> bool:
	if w == null or w.kind == Waypoint.Kind.TOWN or w.on_foot:
		return false
	var act := act_of_scene(w.scene)
	return act != null and act.convoy_route


static func is_cleared(w: Waypoint) -> bool:
	_ensure_loaded()
	return w != null and _cleared.has(w.id)


static func route_open(w: Waypoint) -> bool:
	if not is_convoy_stop(w):
		return false
	if not route_key_ok(w):
		return false
	if w.route_after == "" or is_cleared(w):
		return true
	var act := act_of_scene(w.scene)
	return is_cleared(act.find(w.route_after))


static func route_key_ok(w: Waypoint) -> bool:
	if w == null or (w.route_needs_key == "" and w.route_needs_quests.is_empty()):
		return true
	var tree := Engine.get_main_loop() as SceneTree
	var player := tree.get_first_node_in_group("players") if tree != null else null
	var qm = player.get("quests") if player != null else null
	if qm == null or (w.route_needs_key != "" and not qm.has_recovered(w.route_needs_key)):
		return false
	for id in w.route_needs_quests:
		if not qm.is_completed(id):
			return false
	return true


static func clear_stop(id: String) -> Array[Waypoint]:
	_ensure_loaded()
	var opened: Array[Waypoint] = []
	if id == "" or _cleared.has(id) or Coop.visiting:
		return opened
	_cleared[id] = true
	_write_to_saves()
	for act in acts():
		for w in act.waypoints:
			if w.route_after == id:
				opened.append(w)
	return opened


static func route_blocked_reason(w: Waypoint, tree: SceneTree) -> String:
	if not route_key_ok(w):
		return w.route_needs_text if w.route_needs_text != "" 				else "LOCKED: NEEDS %s" % QuestItems.name_of(w.route_needs_key)
	if not route_open(w):
		var act := act_of_scene(w.scene)
		var before := act.find(w.route_after) if act != null else null
		return "LOCKED: CLEAR %s FIRST" % (before.display_name.to_upper() if before else "THE STOP BEFORE")
	var am := tree.get_first_node_in_group("area_manager") as AreaManager
	if am == null:
		return "NO AREA MANAGER"
	if am.is_busy():
		return "TRAVELLING..."
	return breach_reason(tree)


static func is_docked(qm: QuestManager) -> bool:
	return qm != null and qm.is_completed(DOCKED_QUEST)


static func breach_reason(tree: SceneTree) -> String:
	for b in tree.get_nodes_in_group("hull_breach"):
		if b.has_method("blocks_route") and b.blocks_route():
			if b.has_method("route_block_text"):
				return b.route_block_text()
			return "HULL BREACH: CLEAR THE DECK FIRST" if b.is_running() \
					else "THE NULL ARE BOARDING: HOLD THE DECK FIRST"
	return ""


static func sail(w: Waypoint, tree: SceneTree, new_instance := false) -> bool:
	if route_blocked_reason(w, tree) != "":
		return false
	var am := tree.get_first_node_in_group("area_manager") as AreaManager
	am.go_to(w.scene, w.spawn_id, w.dungeon_level,
			WorldState.ALWAYS_NEW if new_instance else WorldState.REJOIN_OR_NEW)
	return true


static func blocked_reason(w: Waypoint, tree: SceneTree, new_instance := false) -> String:
	if not is_discovered(w):
		return "UNDISCOVERED"
	if is_convoy_stop(w):
		return "USE THE ROUTE TERMINAL OR THE DISTRICT GATE"
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


static func travel(w: Waypoint, tree: SceneTree, new_instance := false) -> bool:
	if blocked_reason(w, tree, new_instance) != "":
		return false
	var am := tree.get_first_node_in_group("area_manager") as AreaManager
	am.travel(w.scene, w.spawn_id, w.dungeon_level, new_instance and is_instanced(w))
	return true


static func is_instanced(w: Waypoint) -> bool:
	return w != null and w.dungeon_level > 0


static func normalize(path: String) -> String:
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return path
