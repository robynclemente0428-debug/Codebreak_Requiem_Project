class_name ProgramBranch
extends Resource
## An "if" block nested inside a rule (the Architect rank's unlock, with loops):
##
##   when every_nth_cast(3):
##       radius += 1.0m              the rule's own lines: the whole cast
##       if target in registry:      a branch: its conditions, checked only when the rule fired
##           damage += 50%           its lines, under the rule's conditions AND its own
##           registry.remove(target)
##
## In a rule with a loop it is checked on every repeat: its lines change only the repeats it's
## true for, and it may end with  break  (the loop stops when it's true):
##
##   while enemies_nearby(3, 4.0m):
##       cast(max=4)
##       if killed:                  checked after each cast or repeat lands
##           damage += 20%           the next repeat hits harder
##       if hit_nothing:
##           break                   stop: no more repeats
##
## One level deep: a branch has no branches of its own.
## Its conditions may be per-hit (target in registry, target_life_below) or per-cast; a per-hit
## branch's lines keep the per-hit limits. ProgramRule.branch_rule() turns a branch into the rule
## it means (the outer conditions + its own) for pricing, validation and ProgramSupport.

@export var conditions: Array[ProgramCondition] = []
@export var effects: Array[ProgramEffect] = []
## A  break  line at the end of the block: only in a rule with a loop. When the block is true
## after a cast or repeat lands, its loop stops (ProgramLoopRunner). One block, and it makes
## the loop cheaper (ProgramLoop.BREAK_COST_MULT): it can only cut it short.
@export var breaks := false


func to_dict() -> Dictionary:
	var conds: Array = []
	for c in conditions:
		conds.append(c.to_dict())
	var effs: Array = []
	for e in effects:
		effs.append(e.to_dict())
	var d := {"if": conds, "do": effs}
	if breaks:
		d["break"] = true
	return d


## A break block for an old save's loop break (ProgramLoop.break_on): if killed / if hit_nothing.
static func legacy_break(on_kill: bool) -> ProgramBranch:
	var b := ProgramBranch.new()
	b.conditions.append(ProgramConditions.create("killed" if on_kill else "hit_nothing"))
	b.breaks = true
	return b


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
	b.breaks = bool(d.get("break", false))
	return b
