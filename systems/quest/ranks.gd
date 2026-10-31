class_name Ranks
extends RefCounted
## Executor ranks. A rank isn't saved on its own: you hold it once you've turned in its exam
## (Examiner Sudo's exam quests), so it always matches your quest progress.
## To add a rank: append it to LADDER with the id of the quest that grants it.

const LADDER := [
	{"name": "UNRANKED", "exam": ""},
	{"name": "OPERATOR", "exam": "exam_operator"},
	{"name": "ENGINEER", "exam": "exam_engineer"},
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


## The next rank's name, or "" at the top of the ladder.
static func next(qm: QuestManager) -> String:
	var i := index_of(qm) + 1
	return LADDER[i]["name"] if i < LADDER.size() else ""
