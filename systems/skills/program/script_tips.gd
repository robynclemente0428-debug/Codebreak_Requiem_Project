class_name ScriptTips
extends RefCounted
## One-line tips in the SCRIPTING editor's OUTPUT, shown the first time a player runs into each
## idea (their first drawback, first time over budget, first efficiency tier...). For players
## who skip the guide: they learn each rule at the moment it matters, next to its cause.
## Each tip shows once per character (saved with it, like TutorialHints' lessons) and links to
## the guide page that explains it. Gameplay setting "script_tips" turns them off.
##
## SkillScriptTab asks next_tip() on every rebuild; the first triggered tip not yet seen wins,
## in TIPS order (more urgent first). "applied" is triggered by apply() itself.

const SAVE_KEY := "script_tips_seen"
const SETTING := "script_tips"

## id -> [text, guide page id (ScriptGuide.PAGES)]. %s in a text is filled in by next_tip().
const TIPS := {
	"over_budget": ["over budget: lower a + line, make a when rule rarer, or add a - line in always:.", "points"],
	"when_drawback": ["points a when rule gives back only pay for that rule. Put drawbacks in always: to fund the others.", "points"],
	"drawback": ["a - line makes the skill worse but gives points back. Spend them on any + line.", "points"],
	"two_conditions": ["when A and B: both must be true. Rarer, so its buffs are cheaper.", "cheaper"],
	"stacked_steps": ["each step on the same line costs more than the last. Spreading steps over a few lines is cheaper.", "points"],
	"when_rule": ["when rules are cheaper: %s means its buffs cost %s of the price. Rarer = cheaper.", "cheaper"],
	"tier": ["%s: short scripts hit harder. Fewer blocks keep the bonus.", "blocks"],
	"applied": ["applied! A when rule only fires when its condition happens: try it in a fight.", "apply"],
}
const STACKED_STEPS := 3                   # buff steps on one line before "stacked_steps"


## The first tip `program` (checked as `v` against `limits`) triggers that this character hasn't
## seen: {id, text, page}, or {} for none.
static func next_tip(program: SkillProgram, v: ProgramValidation, limits: SkillProgramLimits) -> Dictionary:
	if program == null or v == null or limits == null or not enabled():
		return {}
	var hits := _triggered(program, v, limits)
	for id in TIPS:
		if hits.has(id) and not seen(id):
			return tip(id, hits[id])
	return {}


## {id, text, page} for tip `id`, with `args` filled into its text.
static func tip(id: String, args: Array = []) -> Dictionary:
	var t: String = TIPS[id][0]
	if t.count("%s") == args.size() and not args.is_empty():
		t = t % args
	return {"id": id, "text": t, "page": TIPS[id][1]}


## Tip id -> the values its text needs, for every tip this program triggers right now.
static func _triggered(program: SkillProgram, v: ProgramValidation, limits: SkillProgramLimits) -> Dictionary:
	var out := {}
	if not program.has_rules():
		return out
	if v.buff_points > v.drawback_points + v.point_budget + 0.001:
		out["over_budget"] = []
	for rule in program.flat_rules():
		var always := rule.is_always()
		if not always:
			if not out.has("when_rule"):
				var m := rule.cost_multiplier()
				out["when_rule"] = ["x%.2f" % m, "%d%%" % roundi(m * 100.0)]
			if rule.own_conditions().size() >= 2 or (rule.is_branch() and rule.conditions.size() >= 2):
				out["two_conditions"] = []
		for e in rule.effects:
			var k := limits.get_knob(e.knob)
			if k == null or ScriptRegisters.is_write(e.knob) or e.steps == 0:
				continue
			if not k.is_buff(e.steps):
				out["when_drawback" if not always else "drawback"] = []
			elif absi(e.steps) >= STACKED_STEPS:
				out["stacked_steps"] = []
	if v.tier != null:
		out["tier"] = [v.tier.display_name.to_upper() + " (" + v.tier.description.trim_suffix(".") + ")"]
	return out


static func enabled() -> bool:
	return bool(Settings.get_value("gameplay", SETTING))


## Saved with the host's character (seat 0), like TutorialHints' lessons.
static func seen(id: String) -> bool:
	if SaveManager.party.is_empty():
		return false
	return id in SaveManager.get_data(SaveManager.party[0]).get(SAVE_KEY, [])


static func mark_seen(id: String) -> void:
	for slot in SaveManager.party:
		var data: Dictionary = SaveManager.get_data(slot)
		var done: Array = data.get(SAVE_KEY, [])
		if not id in done:
			done.append(id)
		data[SAVE_KEY] = done
