class_name ProgramValidation
extends RefCounted
## The result of checking a SkillProgram against its gem's limits. The editor UI shows this
## live while the player drags blocks: budget bar, action count, tier and any errors.

var valid := true
var errors: Array[String] = []

var points_used := 0.0
## points_used split for the budget bar: buffs cost, drawbacks pay. points_used = buff - drawback.
var buff_points := 0.0
var drawback_points := 0.0
var point_budget := 0.0
var actions_used := 0
var max_actions := 0
## The efficiency tier the program earns (null if none, or if it has no rules).
var tier: EfficiencyTier
## The next tier up and how many actions must be removed to reach it (for "2 fewer -> Elegant").
var next_tier: EfficiencyTier
var actions_to_next_tier := 0
## knob id -> [lowest possible steps, highest possible steps] across all rules.
var knob_ranges: Dictionary = {}


## Every problem, linked to where it is so the editor can mark the line. Each entry:
##   text   short message for that line ("attack_speed only works in an always: rule")
##   hint   what to do about it
##   rule   the ProgramRule it's in (null = the program as a whole)
##   part   the ProgramCondition / ProgramEffect / ProgramLoop on that line (null = the rule header)
##   kind   "error", or "note" (e.g. the rule that costs the most when over budget)
##   dup    true for extra lines of an error already counted (a knob pushed too far by 3 lines)
## `errors` keeps one full sentence per problem, as before (logs, tests, notifications).
var issues: Array[Dictionary] = []


## A problem with no single line to point at (too many blocks, over budget...).
func add_error(msg: String, hint: String = "") -> void:
	valid = false
	errors.append(msg)
	issues.append({"text": msg, "hint": hint, "rule": null, "part": null, "kind": "error", "dup": false})


## A problem on one line. `full` goes to `errors`; `text` is the short form shown on the line.
## count = false marks another line of an error that was already counted.
func add_issue(full: String, text: String, hint: String, rule: ProgramRule, part: Object = null,
		count: bool = true) -> void:
	valid = false
	if count:
		errors.append(full)
	var at := _at(rule, part)
	issues.append({"text": text, "hint": hint, "rule": at[0], "part": at[1], "kind": "error", "dup": not count})


## Not an error: extra information pinned to a line (shown in amber).
func add_note(text: String, hint: String, rule: ProgramRule, part: Object = null) -> void:
	var at := _at(rule, part)
	issues.append({"text": text, "hint": hint, "rule": at[0], "part": at[1], "kind": "note", "dup": true})


## A problem found on an "if" block's rule (ProgramRule.branch_rule) belongs to the real rule the
## editor shows; with no line of its own, it goes on the block's "if" line (the ProgramBranch).
static func _at(rule: ProgramRule, part: Object) -> Array:
	if rule != null and rule.is_branch():
		return [rule.parent, part if part != null else rule.branch()]
	return [rule, part]


## Number of distinct errors (extra lines of the same error and notes don't count).
func error_count() -> int:
	var n := 0
	for i in issues:
		if i["kind"] == "error" and not i["dup"]:
			n += 1
	return n


func points_left() -> float:
	return point_budget - points_used
