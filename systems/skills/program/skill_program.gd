class_name SkillProgram
extends Resource
## A player-made program for one skill socket: a short list of WHEN/DO rules.
##
##   ALWAYS                     -> Damage +20%, Mana cost +40%, Attack speed -10%
##   WHEN 3+ enemies within 4 m -> Range bonus +1.00 m, Damage -15%
##
## Pricing (see SkillKnob for per-step costs):
##   ALWAYS rule       cost = sum of its effect costs (drawbacks are negative and pay for buffs)
##   conditional rule  cost = max(0, sum) x condition cost multipliers
##                     A conditional rule can pay for itself but never for other rules,
##                     otherwise "WHEN never -> mana cost +100%" would be free points.
##   loop rule         like a conditional rule, with the loop's own cost added to the sum
##                     (see ProgramLoop). Its effects only apply to the repeats.
## A program is valid when total cost <= the gem's point_budget and every knob stays inside its
## min/max steps (counting all conditional rules as active at once).
## Using few blocks earns an EfficiencyTier bonus.

const EPSILON := 0.001

@export var rules: Array[ProgramRule] = []


func has_rules() -> bool:
	return not rules.is_empty()


func action_count() -> int:
	var n := 0
	for r in rules:
		n += r.action_count()
	return n


func validate(limits: SkillProgramLimits) -> ProgramValidation:
	var v := ProgramValidation.new()
	if limits == null:
		v.add_error("This skill can't be programmed.")
		return v
	v.point_budget = limits.point_budget
	v.max_actions = limits.max_actions
	v.actions_used = action_count()

	if rules.size() > limits.max_rules:
		v.add_error("Too many rules (%d / %d)." % [rules.size(), limits.max_rules],
			"delete a rule, or move its lines into another rule with the same conditions")
	if v.actions_used > limits.max_actions:
		var extra := v.actions_used - limits.max_actions
		v.add_error("Too many blocks (%d / %d)." % [v.actions_used, limits.max_actions],
			"remove %d block%s: every condition, knob line and loop counts as one" % [extra, "" if extra == 1 else "s"])

	var always_steps := {}      # knob id -> steps from ALWAYS rules
	var cond_up := {}           # knob id -> sum of positive steps in conditional rules
	var cond_down := {}         # knob id -> sum of negative steps in conditional rules
	var raising := {}           # knob id -> [[rule, effect], ...] lines that push it up
	var lowering := {}          # knob id -> [[rule, effect], ...] lines that push it down
	var rule_cost := {}         # ProgramRule -> points it adds, to name the priciest when over budget

	var has_loop := false       # repeat-only rules (target_alive...) need a loop somewhere
	for r in rules:
		has_loop = has_loop or r.loop != null
	var per_owner := {}         # owner -> rules seen so far, for "Cleave rule 2" style labels
	for i in rules.size():
		var rule := rules[i]
		per_owner[rule.owner] = per_owner.get(rule.owner, 0) + 1
		var label := "%s rule %d" % [_owner_name(rule.owner), per_owner[rule.owner]]
		if rule.owner != "" and not (rule.owner in limits.knob_owner.values()):
			v.add_issue("%s: that support isn't socketed in this skill." % label,
				"its support gem isn't socketed in this skill",
				"socket the gem again, or delete this rule", rule)
			continue
		if rule.effects.is_empty() and rule.loop == null:
			v.add_issue("%s has no effects." % label, "this rule does nothing yet",
				"drag a knob from SNIPPETS under it, or delete the rule", rule)
			continue
		var repeated := rule.repeated_condition()
		if repeated != "":
			v.add_issue("%s: %s() is used more than once. Each condition can appear once per rule." % [label, repeated],
				"%s() is already used in this rule" % repeated,
				"delete this line: each condition can appear once per rule", rule, _second_use(rule))
			continue
		var missing: ProgramCondition = null
		for c in rule.conditions:
			if c.required_support() != "" and not limits.support_ids.has(c.required_support()):
				missing = c
		if missing != null:
			var gem := _owner_name(missing.required_support())
			v.add_issue("%s: %s needs the %s gem in this skill." % [label, "that block", gem],
				"needs the %s gem in this skill" % gem,
				"socket %s, or delete this line" % gem, rule, missing)
			continue
		if rule.only_on_repeats() and not has_loop:
			var needs: ProgramCondition = null
			for c in rule.conditions:
				if c.needs_loop():
					needs = c
					break
			var fn := needs.palette_name().to_lower().replace(" ", "_")
			v.add_issue("%s: %s() only changes loop repeats, and this skill has no loop." % [label, fn],
				"%s() only changes loop repeats, and this skill has no loop" % fn,
				"add a for or while loop to this skill, or use a condition that checks the cast itself (target_life_below() checks each hit)",
				rule, needs)
			continue
		var raw_cost := 0.0
		if rule.loop != null:
			var loop_problem := _check_loop(rule, limits)
			if not loop_problem.is_empty():
				v.add_issue("%s: %s" % [label, loop_problem[0]], String(loop_problem[0]).trim_suffix("."),
					loop_problem[1], rule, rule.loop)
				continue
			raw_cost += rule.loop.cost(limits.loop_cost_mult())
		for e in rule.effects:
			var knob := limits.get_knob(e.knob)
			if knob == null:
				v.add_issue("%s: %s can't be changed on this skill." % [label, e.knob],
					"%s can't be changed on this skill" % e.knob, "delete this line", rule, e)
				continue
			if limits.owner_of(e.knob) != rule.owner:
				v.add_issue("%s: %s belongs to another gem." % [label, knob.display_name],
					"%s belongs to the %s file" % [e.knob, _owner_name(limits.owner_of(e.knob))],
					"delete it here and add it in that gem's file", rule, e)
				continue
			if e.steps == 0:
				continue
			if not rule.is_baked():
				if knob.kind == SkillKnob.Kind.STAT and not (rule.scope() == ProgramCondition.Scope.HIT \
						and limits.per_hit_attack_speed(knob)):
					var no_loop := " without a loop" if rule.is_always() else ""
					v.add_issue("%s: %s can only be changed in an ALWAYS rule%s." % [label, knob.display_name, no_loop],
						"%s only works in an always: rule%s" % [e.knob, no_loop],
						"move this line into an always: rule%s" % (" that has no loop" if no_loop != "" else ""), rule, e)
					continue
				if knob.always_only:
					v.add_issue("%s: %s can only be changed in an ALWAYS rule." % [label, knob.display_name],
						"%s only works in an always: rule (it's read before the cast starts)" % e.knob,
						"move this line into an always: rule without a loop", rule, e)
					continue
				if knob.first_cast_only and (rule.loop != null or rule.only_on_repeats()):
					v.add_issue("%s: %s does nothing on loop repeats." % [label, knob.display_name],
						"%s does nothing on loop repeats: its gem only acts on the original cast" % e.knob,
						"move this line to a rule without a loop (and without target_alive, stack_overflow or loop_index)", rule, e)
					continue
				if rule.scope() == ProgramCondition.Scope.HIT and knob.kind != SkillKnob.Kind.DAMAGE \
						and not limits.per_hit_any_knob():
					v.add_issue("%s: per-hit conditions can only change damage." % label,
						"per-hit rules can only change damage",
						"move this line to an always: rule, or to a rule without per-hit conditions", rule, e)
					continue
			raw_cost += knob.cost_for(e.steps)
			var pushes := raising if e.steps > 0 else lowering
			if not pushes.has(e.knob):
				pushes[e.knob] = []
			pushes[e.knob].append([rule, e])
			if rule.is_baked():
				always_steps[e.knob] = always_steps.get(e.knob, 0) + e.steps
			elif e.steps > 0:
				cond_up[e.knob] = cond_up.get(e.knob, 0) + e.steps
			else:
				cond_down[e.knob] = cond_down.get(e.knob, 0) + e.steps
		if rule.is_baked():
			var rule_points := 0.0
			for e in rule.effects:
				var k := limits.get_knob(e.knob)
				if k == null or limits.owner_of(e.knob) != rule.owner:
					continue
				var c := k.cost_for(e.steps)
				if c > 0.0:
					c *= limits.buff_cost_mult()           # Enchanter: buffs cost less
					v.buff_points += c
				else:
					v.drawback_points -= c
				v.points_used += c
				rule_points += c
			rule_cost[rule] = rule_points
		else:
			var net := maxf(raw_cost, 0.0) * rule.cost_multiplier() * limits.rule_cost_mult(rule) \
					* limits.buff_cost_mult()
			v.points_used += net
			v.buff_points += net
			rule_cost[rule] = net

	# Knob limits, assuming every conditional rule could be active at the same time
	for knob in limits.knobs:
		var base: int = always_steps.get(knob.id, 0)
		var lo: int = base + cond_down.get(knob.id, 0)
		var hi: int = base + cond_up.get(knob.id, 0)
		v.knob_ranges[knob.id] = [lo, hi]
		if hi > knob.max_steps:
			_knob_issue(v, "%s can go up at most %d steps (this program: %d)." % [knob.display_name, knob.max_steps, hi],
				"%s goes up %d steps in total, max %d" % [knob.id, hi, knob.max_steps],
				"lower one of the %s lines (rules with conditions count as if all were active at once)" % knob.id,
				raising.get(knob.id, []))
		if lo < knob.min_steps:
			_knob_issue(v, "%s can go down at most %d steps (this program: %d)." % [knob.display_name, -knob.min_steps, -lo],
				"%s goes down %d steps in total, max %d" % [knob.id, -lo, -knob.min_steps],
				"raise one of the %s lines (rules with conditions count as if all were active at once)" % knob.id,
				lowering.get(knob.id, []))

	# WHEN charge >= N can't ask for more charge than the skill can hold, or it never fires
	var cap_knob := limits.get_knob(VariableStoreSupport.CAPACITY_KNOB)
	if cap_knob != null:
		var capacity := VariableStoreSupport.capacity_with(int(always_steps.get(cap_knob.id, 0)), cap_knob)
		var seen := {}
		for rule in rules:
			seen[rule.owner] = seen.get(rule.owner, 0) + 1
			for c in rule.conditions:
				var charge := c as ChargeAtLeastCondition
				if charge == null or charge.n <= capacity:
					continue
				var label := "%s rule %d" % [_owner_name(rule.owner), seen[rule.owner]]
				v.add_issue("%s: charge >= %d never fires, this skill holds at most %d charge." % [label, charge.n, capacity],
					"never fires: this skill holds at most %d charge" % capacity,
					"lower the number to %d or less, or raise Charge capacity in an always: rule (+%d per step)" % [
						capacity, int(cap_knob.step)], rule, charge)

	if v.points_used > limits.point_budget + EPSILON:
		var over_by := v.points_used - limits.point_budget
		v.add_error("Over budget by %.1f points: add drawbacks or remove buffs." % over_by,
			"lower a buff (+ line), or add a drawback (- line) that pays at least %.1f" % over_by)
		var priciest: ProgramRule = null
		for r in rule_cost:
			if rule_cost[r] > EPSILON and (priciest == null or rule_cost[r] > rule_cost[priciest]):
				priciest = r
		if priciest != null:
			v.add_note("costs the most: %.1f points" % rule_cost[priciest],
				"trimming this rule is the quickest way back under budget", priciest)

	if has_rules():
		v.tier = limits.tier_for(v.actions_used)
		for t in limits.tiers:           # smallest max_actions first
			if t == v.tier:
				break
			v.next_tier = t              # ends as the closest better tier
		if v.next_tier != null:
			v.actions_to_next_tier = v.actions_used - v.next_tier.max_actions
	return v


## One error for a knob pushed past its limit, marked on every line that pushes it that way.
static func _knob_issue(v: ProgramValidation, full: String, text: String, hint: String, lines: Array) -> void:
	if lines.is_empty():
		v.add_error(full, hint)
		return
	for i in lines.size():
		v.add_issue(full, text, hint, lines[i][0], lines[i][1], i == 0)


## The second condition of a type already used earlier in the rule (the one to delete).
static func _second_use(rule: ProgramRule) -> ProgramCondition:
	var seen := {}
	for c in rule.conditions:
		if seen.has(c.type_id()):
			return c
		seen[c.type_id()] = true
	return null


## [] when the rule's loop is fine, otherwise [what is wrong, how to fix it].
static func _check_loop(rule: ProgramRule, limits: SkillProgramLimits) -> Array:
	var cap := limits.loop_cap()
	if rule.scope() == ProgramCondition.Scope.HIT:
		return ["loops can't use per-hit conditions.",
			"move the loop to a rule without per-hit conditions"]
	if rule.loop.count < 1 or rule.loop.count > cap:
		return ["a loop can repeat 1 to %d times." % cap,
			"click the repeat number (right-click lowers it) to bring it to %d or less" % cap]
	if rule.loop.mode == ProgramLoop.Mode.WHILE:
		if rule.conditions.is_empty():
			return ["a while loop needs a condition (use a for loop in always:).",
				"drag a condition onto this rule, or use a for loop instead"]
		for c in rule.conditions:
			if c.changes_during_cast():
				return []
		return ["%s never changes mid-cast, so the while would always run to its max: use a for loop." \
				% rule.conditions[0].palette_name().to_lower(),
			"use a for loop, or add a condition that can change mid-cast"]
	return []


## Rules owned by one gem ("" = the skill), in order.
func rules_of(owner_id: String) -> Array[ProgramRule]:
	var out: Array[ProgramRule] = []
	for r in rules:
		if r.owner == owner_id:
			out.append(r)
	return out


## Removes rules whose support gem is no longer socketed. Returns true if anything was removed.
func prune_owners(socketed_support_ids: Array) -> bool:
	var before := rules.size()
	rules.assign(rules.filter(func(r: ProgramRule) -> bool:
		return r.owner == "" or r.owner in socketed_support_ids))
	return rules.size() != before


func duplicate_program() -> SkillProgram:
	return SkillProgram.from_dict(to_dict())


static func _owner_name(owner_id: String) -> String:
	if owner_id == "":
		return "Skill"
	var def: SupportGemDefinition = SkillGemRegistry.get_support_gem(owner_id)
	return def.display_name.trim_suffix(" Support") if def != null else owner_id


## Pseudo-code lines for tooltips and debugging.
func describe(limits: SkillProgramLimits) -> PackedStringArray:
	var lines := PackedStringArray()
	for r in rules:
		lines.append(r.describe(limits))
	return lines


func to_dict() -> Dictionary:
	var out: Array = []
	for r in rules:
		out.append(r.to_dict())
	return {"rules": out}


static func from_dict(d: Dictionary) -> SkillProgram:
	var p := SkillProgram.new()
	for rd in d.get("rules", []):
		p.rules.append(ProgramRule.from_dict(rd))
	return p
