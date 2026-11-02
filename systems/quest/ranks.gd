class_name Ranks
extends RefCounted
## Executor ranks. A rank isn't saved on its own: you hold it once you've turned in its exam
## (Examiner Sudo's exam quests), so it always matches your quest progress.
## To add a rank: append it to LADDER with the id of the quest that grants it.
## Exams sat in Sudo's sandbox (ExamChamber) also keep a grade: QuestManager.exam_grade(id).
##
## One rank per act, two in the last: Operator (I), Architect (II), Strategist (III),
## Engineer (IV), Defragmenter (V) and Theorist (after the campaign). Quests that don't exist
## yet simply can't be completed, so those ranks wait until their act is built.

const LADDER := [
	{"name": "INITIATE", "exam": "", "id": ""},
	{"name": "OPERATOR", "exam": "exam_operator", "id": "operator"},
	{"name": "ARCHITECT", "exam": "exam_architect", "id": "architect"},
	{"name": "STRATEGIST", "exam": "exam_strategist", "id": "strategist"},
	{"name": "ENGINEER", "exam": "exam_engineer", "id": "engineer"},
	{"name": "DEFRAGMENTER", "exam": "exam_defragmenter", "id": "defragmenter"},
	{"name": "THEORIST", "exam": "exam_theorist", "id": "theorist"},
]


## Index in LADDER of the highest rank this player holds.
static func index_of(qm: QuestManager) -> int:
	var best := 0
	if qm == null:
		return best
	for i in LADDER.size():
		var exam: String = LADDER[i]["exam"]
		if exam != "" and qm.is_completed(exam):
			best = i
	return best


static func current(qm: QuestManager) -> String:
	return LADDER[index_of(qm)]["name"]


## The current rank's exam grade ("PASS" / "MERIT" / "DISTINCTION"), or "" if it has none.
static func grade(qm: QuestManager) -> String:
	if qm == null:
		return ""
	var g := qm.exam_grade(LADDER[index_of(qm)]["id"])
	return ExamSpec.GRADES[g] if g >= 0 else ""


## The next rank's name, or "" at the top of the ladder.
static func next(qm: QuestManager) -> String:
	var i := index_of(qm) + 1
	return LADDER[i]["name"] if i < LADDER.size() else ""
