class_name KernelScript
extends RefCounted
## kernel.gd: Act V's root. At the Core the Executor has root, and the Null wants it too. On each
## floor down (the Stack Trace, Sentinel's Hall, the Page File, the Kernel) the Null submits a
## PULL REQUEST: one line it wants to run on the Core (NULL_LINES). The first time you arrive,
## PullRequestCard asks for an answer, and the answers are the three endings in small:
##   MERGE      its line runs (in every Act V zone), and it gives you a root line too ("gift")
##   OVERWRITE  its line never runs; one of two root lines of yours runs instead ("offers")
##   TERMINATE  neither runs, but the process fights its shutdown: a champion spawns there
## Root lines run on the ZONE, whatever you cast (KernelDirector):
##     when enemy_spotted:    registry.add(target)
##     when enemy_killed:     heal(4%)
## The Scheduler has no request of its own: there the Null runs the lines you didn't merge, one at
## a time, SCHEDULE_SECONDS each.
## Before the choice the Last Log reads the answers back, and the ending you answered most is the
## one your kernel leans toward (lean()).
## kernel.gd itself is a record: the script editor shows it read-only (what runs, what you answered).
##
## Your root lines are saved with the character (SkillComponent.kernel). The Null's requests are
## deeds: kernel_null:<id> once submitted, and one of kernel_merge / kernel_overwrite /
## kernel_terminate :<id> once answered.

const FILE_NAME := "kernel.gd"
const UNLOCK_QUEST := "q08_null_gatekeeper"
const ZONES := ["act_5_stack_trace", "act_5_sentinel_hall", "act_5_kernel", "act_5_page_file", "act_5_scheduler"]
## The Scheduler (challenge zone): no request of its own; the Null runs the lines you didn't merge
## there, one at a time, SCHEDULE_SECONDS each (KernelDirector).
const SCHEDULE_ZONE := "act_5_scheduler"
const SCHEDULE_SECONDS := 45.0
const NULL_DEED := "kernel_null"
const MERGE_DEED := "kernel_merge"
const OVERWRITE_DEED := "kernel_overwrite"
const TERMINATE_DEED := "kernel_terminate"
const ANSWERS := ["merge", "overwrite", "terminate"]
const COL_NULL := Color(0.78, 0.5, 1.0)
const COL_ROOT := Color(1.0, 0.85, 0.4)
const COL_TERMINATE := Color(1.0, 0.4, 0.4)       # a terminated request, and its champion

## The triggers, in the order the file shows them.
const TRIGGERS := ["area_entered", "enemy_spotted", "enemy_killed", "life_below(30%)", "life_below(50%)"]

## Root lines: id -> trigger, code, tip. You get them from the Null's requests (a merge's gift, an
## overwrite's pick); each runs in every Act V zone from then on.
const LINES := {
	"barrier_on_entry": {"trigger": "area_entered", "code": "barrier(20%)",
		"tip": "Arriving in a zone gives you a barrier of 20% of your maximum life for 8 seconds."},
	"registry_add": {"trigger": "enemy_spotted", "code": "registry.add(target)",
		"tip": "Every enemy that comes within 14 m joins every one of your skills' registries, so registry.sort and registry[0] see the whole room, not only what you've hit."},
	"defragment": {"trigger": "enemy_spotted", "code": "target.defragment()",
		"tip": "Takes FRAGMENTED off it: it takes full damage in any order, and doesn't knit its pack back."},
	"weaken": {"trigger": "enemy_spotted", "code": "target.max_hp -= 15%",
		"tip": "Every enemy you meet has 15% less maximum life."},
	"slow": {"trigger": "enemy_spotted", "code": "target.move_speed -= 25%",
		"tip": "Every enemy you meet moves 25% slower."},
	"mana_on_kill": {"trigger": "enemy_killed", "code": "mana(10%)",
		"tip": "Each kill gives back 10% of your maximum mana."},
	"heal_on_kill": {"trigger": "enemy_killed", "code": "heal(4%)",
		"tip": "Each kill heals 4% of your maximum life."},
	"rollback": {"trigger": "life_below(30%)", "code": "stack.rollback(5s)",
		"tip": "Once per zone: when your life drops below 30%, it goes back to the most it was in the last 5 seconds."},
}

## The Null's requests, one per floor, in the order you meet them. "gift": the root line a MERGE
## gives you; "offers": what an OVERWRITE can put in its place (the first two you don't run yet).
const NULL_LINES := {
	"null_armour": {"zone": "act_5_stack_trace", "trigger": "enemy_spotted", "code": "target.armour += 40%",
		"tip": "The Null hardens what the Core replays: every enemy you meet has 40% more armour.",
		"gift": "registry_add", "offers": ["defragment", "weaken", "slow"]},
	"null_drain": {"zone": "act_5_sentinel_hall", "trigger": "life_below(50%)", "code": "mana.drain(25%)",
		"tip": "Below half life, the Null takes 25% of your maximum mana (every 8 seconds at most).",
		"gift": "mana_on_kill", "offers": ["barrier_on_entry", "rollback", "heal_on_kill"]},
	"null_swap": {"zone": "act_5_page_file", "trigger": "enemy_killed", "code": "registry.clear()",
		"tip": "The Null swaps your references out: every kill empties every one of your skills' registries.",
		"gift": "heal_on_kill", "offers": ["registry_add", "slow", "barrier_on_entry"]},
	"null_regrow": {"zone": "act_5_kernel", "trigger": "enemy_spotted", "code": "target.max_hp += 20%",
		"tip": "The Null pads what guards the Kernel: every enemy you meet has 20% more maximum life.",
		"gift": "slow", "offers": ["weaken", "rollback", "mana_on_kill"]},
}


## The Last Log gives root at the Core; a REBOOTED character has it from the start (Reboot).
static func unlocked(qm: QuestManager) -> bool:
	return qm != null and (qm.is_completed(UNLOCK_QUEST) or Reboot.count(qm) > 0)


static func is_zone(scene_path: String) -> bool:
	return scene_path.get_file().get_basename() in ZONES


## The Null has submitted this request (you've been to its floor).
static func is_inserted(qm: QuestManager, null_id: String) -> bool:
	return qm != null and qm.deed_count(NULL_DEED, null_id) > 0


## Your answer to a request: "merge", "overwrite", "terminate", or "" (not answered yet).
static func answer_of(qm: QuestManager, null_id: String) -> String:
	if qm == null:
		return ""
	for a in ANSWERS:
		if qm.deed_count(deed_of(a), null_id) > 0:
			return a
	return ""


static func deed_of(answer: String) -> String:
	return {"merge": MERGE_DEED, "overwrite": OVERWRITE_DEED, "terminate": TERMINATE_DEED}.get(answer, "")


## Records the answer (once: a request is answered for good). The root line it brings, if any,
## is added to `lines` (SkillComponent.kernel): a merge's gift, or the overwrite's pick.
static func answer(qm: QuestManager, lines: Array[String], null_id: String, how: String, pick := "") -> void:
	if qm == null or not NULL_LINES.has(null_id) or answer_of(qm, null_id) != "" or not how in ANSWERS:
		return
	var line := ""
	if how == "merge":
		line = str(NULL_LINES[null_id]["gift"])
	elif how == "overwrite":
		line = pick if pick in offers(lines, null_id) else ""
	if line != "" and not line in lines:
		lines.append(line)
	GameEvents.report(deed_of(how), null_id)


## The two root lines an OVERWRITE of this request can put in its place: its offers you don't
## run yet (if you run them all, the first two anyway).
static func offers(lines: Array, null_id: String) -> Array:
	var all: Array = NULL_LINES.get(null_id, {}).get("offers", [])
	var fresh := all.filter(func(id: String) -> bool: return not id in lines)
	return (fresh if fresh.size() >= 2 else all).slice(0, 2)


## The Null's lines running now: the requests you merged. After OVERWRITE none ever run again:
## the Null is dormant (Endings: OVERWRITE).
static func null_running(qm: QuestManager) -> Array:
	if Endings.current(qm) == "overwrite":
		return []
	return NULL_LINES.keys().filter(func(id: String) -> bool: return answer_of(qm, id) == "merge")


## How many requests got each answer: {"merge": n, "overwrite": n, "terminate": n}.
static func tally(qm: QuestManager) -> Dictionary:
	var out := {"merge": 0, "overwrite": 0, "terminate": 0}
	for id in NULL_LINES:
		var a := answer_of(qm, id)
		if a != "":
			out[a] += 1
	return out


## The ending your kernel leans toward: the answer you gave most. A tie goes to the one you gave
## deepest down (the Kernel's, then the Page File's...), so the last word counts most. Nothing
## answered: terminate ("your kernel says very little").
static func lean(qm: QuestManager) -> String:
	var t := tally(qm)
	var best := 0
	for a in ANSWERS:
		best = maxi(best, int(t[a]))
	if best == 0:
		return "terminate"
	var ids: Array = NULL_LINES.keys()
	ids.reverse()                              # the deepest floor first
	for id in ids:
		var a := answer_of(qm, id)
		if a != "" and int(t[a]) == best:
			return a
	return "terminate"


## The Null request this zone submits ("" = none).
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
