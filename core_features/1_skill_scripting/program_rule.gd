class_name ProgramRule
extends Resource

const REMOVED_KNOBS: Array[StringName] = [&"max_targets", &"cleave_targets"]

@export var owner: String = ""
@export var conditions: Array[ProgramCondition] = []
@export var effects: Array[ProgramEffect] = []
@export var loop: ProgramLoop
@export var branches: Array[ProgramBranch] = []

var parent: ProgramRule
var branch_index := -1
var _own_count := 0


func is_always() -> bool:
	return conditions.is_empty()


func is_branch() -> bool:
	return parent != null


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


func flat() -> Array[ProgramRule]:
	var out: Array[ProgramRule] = [self]
	for i in branches.size():
		out.append(branch_rule(i))
	return out


func in_loop() -> bool:
	return parent != null and parent.loop != null


func has_break() -> bool:
	for b in branches:
		if b.breaks:
			return true
	return false


func loop_stops_itself() -> bool:
	return loop != null and (loop.mode == ProgramLoop.Mode.WHILE or has_break())


func branch() -> ProgramBranch:
	return parent.branches[branch_index] if parent != null else null


func own_conditions() -> Array[ProgramCondition]:
	if parent == null:
		return conditions
	var out: Array[ProgramCondition] = []
	out.assign(conditions.slice(conditions.size() - _own_count))
	return out


func scope() -> ProgramCondition.Scope:
	for c in conditions:
		if c.scope() == ProgramCondition.Scope.HIT:
			return ProgramCondition.Scope.HIT
	return ProgramCondition.Scope.CAST


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


const MIN_COST_MULT := 0.25
const CASH_IN_MIN_COST_MULT := 0.18

func cost_multiplier() -> float:
	var best := {}
	for c in conditions:
		var t := c.type_id()
		best[t] = minf(best.get(t, 1.0), c.cost_multiplier())
	return maxf(raw_cost_multiplier_of(best), min_cost_mult())


func is_discount_capped() -> bool:
	var best := {}
	for c in conditions:
		var t := c.type_id()
		best[t] = minf(best.get(t, 1.0), c.cost_multiplier())
	return raw_cost_multiplier_of(best) < min_cost_mult()


func min_cost_mult() -> float:
	return CASH_IN_MIN_COST_MULT if spends_marks() else MIN_COST_MULT


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


func repeated_condition() -> String:
	var seen := {}
	for c in conditions:
		if seen.has(c.type_id()) and not c.allows_repeats():
			return c.palette_name().to_lower().replace(" ", "_")
		seen[c.type_id()] = true
	return ""


func only_on_repeats() -> bool:
	if loop != null:
		return false
	for c in conditions:
		if c.needs_loop():
			return true
	return false


func action_count() -> int:
	var n := conditions.size() + (loop.action_count() if loop != null else 0)
	for e in effects:
		if not ScriptRegisters.is_write(e.knob):
			n += 1
	for b in branches:
		n += b.conditions.size() + (1 if b.breaks else 0)
		for e in b.effects:
			if not ScriptRegisters.is_write(e.knob):
				n += 1
	return n


func uses_registers() -> bool:
	if not branches.is_empty():
		return true
	for e in effects:
		if ScriptRegisters.is_write(e.knob) or e.ramps():
			return true
	return false


func is_baked() -> bool:
	return is_always() and loop == null


func describe(limits: SkillProgramLimits) -> String:
	var whens: Array[String] = []
	for c in conditions:
		whens.append(c.describe())
	var dos: Array[String] = []
	for e in effects:
		if e.is_call():
			dos.append("CALL routine %d" % (e.op + 1))
			continue
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
			if e.is_call():
				bdos.append("CALL routine %d" % (e.op + 1))
			elif ScriptRegisters.is_write(e.knob):
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
		if not e.knob in REMOVED_KNOBS:
			r.effects.append(e)
	if d.get("loop") is Dictionary:
		r.loop = ProgramLoop.from_dict(d["loop"])
	for bd in d.get("branches", []):
		if bd is Dictionary:
			r.branches.append(ProgramBranch.from_dict(bd))
	if r.loop != null and r.loop.break_on != ProgramLoop.Break.NONE:
		r.branches.append(ProgramBranch.legacy_break(r.loop.break_on == ProgramLoop.Break.KILL))
		r.loop.break_on = ProgramLoop.Break.NONE
	return r
