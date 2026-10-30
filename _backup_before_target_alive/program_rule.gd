class_name ProgramRule
extends Resource
## One line of a skill program: WHEN all conditions are true, DO all effects.
## No conditions = ALWAYS: the effects are baked into the skill when it is rebuilt.
## With a loop (FOR / WHILE, see ProgramLoop) the rule repeats the skill instead, and its
## effects only apply to those repeats (the loop body).

## Which gem this rule belongs to: "" = the skill, or a support gem's id. A rule may only
## move knobs of its own gem. Rules of a support are removed when that support is unsocketed.
@export var owner: String = ""
@export var conditions: Array[ProgramCondition] = []
@export var effects: Array[ProgramEffect] = []
## null = no loop.
@export var loop: ProgramLoop


func is_always() -> bool:
	return conditions.is_empty()


## HIT if any condition needs a target, otherwise CAST.
func scope() -> ProgramCondition.Scope:
	for c in conditions:
		if c.scope() == ProgramCondition.Scope.HIT:
			return ProgramCondition.Scope.HIT
	return ProgramCondition.Scope.CAST


func all_true(cast: SkillCast, target: Node) -> bool:
	for c in conditions:
		if not c.is_true(cast, target):
			return false
	return true


## Stacked conditions never make buffs cheaper than this. It's the lowest any single condition
## goes on its own (every_nth_cast(7+)), so it only limits stacking several conditions.
const MIN_COST_MULT := 0.25

## Different conditions stack: two 0.6 conditions make the effects cost 0.36 of the price
## (down to MIN_COST_MULT).
## The same kind of condition counts once, at its strictest (cheapest) setting: repeating
## target_life_below(90%) changes nothing about when the rule fires, so it can't be a discount.
func cost_multiplier() -> float:
	var best := {}                        # condition type -> lowest multiplier among its copies
	for c in conditions:
		var t := c.type_id()
		best[t] = minf(best.get(t, 1.0), c.cost_multiplier())
	return maxf(raw_cost_multiplier_of(best), MIN_COST_MULT)


## True when the conditions would stack below MIN_COST_MULT (the editor says so).
func is_discount_capped() -> bool:
	var best := {}
	for c in conditions:
		var t := c.type_id()
		best[t] = minf(best.get(t, 1.0), c.cost_multiplier())
	return raw_cost_multiplier_of(best) < MIN_COST_MULT


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
		if seen.has(c.type_id()):
			return c.palette_name().to_lower().replace(" ", "_")
		seen[c.type_id()] = true
	return ""


func action_count() -> int:
	return conditions.size() + effects.size() + (loop.action_count() if loop != null else 0)


## A plain ALWAYS rule, baked into the skill (not a loop).
func is_baked() -> bool:
	return is_always() and loop == null


func describe(limits: SkillProgramLimits) -> String:
	var whens: Array[String] = []
	for c in conditions:
		whens.append(c.describe())
	var dos: Array[String] = []
	for e in effects:
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
	return d


static func from_dict(d: Dictionary) -> ProgramRule:
	var r := ProgramRule.new()
	r.owner = str(d.get("owner", ""))
	for cd in d.get("if", []):
		var c := ProgramConditions.from_dict(cd)
		if c != null:
			r.conditions.append(c)
	for ed in d.get("do", []):
		r.effects.append(ProgramEffect.from_dict(ed))
	if d.get("loop") is Dictionary:
		r.loop = ProgramLoop.from_dict(d["loop"])
	return r
