class_name SaveEdit
extends RefCounted
## The Save Editor's rules (SaveEditor is the window): reads and changes ONE save dictionary, the
## way the game itself stores it. For testing only. Nothing here touches files; the window loads
## and saves through SaveManager.
##
##   credits     data.currency.amount
##   quests      data.quests: active [{id, progress, status}], completed [ids]
##   rank        not stored: held once its exam quest and every exam below are completed (Ranks)
##   keys        data.quests.recovered: quest items and keys that open sealed portals (QuestItems)
##   waypoints   data.waypoints [ids], data.route_cleared [convoy stop ids] (Waypoints)
##   ending      data.quests.deeds "ending_now:<id>" and "ending:<id>" (Endings)
##   tower       data.tower {cleared, seeds} (Tower)

## Which act each quest belongs to (quest files don't say). A quest missing here shows under OTHER:
## add it when a new quest is made.
const QUEST_ACTS := {
	"tut_basics": 1, "tutorial_gear": 1, "q00_proximity_trigger": 1, "q01_glitchling_queen": 1,
	"q01b_clear_the_ward": 1, "clear_hub": 1, "ward_beacons_outer": 1, "ward_beacons_inner": 1,
	"q02_corrupted_gate_guard": 1, "q02b_the_road_out": 1, "exam_operator": 1,
	"exam_architect": 2, "q03_loop_hound_alpha": 2, "q04_the_overflow": 2, "q04b_hollow_choir": 2,
	"q04c_the_last_mile": 2,
	"exam_strategist": 3, "q05_the_leak": 3, "q06_the_mimic": 3, "q06b_the_collector": 3,
	"q06c_root_access": 3, "memory_shards": 3, "copied_stock": 3,
	"exam_engineer": 4, "q07a_learn_the_language": 4, "null_fragments": 4, "under_new_rules": 4,
	"guild_expedition": 4, "static_from_home": 4, "q07_null_weaver_prime": 4, "q08_null_gatekeeper": 4,
	"exam_defragmenter": 5, "q09_core_sentinel": 5, "paged_out": 5, "time_slice": 5, "last_words": 5,
	"q10_root_process": 5,
	"exam_theorist": 6,
}
const ACT_TITLES := {1: "ACT I  //  THE SPAWN POINT", 2: "ACT II  //  THE MIGRATION", 3: "ACT III  //  ROOT ACCESS",
		4: "ACT IV  //  INTO THE NULL", 5: "ACT V  //  FINAL EXECUTION", 6: "THE RECURSION", 0: "OTHER"}


## The quests in `catalog` grouped by act, in play order within each: {act number: [QuestDefinition]}.
## Act 0 holds any quest QUEST_ACTS doesn't list.
static func quests_by_act(catalog: Array[QuestDefinition]) -> Dictionary:
	var order: Array = QUEST_ACTS.keys()
	var out := {}
	for def in catalog:
		var act := int(QUEST_ACTS.get(def.id, 0))
		if not out.has(act):
			out[act] = []
		out[act].append(def)
	for act in out:
		(out[act] as Array).sort_custom(func(a: QuestDefinition, b: QuestDefinition) -> bool:
			var ia := order.find(a.id)
			var ib := order.find(b.id)
			return (ia if ia >= 0 else 999) < (ib if ib >= 0 else 999) if ia != ib else a.id < b.id)
	return out


enum QuestStatus { NOT_STARTED, ACTIVE, READY, COMPLETED }
const STATUS_NAMES := ["NOT STARTED", "ACTIVE", "READY TO TURN IN", "COMPLETED"]


static func _quests(data: Dictionary) -> Dictionary:
	if not (data.get("quests") is Dictionary):
		data["quests"] = {}
	var q: Dictionary = data["quests"]
	for k in ["active", "completed", "recovered"]:
		if not (q.get(k) is Array):
			q[k] = []
	for k in ["deeds", "exam_grades"]:
		if not (q.get(k) is Dictionary):
			q[k] = {}
	return q


# ---------- CREDITS ----------
static func credits(data: Dictionary) -> int:
	var c = data.get("currency", {})
	return int(c.get("amount", 0)) if c is Dictionary else 0


static func set_credits(data: Dictionary, amount: int) -> void:
	if not (data.get("currency") is Dictionary):
		data["currency"] = {}
	data["currency"]["amount"] = maxi(amount, 0)


# ---------- QUESTS ----------
## Every quest the game has, by id, sorted.
static func quest_catalog() -> Array[QuestDefinition]:
	var out: Array[QuestDefinition] = []
	var folder := "res://data/quests/"
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if not f.ends_with(".tres"):
			continue
		var q := load(folder.path_join(f)) as QuestDefinition
		if q != null and q.id != "":
			out.append(q)
	out.sort_custom(func(a: QuestDefinition, b: QuestDefinition) -> bool: return a.id < b.id)
	return out


static func quest_status(data: Dictionary, id: String) -> QuestStatus:
	var q := _quests(data)
	if id in q["completed"]:
		return QuestStatus.COMPLETED
	for e in q["active"]:
		if e is Dictionary and str(e.get("id", "")) == id:
			return QuestStatus.READY if int(e.get("status", 0)) == 1 else QuestStatus.ACTIVE
	return QuestStatus.NOT_STARTED


## Puts a quest in a state. READY fills every objective; ACTIVE starts it from nothing.
## Rewards (credits, items, keys) are NOT given: set those yourself.
static func set_quest_status(data: Dictionary, def: QuestDefinition, status: QuestStatus) -> void:
	var q := _quests(data)
	var id := def.id
	q["completed"] = (q["completed"] as Array).filter(func(x) -> bool: return str(x) != id)
	q["active"] = (q["active"] as Array).filter(func(e) -> bool: return not (e is Dictionary and str(e.get("id", "")) == id))
	match status:
		QuestStatus.COMPLETED:
			q["completed"].append(id)
		QuestStatus.ACTIVE, QuestStatus.READY:
			var progress: Array = []
			for o in def.objectives:
				progress.append(int(o.required) if status == QuestStatus.READY else 0)
			q["active"].append({"id": id, "progress": progress, "status": 1 if status == QuestStatus.READY else 0})


## Every quest in `catalog` to one state (COMPLETE ALL / RESET ALL). Exam grades follow: a
## DISTINCTION for exams completed, none for exams reset.
static func set_all_quests(data: Dictionary, catalog: Array[QuestDefinition], status: QuestStatus) -> void:
	for def in catalog:
		set_quest_status(data, def, status)
	var grades: Dictionary = _quests(data)["exam_grades"]
	for r in Ranks.LADDER:
		if r["id"] == "":
			continue
		if status == QuestStatus.COMPLETED and _quests(data)["completed"].has(r["exam"]):
			grades[r["id"]] = ScriptBudget.DISTINCTION
		elif status == QuestStatus.NOT_STARTED:
			grades.erase(r["id"])


# ---------- RANK ----------
## The rank the save holds (LADDER index), by the game's own rule.
static func rank_index(data: Dictionary) -> int:
	var done: Array = _quests(data)["completed"]
	var best := 0
	for i in range(1, Ranks.LADDER.size()):
		if not done.has(Ranks.LADDER[i]["exam"]):
			break
		best = i
	return best


## Sets the rank: every exam up to it completed with a DISTINCTION, every exam above it not
## started. Exams that don't exist as quests are skipped.
static func set_rank(data: Dictionary, index: int, catalog: Array[QuestDefinition]) -> void:
	var q := _quests(data)
	var by_id := {}
	for d in catalog:
		by_id[d.id] = d
	for i in range(1, Ranks.LADDER.size()):
		var exam: String = Ranks.LADDER[i]["exam"]
		var def: QuestDefinition = by_id.get(exam)
		if def == null:
			continue
		if i <= index:
			set_quest_status(data, def, QuestStatus.COMPLETED)
			q["exam_grades"][Ranks.LADDER[i]["id"]] = ScriptBudget.DISTINCTION
		else:
			set_quest_status(data, def, QuestStatus.NOT_STARTED)
			q["exam_grades"].erase(Ranks.LADDER[i]["id"])


# ---------- KEYS (quest items) ----------
static func has_key(data: Dictionary, id: String) -> bool:
	return id in _quests(data)["recovered"]


static func set_key(data: Dictionary, id: String, on: bool) -> void:
	var q := _quests(data)
	q["recovered"] = (q["recovered"] as Array).filter(func(x) -> bool: return str(x) != id)
	if on:
		q["recovered"].append(id)


# ---------- WAYPOINTS ----------
static func has_waypoint(data: Dictionary, id: String) -> bool:
	return id in (data.get(Waypoints.SAVE_KEY, []) as Array)


static func set_waypoint(data: Dictionary, id: String, on: bool) -> void:
	_set_in_list(data, Waypoints.SAVE_KEY, id, on)


## The act bosses fought in each area (area id = the scene's file name). Scenes place bosses by
## hand, so this is kept here: add a line when a new act boss is placed.
const AREA_BOSSES := {
	"act_1_map_2": ["glitchling_queen"], "act_1_map_3": ["corrupted_gate_guard"],
	"act_2_scrapline_crossing": ["loop_hound_alpha"], "act_2_signal_wastes": ["the_overflow"],
	"act_2_hollow_relay": ["hollow_choir"], "act_2_checkpoint_approach": ["perimeter_warden"],
	"act_3_heap": ["the_leak"], "act_3_mirror_dock": ["the_mimic"], "act_3_sweep": ["the_collector"],
	"act_4_weavers_loom": ["null_weaver_prime"], "act_4_core_gate": ["null_gatekeeper"],
	"act_4_expedition_end": ["the_auditor"],
	"act_5_sentinel_hall": ["core_sentinel"], "act_5_page_file": ["watchdog"], "act_5_kernel": ["root_process"],
}


## The id the game clears `w` under (DungeonPopulator._area_id: the scene's file name), or ""
## for a town.
static func area_id(w: Waypoint) -> String:
	if w == null or w.dungeon_level <= 0:
		return ""
	var path := w.scene
	if path.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(path)
		path = ResourceUID.get_id_path(uid) if ResourceUID.has_id(uid) else ""
	return path.get_file().get_basename()


static func area_bosses(w: Waypoint) -> Array:
	return AREA_BOSSES.get(area_id(w), [])


## Checking a dungeon's waypoint also gives what clearing it gives: the clear_area deed (+script
## points on every skill) and the act_boss deed of each boss there (+knob steps). Unchecking
## takes them away again.
static func set_waypoint_with_rewards(data: Dictionary, w: Waypoint, on: bool) -> void:
	set_waypoint(data, w.id, on)
	var area := area_id(w)
	if area == "":
		return
	var deeds: Dictionary = _quests(data)["deeds"]
	var keys: Array = ["%s:%s" % [ScriptBudget.CLEAR_DEED, area]]
	for b in area_bosses(w):
		keys.append("%s:%s" % [ScriptBudget.BOSS_DEED, b])
	for k in keys:
		if on:
			deeds[k] = maxi(int(deeds.get(k, 0)), 1)
		else:
			deeds.erase(k)


static func has_route_cleared(data: Dictionary, id: String) -> bool:
	return id in (data.get(Waypoints.SAVE_KEY_CLEARED, []) as Array)


static func set_route_cleared(data: Dictionary, id: String, on: bool) -> void:
	_set_in_list(data, Waypoints.SAVE_KEY_CLEARED, id, on)


static func _set_in_list(data: Dictionary, key: String, id: String, on: bool) -> void:
	var list: Array = (data.get(key, []) as Array).filter(func(x) -> bool: return str(x) != id)
	if on:
		list.append(id)
	data[key] = list


# ---------- ENDING ----------
static func ending(data: Dictionary) -> String:
	var deeds: Dictionary = _quests(data)["deeds"]
	for id in Endings.IDS:
		if int(deeds.get("%s:%s" % [Endings.NOW_DEED, id], 0)) > 0:
			return id
	for id in Endings.IDS:
		if int(deeds.get("ending:%s" % id, 0)) > 0:
			return id
	return ""


## "" clears it (the choice can be made again at the Last Log).
static func set_ending(data: Dictionary, id: String) -> void:
	var deeds: Dictionary = _quests(data)["deeds"]
	for e in Endings.IDS:
		deeds.erase("%s:%s" % [Endings.NOW_DEED, e])
		deeds.erase("ending:%s" % e)
	if id in Endings.IDS:
		deeds["%s:%s" % [Endings.NOW_DEED, id]] = 1
		deeds["ending:%s" % id] = 1


# ---------- THE RECURSION ----------
static func tower_cleared(data: Dictionary) -> int:
	var t = data.get(Tower.SAVE_KEY, {})
	return int(t.get("cleared", 0)) if t is Dictionary else 0


## The highest floor cleared. Floors above it lose their rolls (they roll again when revealed).
static func set_tower_cleared(data: Dictionary, n: int) -> void:
	if not (data.get(Tower.SAVE_KEY) is Dictionary):
		data[Tower.SAVE_KEY] = {"cleared": 0, "seeds": {}}
	var t: Dictionary = data[Tower.SAVE_KEY]
	t["cleared"] = clampi(n, 0, Tower.FLOORS)
	var seeds: Dictionary = t.get("seeds", {}) if t.get("seeds") is Dictionary else {}
	for k in seeds.keys():
		if int(k) > t["cleared"] + 1:
			seeds.erase(k)
	t["seeds"] = seeds
