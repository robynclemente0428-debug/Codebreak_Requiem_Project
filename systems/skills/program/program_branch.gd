class_name ProgramBranch
extends Resource
## An "if" block nested inside a rule (the Strategist rank's unlock, with the Registry):
##
##   when every_nth_cast(3):
##       radius += 1.0m              the rule's own lines: the whole cast
##       if target in registry:      a branch: its conditions, checked only when the rule fired
##           damage += 50%           its lines, under the rule's conditions AND its own
##           registry.remove(target)
##
## One level deep: a branch has no branches of its own, and a rule with a loop has none.
## Its conditions may be per-hit (target in registry, target_life_below) or per-cast; a per-hit
## branch's lines keep the per-hit limits. ProgramRule.branch_rule() turns a branch into the rule
## it means (the outer conditions + its own) for pricing, validation and ProgramSupport.

@export var conditions: Array[ProgramCondition] = []
@export var effects: Array[ProgramEffect] = []


func to_dict() -> Dictionary:
	var conds: Array = []
	for c in conditions:
		conds.append(c.to_dict())
	var effs: Array = []
	for e in effects:
		effs.append(e.to_dict())
	return {"if": conds, "do": effs}


static func from_dict(d: Dictionary) -> ProgramBranch:
	var b := ProgramBranch.new()
	for cd in d.get("if", []):
		var c := ProgramConditions.from_dict(cd)
		if c != null:
			b.conditions.append(c)
	for ed in d.get("do", []):
		var e := ProgramEffect.from_dict(ed)
		if not e.knob in ProgramRule.REMOVED_KNOBS:
			b.effects.append(e)
	return b
