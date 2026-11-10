class_name ProgramRule
extends Resource
## One line of a skill program: WHEN all conditions are true, DO all effects.
## No conditions = ALWAYS: the effects are baked into the skill when it is rebuilt.
## With a loop (FOR / WHILE, see ProgramLoop) the rule repeats the skill instead, and its
## effects only apply to those repeats (the loop body).

## Knobs taken out of the game. Saved scripts still name them, so their lines are skipped on
## load (max_targets: every skill now hits everyone in its area).
const REMOVED_KNOBS: Array[StringName] = [&"max_targets", &"cleave_targets"]

## Which gem this rule belongs to: "" = the skill, or a support gem's id. A rule may only
## move knobs of its own gem. Rules of a support are removed when that support is unsocketed.
@export var owner: String = ""
@export var conditions: Array[ProgramCondition] = []
@export var effects: Array[ProgramEffect] = []
## null = no loop.
@export var loop: ProgramLoop
## "if" blocks nested in this rule (ProgramBranch). Not allowed with a loop.
@export var branches: Array[ProgramBranch] = []

## Set only on the rule branch_rule() builds for a branch: the rule it is nested in, and which
## of its branches it is. Such a rule's conditions are the outer rule's followed by the branch's.
var parent: ProgramRule
var branch_index := -1
var _own_count := 0                       # how many of `conditions` belong to the branch itself


func is_always() -> bool:
	return conditions.is_empty()


func is_branch() -> bool:
	return parent != null


## The rule a branch means: the outer rule's conditions AND the branch's, doing the branch's
## lines. Built fresh each call; its condition and effect objects are the real ones.
func branch_rule(i: int) -> ProgramRule:
	var b := branches[i]
	var r := ProgramRule.new()
	r.owner = owner
	r.conditions.assign(conditions + b.conditions)
	r.effects.assign(b.effects)
	r.parent = self
	r.branch_index = i
	r._own_count = b.conditions.size()
	return r


## This rule, then one rule per branch (branch_rule): what pricing, validation and ProgramSupport
## go through.
func flat() -> Array[ProgramRule]:
	var out: Array[ProgramRule] = [self]
	for i in branches.size():
		out.append(branch_rule(i))
	return out


## The branch a branch rule stands for (null for an ordinary rule).
func branch() -> ProgramBranch:
	return parent.branches[branch_index] if parent != null else null


## The conditions that are this rule's own: a branch's, without the outer rule's. They are the
## ones a branch announces when it fires (the outer rule announced its own already).
func own_conditions() -> Array[ProgramCondition]:
	if parent == null:
		return conditions
	var out: Array[ProgramCondition] = []
	out.assign(conditions.slice(conditions.size() - _own_count))
	return out


## HIT if any condition needs a target, otherwise CAST.
func scope() -> ProgramCondition.Scope:
	for c in conditions:
		if c.scope() == ProgramCondition.Scope.HIT:
			return ProgramCondition.Scope.HIT
	return ProgramCondition.Scope.CAST


## A branch rule doesn't judge the outer rule's per-cast conditions again: it asks whether the
## outer rule fired for this cast (ProgramSupport.rule_fired), so a condition that spends
## something (Variable Store's charge) is only spent once. Per-hit outer conditions are read again
## for each hit, since they are about the enemy being hit.
func all_true(cast: SkillCast, target: Node) -> bool:
	if parent != null:
		if not parent.is_always():
			if parent.scope() == ProgramCondition.Scope.CAST:
				if not ProgramSupport.rule_fired(cast, parent):
					return false
			elif not parent.all_true(cast, target):
				return false
		for c in own_conditions():
			if not c.is_true(cast, target):
				return false
		return true
	for c in conditions:
		if not c.is_true(cast, target):
			return false
	return true


## Stacked conditions never make buffs cheaper than this. It's the lowest any single condition
## goes on its own (every_nth_cast(7+)), so it only limits stacking several conditions.
const MIN_COST_MULT := 0.25
## A cash-in rule (spends_marks) may stack further, down to this: each of its marks pays out once,
## so a rare one (every_nth_cast(4) and target in registry) keeps getting cheaper.
const CASH_IN_MIN_COST_MULT := 0.18

## Different conditions stack: two 0.6 conditions make the effects cost 0.36 of the price
## (down to min_cost_mult()).
## The same kind of condition counts once, at its strictest (cheapest) setting: repeating
## target_life_below(90%) changes nothing about when the rule fires, so it can't be a discount.
func cost_multiplier() -> float:
	var best := {}                        # condition type -> lowest multiplier among its copies
	for c in conditions:
		var t := c.type_id()
		best[t] = minf(best.get(t, 1.0), c.cost_multiplier())
	return maxf(raw_cost_multiplier_of(best), min_cost_mult())


## True when the conditions would stack below min_cost_mult() (the editor says so).
func is_discount_capped() -> bool:
	var best := {}
	for c in conditions:
		var t := c.type_id()
		best[t] = minf(best.get(t, 1.0), c.cost_multiplier())
	return raw_cost_multiplier_of(best) < min_cost_mult()


## The lowest this rule's conditions can stack to: CASH_IN_MIN_COST_MULT for a cash-in rule.
func min_cost_mult() -> float:
	return CASH_IN_MIN_COST_MULT if spends_marks() else MIN_COST_MULT


## True for a cash-in rule: it checks "target in registry" and spends that mark itself, with a
## registry.remove(target) in the same rule. A remove in another rule doesn't count.
func spends_marks() -> bool:
	var checks := false
	for c in conditions:
		var read := c as VarCondition
		checks = checks or (read != null and read.is_membership() and read.op_text() == "in")
	if not checks:
		return false
	for e in effects:
		if ScriptRegisters.is_write(e.knob) and e.write_op() == "remove":
			return true
	return false


static func raw_cost_multiplier_of(best: Dictionary) -> float:
	var m := 1.0
	for t in best:
		m *= best[t]
	return m


## The editor name of the first condition that appears more than once in this rule
## ("" = none), e.g. "target_life_below".
func repeated_condition() -> String:
	var seen := {}
	for c in conditions:
		if seen.has(c.type_id()) and not c.allows_repeats():
			return c.palette_name().to_lower().replace(" ", "_")
		seen[c.type_id()] = true
	return ""


## True when this rule (without a loop of its own) can only fire on loop repeats, because one of
## its conditions is about a repeat (target_alive...). Its effects then only change repeats.
func only_on_repeats() -> bool:
	if loop != null:
		return false
	for c in conditions:
		if c.needs_loop():
			return true
	return false


## Writing the registry doesn't count as a block (ScriptRegisters).
## An "if" block costs its conditions and lines, like the rule's own: the outer conditions are
## written once, which is what makes nesting cheaper than repeating them in another rule.
func action_count() -> int:
	var n := conditions.size() + (loop.action_count() if loop != null else 0)
	for e in effects:
		if not ScriptRegisters.is_write(e.knob):
			n += 1
	for b in branches:
		n += b.conditions.size()
		for e in b.effects:
			if not ScriptRegisters.is_write(e.knob):
				n += 1
	return n


## True when part of this rule has to run per cast even in always: (registry.add(target),
## damage += registry.size * 1%, or an "if" block).
func uses_registers() -> bool:
	if not branches.is_empty():
		return true
	for e in effects:
		if ScriptRegisters.is_write(e.knob) or e.ramps():
			return true
	return false


## A plain ALWAYS rule, baked into the skill (not a loop).
func is_baked() -> bool:
	return is_always() and loop == null


func describe(limits: SkillProgramLimits) -> String:
	var whens: Array[String] = []
	for c in conditions:
		whens.append(c.describe())
	var dos: Array[String] = []
	for e in effects:
		if ScriptRegisters.is_write(e.knob):
			dos.append(e.describe_write())
			continue
		var k := limits.get_knob(e.knob) if limits != null else null
		dos.append(k.describe(e.steps) if k != null else "%s %+d" % [e.knob, e.steps])
	var head := "ALWAYS" if whens.is_empty() else " AND ".join(whens)
	if loop != null:
		if loop.mode == ProgramLoop.Mode.WHILE:
			head = head.replace("WHEN ", "WHILE ")
		var body := loop.describe()
		if not dos.is_empty():
			body += " with " + ", ".join(dos)
		return "%s -> %s" % [head, body]
	for b in branches:
		var ifs: Array[String] = []
		for c in b.conditions:
			ifs.append(c.describe().trim_prefix("WHEN "))
		var bdos: Array[String] = []
		for e in b.effects:
			if ScriptRegisters.is_write(e.knob):
				bdos.append(e.describe_write())
			else:
				var bk := limits.get_knob(e.knob) if limits != null else null
				bdos.append(bk.describe(e.steps) if bk != null else "%s %+d" % [e.knob, e.steps])
		dos.append("IF %s -> [%s]" % [" AND ".join(ifs), ", ".join(bdos)])
	return "%s -> %s" % [head, ", ".join(dos)]


func to_dict() -> Dictionary:
	var conds: Array = []
	for c in conditions:
		conds.append(c.to_dict())
	var effs: Array = []
	for e in effects:
		effs.append(e.to_dict())
	var d := {"if": conds, "do": effs}
	if owner != "":
		d["owner"] = owner
	if loop != null:
		d["loop"] = loop.to_dict()
	if not branches.is_empty():
		var bs: Array = []
		for b in branches:
			bs.append(b.to_dict())
		d["branches"] = bs
	return d


static func from_dict(d: Dictionary) -> ProgramRule:
	var r := ProgramRule.new()
	r.owner = str(d.get("owner", ""))
	for cd in d.get("if", []):
		var c := ProgramConditions.from_dict(cd)
		if c != null:
			r.conditions.append(c)
	for ed in d.get("do", []):
		var e := ProgramEffect.from_dict(ed)
		if not e.knob in REMOVED_KNOBS:              # old saves: knobs that no longer exist
			r.effects.append(e)
	if d.get("loop") is Dictionary:
		r.loop = ProgramLoop.from_dict(d["loop"])
	for bd in d.get("branches", []):
		if bd is Dictionary:
			r.branches.append(ProgramBranch.from_dict(bd))
	return r
