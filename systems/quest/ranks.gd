class_name Ranks
extends RefCounted
## Executor ranks. A rank isn't saved on its own: you hold it once you've turned in its exam
## and every exam below it (Examiner Sudo's exam quests), so it always matches your quest progress.
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


## What each rank unlocks, by LADDER index. Bonuses add up as you climb (see perk()).
##   sets      script sets usable (SkillComponent), out of SCRIPT_SETS
##   rules     extra rules per program        blocks   extra blocks per program
##   hints     the threat panel shows how to counter each threat
##   library   the SCRIPTING editor's save / load library (SkillComponent.library)
##   loops     for / while / break and the blocks about repeats (see LOCKED_BLOCKS)
##   variables the registers x and y: [x] [+=] [1], when [x] [>=] [3] (see ScriptRegisters)
##   budget    extra script points on every skill (ScriptBudget adds exam grades and clears)
const PERKS := [
	{"sets": 1},                                          # INITIATE
	{"sets": 2, "rules": 1, "hints": true},               # OPERATOR
	{"rules": 1, "blocks": 4, "library": true, "loops": true},   # ARCHITECT
	{"sets": 3, "variables": true},                       # STRATEGIST
	{"budget": 2},                                        # ENGINEER
	{"budget": 2},                                        # DEFRAGMENTER
	{"budget": 2},                                        # THEORIST
]
## One line per perk for the rank-up message and the character panel tooltip.
const PERK_TEXT := {
	"sets": "Script set %s",
	"rules": "+%d rule per script",
	"blocks": "+%d blocks per script",
	"hints": "Threat counter hints",
	"library": "Script library (save / load scripts)",
	"loops": "Loops (for / while / break)",
	"variables": "Counters (x and y)",
	"budget": "+%d script points on every skill",
}
## Perks that are on / off (the rest are numbers).
const FLAG_PERKS := ["hints", "library", "loops", "variables"]

## Script blocks a perk unlocks. Below that rank they don't exist for the player: the editor
## doesn't list them, the gem vendor doesn't sell them, and a script using one doesn't compile.
##   "loop"            for / while / break (ProgramLoop)
##   "cond:<type id>"  a condition block (ProgramConditions.TYPES)
##   "knob:<id>"       a knob (SkillKnob.id)
##   "gem:<id>"        a support gem (SupportGemDefinition.id)
const LOCKED_BLOCKS := {
	"loop": "loops",
	"cond:loop_index": "loops",
	"cond:target_alive": "loops",
	"cond:stack_overflow": "loops",
	"gem:for_loop_support": "loops",
	"cond:var_compare": "variables",
	"knob:var": "variables",
}


## Flag perks lent for now whatever the rank: Sudo's sandbox lends what its exam asks for
## (ExamSpec.lends: the Architect exam lends "loops"), and takes them back on leaving.
static var lent := PackedStringArray()


## A perk's value at rank index `rank`: numbers add up over the ranks held ("rules", "blocks"),
## "sets" is the highest reached, flags stay on once unlocked.
static func perk(rank: int, key: String) -> Variant:
	if key in FLAG_PERKS and key in lent:
		return true
	if key == "sets" and key in lent:                 # every set, for a test of The Collector
		return SkillComponent.SCRIPT_SETS
	var out: Variant = null
	for i in mini(rank + 1, PERKS.size()):
		if not PERKS[i].has(key):
			continue
		var v: Variant = PERKS[i][key]
		if v is bool:
			out = true
		elif key == "sets":
			out = v
		else:
			out = (out if out != null else 0) + v
	if out == null:
		return false if key in FLAG_PERKS else 0
	return out


## True when rank index `rank` may use a script block (see LOCKED_BLOCKS for the ids).
static func allows(rank: int, block: String) -> bool:
	return not LOCKED_BLOCKS.has(block) or perk(rank, LOCKED_BLOCKS[block])


## The rank (name) that unlocks a script block, "" if it is never locked.
static func unlocks(block: String) -> String:
	return first_with(LOCKED_BLOCKS[block]) if LOCKED_BLOCKS.has(block) else ""


## The rank index of the player owning `node` (its QuestManager), 0 without one.
static func of(node: Node) -> int:
	if node == null:
		return 0
	var qm := node.get("quests") as QuestManager
	return index_of(qm)


## The rank held by the player (first in group "players").
static func of_player(tree: SceneTree) -> int:
	return of(tree.get_first_node_in_group("players")) if tree != null else 0


## Lines describing what rank `rank` adds on top of the one below it.
static func unlock_lines(rank: int) -> PackedStringArray:
	var out := PackedStringArray()
	if rank <= 0 or rank >= PERKS.size():
		return out
	for key in PERKS[rank]:
		var v: Variant = PERKS[rank][key]
		if key == "sets":
			out.append(PERK_TEXT[key] % SkillComponent.SET_NAMES[int(v) - 1])
		elif v is bool:
			out.append(PERK_TEXT[key])
		else:
			out.append(PERK_TEXT[key] % v)
	return out


## The first rank (name) that unlocks `key`, "" if none does.
static func first_with(key: String, value: Variant = true) -> String:
	for i in PERKS.size():
		var v: Variant = perk(i, key)
		if (v is bool and v == value) or (not v is bool and v >= value):
			return LADDER[i]["name"]
	return ""


## Index in LADDER of the highest rank this player holds. The ladder is climbed in order: a rank
## needs every exam below it too, so passing a later exam early doesn't skip the ranks between.
## It counts once the gap is filled.
static func index_of(qm: QuestManager) -> int:
	var best := 0
	if qm == null:
		return best
	for i in range(1, LADDER.size()):
		if not qm.is_completed(LADDER[i]["exam"]):
			break
		best = i
	return best


## Ranks whose exam is passed but that aren't held yet, because an exam below is missing.
static func waiting(qm: QuestManager) -> PackedStringArray:
	var out := PackedStringArray()
	if qm == null:
		return out
	for i in range(index_of(qm) + 2, LADDER.size()):
		if qm.is_completed(LADDER[i]["exam"]):
			out.append(LADDER[i]["name"])
	return out


## True for a rank exam quest (one of the LADDER exams). Exams get their own colour on quest
## markers, the NPC card and the tracker (NpcInfoPanel.COL_EXAM).
static func is_exam(quest_id: String) -> bool:
	if quest_id == "":
		return false
	for r in LADDER:
		if r["exam"] == quest_id:
			return true
	return false


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
