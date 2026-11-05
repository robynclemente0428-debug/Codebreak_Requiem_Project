class_name ScriptBudget
extends RefCounted
## Extra script points on top of every gem's own point_budget: how a player's scripts grow
## stronger as the enemies do. Every programmable skill gets the same bonus. Three sources:
##   rank    Ranks.PERKS "budget" (ENGINEER, DEFRAGMENTER and THEORIST)
##   grades  each rank exam passed with MERIT or DISTINCTION (retake one to raise it)
##   clears  each area cleared of every enemy, once per area (the clear_area deed, reported by
##           DungeonPopulator when the last enemy of an instance dies)
## Knobs also get wider (more steps in their buff direction, SkillProgramLimits.widen_knob):
##   STEPS_PER_DISTINCTION for each exam passed with DISTINCTION
##   STEPS_PER_ACT_BOSS    for each act boss killed (EnemyDefinition.act_boss), once per boss

const GRADE_POINTS := [0.0, 0.5, 1.0]      # by ExamSpec.GRADES: PASS, MERIT, DISTINCTION
const POINTS_PER_CLEAR := 1.0
const STEPS_PER_DISTINCTION := 1
const STEPS_PER_ACT_BOSS := 1
const BOSS_DEED := "act_boss"
const DISTINCTION := 2                     # ExamSpec.GRADES index
const CLEAR_DEED := "clear_area"


## {"rank": points, "grades": points, "clears": points, "areas": areas cleared, "total": points,
##  "distinctions": exams passed with DISTINCTION, "bosses": act bosses killed, "steps": extra knob steps}
static func breakdown(qm: QuestManager) -> Dictionary:
	var out := {"rank": 0.0, "grades": 0.0, "clears": 0.0, "areas": 0, "total": 0.0,
		"distinctions": 0, "bosses": 0, "steps": 0}
	if qm == null:
		return out
	out["rank"] = float(Ranks.perk(Ranks.index_of(qm), "budget"))
	for r in Ranks.LADDER:
		var g := qm.exam_grade(r["id"]) if r["id"] != "" else -1
		if g >= 0 and g < GRADE_POINTS.size():
			out["grades"] += GRADE_POINTS[g]
		if g == DISTINCTION:
			out["distinctions"] += 1
	out["bosses"] = _deeds(qm, BOSS_DEED).size()
	out["steps"] = out["distinctions"] * STEPS_PER_DISTINCTION + out["bosses"] * STEPS_PER_ACT_BOSS
	out["areas"] = cleared_areas(qm).size()
	out["clears"] = out["areas"] * POINTS_PER_CLEAR
	out["total"] = out["rank"] + out["grades"] + out["clears"]
	return out


static func points(qm: QuestManager) -> float:
	return breakdown(qm)["total"]


## Extra steps on every knob (per DISTINCTION and per act boss).
static func steps(qm: QuestManager) -> int:
	return breakdown(qm)["steps"]


## Area ids (scene file names, e.g. "act_1_spillway") this player has cleared.
static func cleared_areas(qm: QuestManager) -> PackedStringArray:
	return _deeds(qm, CLEAR_DEED)


## Enemy ids of the act bosses this player has killed.
static func act_bosses_killed(qm: QuestManager) -> PackedStringArray:
	return _deeds(qm, BOSS_DEED)


static func is_boss_killed(qm: QuestManager, enemy_id: String) -> bool:
	return qm != null and qm.deed_count(BOSS_DEED, enemy_id) > 0


## The targets of every `kind` deed this player has (QuestManager.deeds keys are "kind:target").
static func _deeds(qm: QuestManager, kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	if qm == null:
		return out
	var prefix := kind + ":"
	for key: String in qm.deeds:
		if key.begins_with(prefix) and int(qm.deeds[key]) > 0:
			out.append(key.substr(prefix.length()))
	return out


static func is_cleared(qm: QuestManager, area_id: String) -> bool:
	return qm != null and qm.deed_count(CLEAR_DEED, area_id) > 0
