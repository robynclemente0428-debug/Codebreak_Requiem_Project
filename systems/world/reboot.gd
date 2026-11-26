class_name Reboot
extends RefCounted
## TERMINATE's reward: REBOOT, a new game plus. AXIOM ended; it boots again with you in it.
## (story_plan/CodeBreak_Requiem_Endgame_Plan.md, section 7.)
##
## At Character Select a character who chose TERMINATE has a REBOOT button: the character is
## rebooted in its own slot (make). The save from before is kept only as a backup file.
##   kept     name, class, rank and exam grades (the exam quests, completed), the script library,
##            routines, and kernel.gd's root lines (they run in every dungeon from Act I)
##   reset    quests, deeds, waypoints, gear and backpack (the class's starting kit again),
##            credits, the tower, and the ending: a rebooted run can choose another one
##   harder   enemies have +ENEMY_BONUS health and damage per reboot (enemy_bonus); Null Echoes
##            copy you from Act II (early_echoes, Dungeon); in The Recursion two floors are
##            revealed at a time (tower_reveal)
## A rebooted save carries the deed "reboot:run" = how many times it's been rebooted, so every
## rule reads it from the QuestManager like the endings do. Co-op: the host's count decides how
## tough the enemies are (the host runs them), sent in the loadout as "reboot".

const DEED := "reboot"
const DEED_TARGET := "run"
## Health and damage per reboot: +100%, so a first reboot doubles them.
const ENEMY_BONUS := 1.0
## Null Echoes copy you in these acts too, after a reboot (Act IV has them anyway).
const EARLY_ECHO_ACTS := [2, 3]
## The tower reveals this many floors past your highest cleared one.
const TOWER_REVEAL := 2


static func can_reboot(data: Dictionary) -> bool:
	var q = data.get("quests", {})
	var deeds = q.get("deeds", {}) if q is Dictionary else {}
	return deeds is Dictionary and int(deeds.get("%s:terminate" % Endings.NOW_DEED, 0)) > 0


static func count(qm: QuestManager) -> int:
	return qm.deed_count(DEED, DEED_TARGET) if qm != null else 0


static func count_of_save(data: Dictionary) -> int:
	var q = data.get("quests", {})
	var deeds = q.get("deeds", {}) if q is Dictionary else {}
	return int(deeds.get("%s:%s" % [DEED, DEED_TARGET], 0)) if deeds is Dictionary else 0


## This machine's character's reboots (0 = a first run).
static func local_count() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var player := tree.get_first_node_in_group("players") if tree != null else null
	if player != null and player.get("quests") != null:
		return count(player.get("quests") as QuestManager)
	if not SaveManager.party.is_empty():
		return count_of_save(SaveManager.get_data(SaveManager.party[0]))
	return 0


## The reboots that decide how tough enemies are: the host's in co-op (it runs them), else ours.
static func world_count() -> int:
	if Coop.in_game and not Coop.is_host():
		var host: Dictionary = Coop.roster.get(1, {})
		return int((host.get("loadout", {}) as Dictionary).get("reboot", 0))
	return local_count()


## Added to enemies' health and damage (0.0 on a first run).
static func enemy_bonus() -> float:
	return ENEMY_BONUS * world_count()


## Whether a dungeon in `act_number` gets Null Echoes because of a reboot.
static func early_echoes(act_number: int) -> bool:
	return act_number in EARLY_ECHO_ACTS and world_count() > 0


static func tower_reveal() -> int:
	return TOWER_REVEAL if local_count() > 0 else 1


## The rank a save holds (Ranks' rule: every exam up to it completed), by name.
static func rank_name(data: Dictionary) -> String:
	var q = data.get("quests", {})
	var done: Array = q.get("completed", []) if q is Dictionary and q.get("completed") is Array else []
	var best := 0
	for i in range(1, Ranks.LADDER.size()):
		if not done.has(Ranks.LADDER[i]["exam"]):
			break
		best = i
	return Ranks.LADDER[best]["name"]


# ---------- REBOOTING THE CHARACTER ----------
## Where the save from before a reboot is copied, in case it's wanted back.
const BACKUP_DIR := "user://saves/backups/"


## The new save's data: `fresh` (a new character's save) plus what a reboot keeps from `old`.
## Nothing is written here.
static func carry(old: Dictionary, fresh: Dictionary) -> Dictionary:
	var out := fresh.duplicate(true)
	for key in ["script_library", "script_routines", "kernel", "script_set_names"]:
		if old.has(key):
			var v = old[key]
			out[key] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	var oq: Dictionary = old.get("quests", {}) if old.get("quests") is Dictionary else {}
	var done: Array = oq.get("completed", []) if oq.get("completed") is Array else []
	var exams: Array = []
	for i in range(1, Ranks.LADDER.size()):              # the rank held: every exam up to it
		var exam: String = Ranks.LADDER[i]["exam"]
		if not done.has(exam):
			break
		exams.append(exam)
	var grades := {}
	var old_grades: Dictionary = oq.get("exam_grades", {}) if oq.get("exam_grades") is Dictionary else {}
	for i in range(1, exams.size() + 1):
		var rid: String = Ranks.LADDER[i]["id"]
		if old_grades.has(rid):
			grades[rid] = int(old_grades[rid])
	out["quests"] = {"active": [], "completed": exams, "pending_choices": [], "recovered": [],
			"exam_grades": grades, "deeds": {"%s:%s" % [DEED, DEED_TARGET]: count_of_save(old) + 1}}
	return out


## Reboots the character in `slot`: its save is replaced by the rebooted one, in the same slot.
## The save from before is copied to BACKUP_DIR first. False if nothing changed (the character
## can't be rebooted, or the backup or save failed).
static func make(slot: int) -> bool:
	var old := SaveManager.load_slot(slot)
	if old.is_empty() or not can_reboot(old):
		return false
	var class_data := load("res://data/classes/%s.tres" % str(old.get("class_id", ""))) as ClassData
	if class_data == null:
		return false
	if _backup(slot, old) == "":
		push_warning("REBOOT: couldn't back up slot %d, so it wasn't rebooted" % slot)
		return false
	return SaveManager.save_slot(slot, carry(old, SaveManager.new_character_data(str(old.get("name", "Executor")), class_data)))


static func _backup(slot: int, data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(BACKUP_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path := BACKUP_DIR + "slot_%d_before_reboot_%s.json" % [slot, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return path
