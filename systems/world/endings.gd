class_name Endings
extends RefCounted
## Act V's three endings, after the Root Process: what each one says (the epilogue pages
## EndingCard shows), and what it leaves behind.
##   MERGE      the Null finishes. Vesper merges into the Core (gone from it; her voice is the
##              Last Log's). The Core turns violet. Your root lines and the Null lines you merged
##              run in every dungeon, not only below the Core (KernelDirector).
##   OVERWRITE  a patch. The Null goes dormant. The Core is the Architects' white and gold again.
##              kernel.gd becomes yours to edit (MAX_ROOT_LINES root lines, any you like), they run
##              in every dungeon, and the Null's lines never run again.
##   TERMINATE  shutdown. The Core goes dark but for the Last Log's terminal. The epilogue is your
##              FINAL LOG: the run, from what the save keeps.
## The choice is final: once made, choose() refuses another, and the Last Log only offers to read
## the epilogue again (> epilogue). It's kept as the deed ending_now:<id>; a save from when the
## ending could be chosen again keeps the last one it chose.
## Co-op: each player's own (their own save), so each sees their own Core.
##
## Open on purpose: who signed the Null (Architect log 2) is never named here.

const NOW_DEED := "ending_now"              # ending_now:<id>, only one at a time
const IDS := ["merge", "overwrite", "terminate"]
## Overwrite's kernel.gd: at most this many root lines, picked by hand.
const MAX_ROOT_LINES := 4
## MERGE's violet slot: this many more rules on every skill (SkillProgramLimits.bonus_rules).
const MERGE_RULES := 1

const TITLES := {"merge": "MERGED", "overwrite": "PATCHED", "terminate": "LAST ENTRY"}
const COLOURS := {
	"merge": Color(0.75, 0.45, 1.0),
	"overwrite": Color(1.0, 0.85, 0.45),
	"terminate": Color(1.0, 0.35, 0.35),
}

## The epilogue's line for each floor, by the answer you gave its pull request.
const FLOOR_LINES := {
	"null_armour": {
		"merge": "The Stack Trace still replays everything, harder than before. Nobody minds. It's how the Core remembers.",
		"overwrite": "The Stack Trace replays in order now, soft enough to read.",
		"terminate": "The Stack Trace was shut down. The Core lost its memory of the order things happened in.",
	},
	"null_drain": {
		"merge": "Sentinel's Hall drinks a little from whoever passes. They let it.",
		"overwrite": "Sentinel's Hall keeps your line, and nothing else.",
		"terminate": "Sentinel's Hall stands empty. Nothing guards it, and nothing needs to.",
	},
	"null_swap": {
		"merge": "Things still page out of the Page File, and come back changed.",
		"overwrite": "Nothing pages out any more. Whatever is referenced stays.",
		"terminate": "The Page File stayed shut down. Whatever was swapped out stays out.",
	},
	"null_regrow": {
		"merge": "The Kernel grows what guards it. It grows gently now.",
		"overwrite": "The Kernel runs your patch, line for line, exactly as written.",
		"terminate": "The Kernel is quiet. Nothing at the bottom of the Core asks for anything.",
	},
}


# ---------- WHICH ENDING ----------
## The ending the world shows now ("" = none chosen yet).
static func current(qm: QuestManager) -> String:
	if qm == null:
		return ""
	for id in IDS:
		if qm.deed_count(NOW_DEED, id) > 0:
			return id
	for id in IDS:                             # a save from before ending_now: one it chose
		if qm.deed_count("ending", id) > 0:
			return id
	return ""


## The Last Log's button: `id` becomes the ending, for good, and the `ending` deed records it.
## False (nothing changes) once an ending is chosen.
static func choose(qm: QuestManager, id: String) -> bool:
	if qm == null or not id in IDS or current(qm) != "":
		return false
	for other in IDS:
		qm.deeds.erase("%s:%s" % [NOW_DEED, other])
	qm.deeds["%s:%s" % [NOW_DEED, id]] = 1
	GameEvents.report("ending", id)
	Coop.kernel_changed()                      # co-op: whether our lines run everywhere now
	var tree := Engine.get_main_loop() as SceneTree
	var player := tree.get_first_node_in_group("players") if tree != null else null
	if player != null and player.get("skills") != null:
		player.skills.refresh_rank()           # MERGE's violet slot, on every skill now
	return true


## Root lines and merged Null lines run in every dungeon, not only below the Core.
## Also after a REBOOT: the root lines carried over run from Act I (Reboot).
static func runs_everywhere(qm: QuestManager) -> bool:
	return current(qm) in ["merge", "overwrite"] or Reboot.count(qm) > 0


## MERGE's reward: one more rule on every skill (the violet slot).
static func bonus_rules(qm: QuestManager) -> int:
	return MERGE_RULES if current(qm) == "merge" else 0


## Overwrite's reward: kernel.gd is editable by hand.
static func kernel_editable(qm: QuestManager) -> bool:
	return current(qm) == "overwrite"


# ---------- THE EPILOGUE ----------
## The pages EndingCard shows for `id`: [{title, text, colour}, ...].
static func pages(qm: QuestManager, player: Node, id: String) -> Array:
	var col: Color = COLOURS.get(id, Color.WHITE)
	var out: Array = []
	match id:
		"merge":
			out.append(_page("MERGE", col, "You let the Null's process complete.\n\nAXIOM does not end. It transforms. The rules rewrite themselves, one by one, "
				+ "and what comes out is something neither the Architects nor the Null designed alone. You wrote some of it."))
			out.append(_page("VESPER", col, "She stopped at the Last Log's terminal and didn't walk away from it.\n\n"
				+ "Her voice is in the Core now, finishing its sentences. Sometimes it finishes yours. She sounds happy. It's hard to tell."))
			out.append(_page("HARDFAULT", col, _brack(qm, "merge")))
			out.append(_page("HEX AND SUDO", col, "Hex's new stock hums when you pick it up. She charges extra for that.\n\n"
				+ "Sudo closes the sandbox. \"No more exams. It grades itself now.\""))
		"overwrite":
			out.append(_page("OVERWRITE", col, "You write a patch from scratch: one that holds AXIOM together without finishing the Null's work.\n\n"
				+ "It works, partly. AXIOM survives as it is, degraded but knowable. The Null goes quiet, and stays quiet."))
			out.append(_page("THE CONVOY", col, _convoy(qm)))
			out.append(_page("VESPER", col, "The Null's voice went quiet in her too.\n\n"
				+ "She's ordinary now. She says it's restful. She says it twice, as if one of them was for someone else."))
			out.append(_page("HEX AND SUDO", col, "Hex's prices come down to something close to fair. Close.\n\n"
				+ "Sudo keeps the sandbox open. \"Somebody has to maintain a patch. It may as well be graded.\""))
		"terminate":
			out.append(_page("TERMINATE", col, "A controlled shutdown, at the Core.\n\nAXIOM ends. Every process in it simply stops. "
				+ "Your log is the last thing written in its history."))
			out.append(_page("// FINAL LOG //", col, "\n".join(final_log(qm, player))))
			out.append(_page("VESPER", col, "She asked to be the last one switched off, so that someone would hear the end.\n\n"
				+ "\"Go on. I'm listening.\""))
	out.append(_page("YOUR KERNEL", col, "\n\n".join(kernel_lines(qm))))
	out.append(_page("AFTER", col, _after(id) + "\n\n// The Last Log can show the other endings."))
	if id == "terminate":
		out.append(_page("", col, "// END OF LOG.\n\nGoodbye, Executor."))
	return out


## One line per floor, by your answer to its pull request (unanswered floors left out).
static func kernel_lines(qm: QuestManager) -> PackedStringArray:
	var out := PackedStringArray()
	for nid in KernelScript.NULL_LINES:
		var a := KernelScript.answer_of(qm, nid)
		if a != "":
			out.append(str(FLOOR_LINES[nid][a]))
	if out.is_empty():
		out.append("Your kernel says very little. The Core will have to decide for itself.")
	return out


## Terminate's FINAL LOG: the run, from what the save keeps.
static func final_log(qm: QuestManager, player: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var who := "EXECUTOR"
	if player != null and is_instance_valid(player):
		var c = player.get("class_data")
		who = str(c.display_name).to_upper() if c != null and c.get("display_name") != null else who
	out.append("> executor   %s" % who)
	out.append("> rank       %s" % Ranks.current(qm))
	var grades := PackedStringArray()
	for r in Ranks.LADDER:
		var g := qm.exam_grade(r["id"]) if r["id"] != "" else -1
		if g >= 0:
			grades.append("%s %s" % [str(r["name"]).to_lower(), ExamSpec.GRADES[clampi(g, 0, ExamSpec.GRADES.size() - 1)]])
	out.append("> exams      %s" % (", ".join(grades) if not grades.is_empty() else "none sat"))
	var bosses := ScriptBudget.act_bosses_killed(qm)
	out.append("> bosses     %d broken" % bosses.size())
	out.append("> areas      %d cleared" % ScriptBudget.cleared_areas(qm).size())
	var logs := 0
	for k in ["architect_log_a", "architect_log_b", "architect_log_c"]:
		if qm.has_recovered(k):
			logs += 1
	out.append("> logs       %d of 3 Architect logs found" % logs)
	var t := KernelScript.tally(qm)
	out.append("> kernel     merged %d, overwrote %d, terminated %d" % [t["merge"], t["overwrite"], t["terminate"]])
	return out


static func _brack(qm: QuestManager, _id: String) -> String:
	if qm != null and qm.is_completed("static_from_home"):
		return "A relay call reaches Checkpoint in Brack's voice, still in the Null's syntax: keep moving until someone answers.\n\n" \
			+ "This time something does. Hardfault stops packing."
	return "Word reaches Checkpoint the slow way, by relay, in a syntax nobody taught them.\n\n" \
		+ "Brack reads it twice and tells everyone to unpack. Nobody argues."


static func _convoy(qm: QuestManager) -> String:
	var lost := 0
	for id in YardCrates.ORDER:
		if YardCrates.is_deleted(qm, id):
			lost += 1
	var total := YardCrates.ORDER.size()
	var count := ("Every crate Hardfault carried in made it." if lost == 0
		else "%d of the %d crates Hardfault carried in made it." % [total - lost, total])
	return "Hardfault's convoy keeps moving, at Checkpoint's pace. %s\n\n" % count \
		+ "The Registrar files it without being asked. \"Records updated. Patch applied.\""


static func _after(id: String) -> String:
	match id:
		"merge":
			return "Your root lines and the Null's lines you merged now run in every dungeon, not only below the Core.\n\n" \
					+ "Every skill has one more rule, a violet one: the Null's.\n\n" \
					+ "The Recursion is open above the Core. The Null builds some of its floors."
		"overwrite":
			return ("kernel.gd is yours. Open it in your scripts and choose up to %d root lines: they run in every dungeon, and the Null's never do." % MAX_ROOT_LINES) \
					+ ("\n\nThe Recursion is open above the Core. Every %d floors you climb earns a patch: take a threat out of a floor, carry one up, or roll it again." % Tower.PATCH_EVERY)
		"terminate":
			return "The Core is dark. The Last Log's terminal is the only light left in it.\n\n" \
					+ "AXIOM can boot again. At Character Select this character can REBOOT: a new run with your rank, scripts and routines, against a world that remembers you."
	return ""


static func _page(title: String, col: Color, text: String) -> Dictionary:
	return {"title": title, "colour": col, "text": text}
