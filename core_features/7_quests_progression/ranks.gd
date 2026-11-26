class_name Ranks
extends RefCounted

const LADDER := [
	{"name": "INITIATE", "exam": "", "id": ""},
	{"name": "OPERATOR", "exam": "exam_operator", "id": "operator"},
	{"name": "ARCHITECT", "exam": "exam_architect", "id": "architect"},
	{"name": "STRATEGIST", "exam": "exam_strategist", "id": "strategist"},
	{"name": "ENGINEER", "exam": "exam_engineer", "id": "engineer"},
	{"name": "DEFRAGMENTER", "exam": "exam_defragmenter", "id": "defragmenter"},
	{"name": "THEORIST", "exam": "exam_theorist", "id": "theorist"},
]


const PERKS := [
	{"sets": 1},
	{"sets": 2, "rules": 1, "hints": true},
	{"rules": 1, "blocks": 4, "library": true, "loops": true},
	{"sets": 3, "rules": 1, "variables": true, "tier_blocks": 1},
	{"rules": 2, "budget": 2, "tier_blocks": 1, "routines": true},
	{"budget": 2, "sorting": true},
	{"budget": 2},
]
const PERK_TEXT := {
	"sets": "Script set %s",
	"rules": "+%d rule per script",
	"blocks": "+%d blocks per script",
	"hints": "Threat counter hints",
	"library": "Script library (save / load scripts)",
	"loops": "Loops (for / while / break) and if blocks inside a rule",
	"variables": "The Registry (a set of enemies: add, remove, in, .size)",
	"budget": "+%d script points on every skill",
	"routines": "Routines: write lines once in routines.gd, run them from any skill with call name() (1 block)",
	"tier_blocks": "Elegant and Lean allow +%d block",
	"sorting": "Sorting: registry.sort(key=hp) puts the registry in order, and when target is registry[0] picks by place",
}
const FLAG_PERKS := ["hints", "library", "loops", "variables", "routines", "sorting"]

const LOCKED_BLOCKS := {
	"loop": "loops",
	"cond:loop_index": "loops",
	"cond:target_alive": "loops",
	"cond:stack_overflow": "loops",
	"cond:killed": "loops",
	"cond:hit_nothing": "loops",
	"gem:for_loop_support": "loops",
	"cond:var_compare": "variables",
	"knob:var": "variables",
	"if": "loops",
	"call": "routines",
	"sort": "sorting",
	"cond:registry_pos": "sorting",
}


static var lent := PackedStringArray()


static func perk(rank: int, key: String) -> Variant:
	if key in FLAG_PERKS and key in lent:
		return true
	if key == "sets" and key in lent:
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


static func allows(rank: int, block: String) -> bool:
	return not LOCKED_BLOCKS.has(block) or perk(rank, LOCKED_BLOCKS[block])


static func unlocks(block: String) -> String:
	return first_with(LOCKED_BLOCKS[block]) if LOCKED_BLOCKS.has(block) else ""


static func of(node: Node) -> int:
	if node == null:
		return 0
	var qm := node.get("quests") as QuestManager
	return index_of(qm)


static func of_player(tree: SceneTree) -> int:
	return of(tree.get_first_node_in_group("players")) if tree != null else 0


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
		elif key == "rules" and int(v) != 1:
			out.append((PERK_TEXT[key] % v).replace(" rule ", " rules "))
		else:
			out.append(PERK_TEXT[key] % v)
	return out


static func first_with(key: String, value: Variant = true) -> String:
	for i in PERKS.size():
		var v: Variant = perk(i, key)
		if (v is bool and v == value) or (not v is bool and v >= value):
			return LADDER[i]["name"]
	return ""


static func index_of(qm: QuestManager) -> int:
	var best := 0
	if qm == null:
		return best
	for i in range(1, LADDER.size()):
		if not qm.is_completed(LADDER[i]["exam"]):
			break
		best = i
	return best


static func waiting(qm: QuestManager) -> PackedStringArray:
	var out := PackedStringArray()
	if qm == null:
		return out
	for i in range(index_of(qm) + 2, LADDER.size()):
		if qm.is_completed(LADDER[i]["exam"]):
			out.append(LADDER[i]["name"])
	return out


static func is_exam(quest_id: String) -> bool:
	if quest_id == "":
		return false
	for r in LADDER:
		if r["exam"] == quest_id:
			return true
	return false


static func name_of_save(data: Dictionary) -> String:
	var quests = data.get("quests", {})
	var done: Array = quests.get("completed", []) if quests is Dictionary else []
	var best := 0
	for i in range(1, LADDER.size()):
		if not done.has(LADDER[i]["exam"]):
			break
		best = i
	return LADDER[best]["name"]


static func name_at(index: int) -> String:
	return LADDER[clampi(index, 0, LADDER.size() - 1)]["name"]


static func current(qm: QuestManager) -> String:
	return LADDER[index_of(qm)]["name"]


static func grade(qm: QuestManager) -> String:
	if qm == null:
		return ""
	var g := qm.exam_grade(LADDER[index_of(qm)]["id"])
	return ExamSpec.GRADES[g] if g >= 0 else ""


static func next(qm: QuestManager) -> String:
	var i := index_of(qm) + 1
	return LADDER[i]["name"] if i < LADDER.size() else ""
