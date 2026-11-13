class_name KernelScript
extends RefCounted
## kernel.gd: Act V's root scripts. At the Core the Executor has root, and the script editor gets
## a fourth file whose lines aren't about a skill: their subject is the ZONE, and they run whatever
## you cast (KernelDirector, in the Stack Trace, Sentinel's Hall and The Kernel):
##     when enemy_spotted:    registry.add(target)
##     when enemy_killed:     heal(4%)
##     when life_below(30%):  stack.rollback(5s)
## Unlocked once the Null Gatekeeper is turned in (you reach the Core).
##
## Root points: every line costs some (LINES "cost"), out of MAX_POINTS. What's left is CORE
## STABILITY, shown on the HUD in Act V zones and at the top of kernel.gd.
## The Null writes back: the first time you enter each Act V zone it inserts one line of its own
## (NULL_LINES), marked violet, that runs against you. Low stability makes its lines stronger
## (null_scale). You can OVERWRITE one, for OVERWRITE_COST points, for good.
## What your kernel holds when you reach the end leans the ending (lean()): overwrite most of the
## Null's lines and it leans OVERWRITE; keep them running and it leans MERGE; otherwise TERMINATE.
##
## Your lines are saved with the character (SkillComponent.kernel). The Null's lines are deeds:
## kernel_null:<id> once inserted, kernel_overwrite:<id> once overwritten.

const FILE_NAME := "kernel.gd"
const UNLOCK_QUEST := "q08_null_gatekeeper"
const MAX_POINTS := 10
const OVERWRITE_COST := 3
const ZONES := ["act_5_stack_trace", "act_5_sentinel_hall", "act_5_kernel", "act_5_page_file", "act_5_scheduler"]
## The Scheduler (challenge zone): no line of its own; instead the Null schedules one of NULL_LINES
## for SCHEDULE_SECONDS at a time, round and round, while you're there (KernelDirector).
const SCHEDULE_ZONE := "act_5_scheduler"
const SCHEDULE_SECONDS := 45.0
const NULL_DEED := "kernel_null"
const OVERWRITE_DEED := "kernel_overwrite"
const COL_NULL := Color(0.78, 0.5, 1.0)
const COL_ROOT := Color(1.0, 0.85, 0.4)

## The triggers, in the order the file shows them.
const TRIGGERS := ["area_entered", "enemy_spotted", "enemy_killed", "life_below(30%)", "life_below(50%)"]

## Your lines: id -> trigger, code, cost (root points), tip.
const LINES := {
	"barrier_on_entry": {"trigger": "area_entered", "code": "barrier(20%)", "cost": 1,
		"tip": "Arriving in a zone gives you a barrier of 20% of your maximum life for 8 seconds."},
	"registry_add": {"trigger": "enemy_spotted", "code": "registry.add(target)", "cost": 1,
		"tip": "Every enemy that comes within 14 m joins every one of your skills' registries, so registry.sort and registry[0] see the whole room, not only what you've hit."},
	"defragment": {"trigger": "enemy_spotted", "code": "target.defragment()", "cost": 3,
		"tip": "Takes FRAGMENTED off it: it takes full damage in any order, and doesn't knit its pack back."},
	"weaken": {"trigger": "enemy_spotted", "code": "target.max_hp -= 15%", "cost": 3,
		"tip": "Every enemy you meet has 15% less maximum life."},
	"slow": {"trigger": "enemy_spotted", "code": "target.move_speed -= 25%", "cost": 2,
		"tip": "Every enemy you meet moves 25% slower."},
	"mana_on_kill": {"trigger": "enemy_killed", "code": "mana(10%)", "cost": 1,
		"tip": "Each kill gives back 10% of your maximum mana."},
	"heal_on_kill": {"trigger": "enemy_killed", "code": "heal(4%)", "cost": 2,
		"tip": "Each kill heals 4% of your maximum life."},
	"rollback": {"trigger": "life_below(30%)", "code": "stack.rollback(5s)", "cost": 4,
		"tip": "Once per zone: when your life drops below 30%, it goes back to the most it was in the last 5 seconds."},
}

## The Null's lines: one per zone, inserted the first time you enter it.
const NULL_LINES := {
	"null_armour": {"zone": "act_5_stack_trace", "trigger": "enemy_spotted", "code": "target.armour += 40%",
		"tip": "The Null hardens what the Core replays: every enemy you meet has 40% more armour."},
	"null_drain": {"zone": "act_5_sentinel_hall", "trigger": "life_below(50%)", "code": "mana.drain(25%)",
		"tip": "Below half life, the Null takes 25% of your maximum mana (every 8 seconds at most)."},
	"null_regrow": {"zone": "act_5_kernel", "trigger": "enemy_spotted", "code": "target.max_hp += 20%",
		"tip": "The Null pads what guards the Kernel: every enemy you meet has 20% more maximum life."},
	"null_swap": {"zone": "act_5_page_file", "trigger": "enemy_killed", "code": "registry.clear()",
		"tip": "The Null swaps your references out: every kill empties every one of your skills' registries."},
}


static func unlocked(qm: QuestManager) -> bool:
	return qm != null and qm.is_completed(UNLOCK_QUEST)


static func is_zone(scene_path: String) -> bool:
	return scene_path.get_file().get_basename() in ZONES


## Root points your lines and your overwrites have spent.
static func used(lines: Array, qm: QuestManager) -> int:
	var n := 0
	for id in lines:
		n += int(LINES.get(id, {}).get("cost", 0))
	return n + overwrites(qm) * OVERWRITE_COST


static func free_points(lines: Array, qm: QuestManager) -> int:
	return MAX_POINTS - used(lines, qm)


## Core stability, 0..1: the share of root points still free.
static func stability(lines: Array, qm: QuestManager) -> float:
	return clampf(float(free_points(lines, qm)) / MAX_POINTS, 0.0, 1.0)


## How much stronger the Null's lines run: x1 at full stability, x2 with nothing left.
static func null_scale(lines: Array, qm: QuestManager) -> float:
	return 1.0 + (1.0 - stability(lines, qm))


## True when `id` can be added to `lines` now (not there yet, and the points are free).
static func can_add(lines: Array, qm: QuestManager, id: String) -> bool:
	return LINES.has(id) and not (id in lines) and free_points(lines, qm) >= int(LINES[id]["cost"])


static func is_inserted(qm: QuestManager, null_id: String) -> bool:
	return qm != null and qm.deed_count(NULL_DEED, null_id) > 0


static func is_overwritten(qm: QuestManager, null_id: String) -> bool:
	return qm != null and qm.deed_count(OVERWRITE_DEED, null_id) > 0


## The Null's lines running now (inserted, not overwritten).
static func null_running(qm: QuestManager) -> Array:
	return NULL_LINES.keys().filter(func(id: String) -> bool: return is_inserted(qm, id) and not is_overwritten(qm, id))


static func overwrites(qm: QuestManager) -> int:
	var n := 0
	for id in NULL_LINES:
		if is_overwritten(qm, id):
			n += 1
	return n


## The ending your kernel leans toward: "overwrite", "merge" or "terminate".
static func lean(qm: QuestManager) -> String:
	if overwrites(qm) >= 2:
		return "overwrite"
	if null_running(qm).size() >= 2:
		return "merge"
	return "terminate"


## The Null line this zone inserts ("" = none).
static func null_line_of(scene_path: String) -> String:
	var zone := scene_path.get_file().get_basename()
	for id in NULL_LINES:
		if NULL_LINES[id]["zone"] == zone:
			return id
	return ""


## "when enemy_spotted: registry.add(target)"
static func code_of(id: String) -> String:
	var d: Dictionary = LINES.get(id, NULL_LINES.get(id, {}))
	return "when %s: %s" % [d.get("trigger", "?"), d.get("code", "?")]
