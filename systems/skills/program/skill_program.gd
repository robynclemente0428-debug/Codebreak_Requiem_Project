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
## The script's Registry (ScriptRegisters): a set of enemies, instance id -> true. It lives
## here, so rebuilding the skill keeps it and each script set has its own. Never saved. Applying a
## script makes a new copy of it, which starts empty.
var registers := {}
## When the owner last landed a hit (-1 = not yet), and the area its registry belongs to.
var last_active_msec := -1
var area_id := 0

## ---- Routines (ProgramRoutine, the Engineer rank) ----
## A script with  call  lines runs as its resolved copy (resolve): every call replaced by its
## routine's lines. On that copy, `source` is the script it was made from: the registry and its
## fight clock stay on the source (state()), so rebuilding never loses them.
var source: SkillProgram
## On a resolved copy: the source's block count, where a call is one block (action_count).
var _actions_override := -1
## On a resolved copy: copy object -> what the editor shows for it (the source's rule, if block,
## or the call line a routine's line came from), so validate() marks the right lines.
var _origin := {}
## On a resolved copy: problems with the calls themselves, [rule, call line, full, text, fix].
var _call_problems: Array = []


func has_rules() -> bool:
	return not rules.is_empty()


## Where the registry and its fight clock live: the source of a resolved copy, else this script.
func state() -> SkillProgram:
	return source if source != null else self


## True when a line anywhere in the script is a  call  (a routine).
func has_calls() -> bool:
	for r in rules:
		for e in r.effects:
			if e.is_call():
				return true
		for b in r.branches:
			for e in b.effects:
				if e.is_call():
					return true
	return false


## The routine indices this script calls, each once.
func called_routines() -> Array:
	var out: Array = []
	for r in rules:
		for list in [r.effects] + r.branches.map(func(b: ProgramBranch) -> Array: return b.effects):
			for e in list:
				if e.is_call() and not (e.op in out):
					out.append(e.op)
	return out


## A copy of this script with every  call  replaced by its routine's lines (`routines`:
## SkillComponent.routines), the way pricing, validation and the skill itself read it. The
## routine's lines go where the call is: a call among a rule's lines adds its lines and its if
## blocks to that rule; a call inside an if adds its lines to that if. Lines and conditions taken
## from a routine are copies (a routine called twice is two sets of lines). Problems with a call
## (no such routine, empty, too big, an if inside an if, above the player's rank) are kept in
## _call_problems for validate(). Rules that call a routine carry meta "calls" (the indices), as
## do if blocks: ProgramSupport reports each call that runs ("routine_called").
func resolve(routines: Array, limits: SkillProgramLimits = null) -> SkillProgram:
	var out := SkillProgram.new()
	out.source = self
	out.registers = registers
	out._actions_override = action_count()
	for r in rules:
		var nr := ProgramRule.new()
		nr.owner = r.owner
		nr.conditions.assign(r.conditions)
		nr.loop = r.loop
		out._origin[nr] = r
		var failed := out._call_problems.size()
		var calls := out._expand(r.effects, nr.effects, r, routines, limits, false)
		if out._call_problems.size() > failed:
			nr.set_meta(&"call_failed", true)            # its call is the error, not "does nothing"
		for b in r.branches:
			var nb := ProgramBranch.new()
			nb.conditions.assign(b.conditions)
			out._origin[nb] = b
			failed = out._call_problems.size()
			var inner := out._expand(b.effects, nb.effects, r, routines, limits, true)
			if out._call_problems.size() > failed:
				nb.set_meta(&"call_failed", true)
			if not inner.is_empty():
				nb.set_meta(&"calls", inner.map(func(c: Array) -> int: return (c[0] as ProgramEffect).op))
			nr.branches.append(nb)
		for c in calls:                                  # a called routine's own if blocks
			var call: ProgramEffect = c[0]
			var routine: ProgramRoutine = c[1]
			for rb in routine.body.branches:
				var nb := ProgramBranch.new()
				for cond in rb.conditions:
					var cc := (cond as ProgramCondition).duplicate() as ProgramCondition
					out._origin[cc] = call
					nb.conditions.append(cc)
				for e in rb.effects:
					var ec := (e as ProgramEffect).duplicate() as ProgramEffect
					out._origin[ec] = call
					nb.effects.append(ec)
				out._origin[nb] = call
				nr.branches.append(nb)
		if not calls.is_empty():
			nr.set_meta(&"calls", calls.map(func(c: Array) -> int: return (c[0] as ProgramEffect).op))
		out.rules.append(nr)
	return out


## Copies `lines` into `into`, each call replaced by its routine's lines. Returns the calls that
## were expanded, [[call line, routine], ...]. `in_if`: these lines are inside an if block.
func _expand(lines: Array, into: Array, rule: ProgramRule, routines: Array, limits: SkillProgramLimits,
		in_if: bool) -> Array:
	var calls: Array = []
	for e in lines:
		var line := e as ProgramEffect
		if not line.is_call():
			into.append(line)
			continue
		var routine: ProgramRoutine = routines[line.op] if line.op >= 0 and line.op < routines.size() else null
		var problem: Array = []
		if limits != null and not limits.allows("call"):
			problem = ["routines aren't available at your rank.", "routines aren't available at your rank (Engineer)",
				"delete this line"]
		elif routine == null:
			problem = ["it calls a routine that doesn't exist.", "there's no routine %d" % (line.op + 1),
				"pick a routine (click its name) or delete this line"]
		elif not routine.problem().is_empty():
			problem = routine.problem()
		elif in_if and routine.has_if():
			problem = ["%s() has an if, and it's called inside an if." % routine.routine_name,
				"%s() has an if: it can't be called inside an if" % routine.routine_name,
				"call it from the rule's own lines, or take the if out of %s()" % routine.routine_name]
		if not problem.is_empty():
			_call_problems.append([rule, line, problem[0], problem[1], problem[2]])
			continue
		for re in routine.body.effects:
			var copy := (re as ProgramEffect).duplicate() as ProgramEffect
			_origin[copy] = line
			into.append(copy)
		calls.append([line, routine])
	return calls


## A problem found on the resolved copy, moved onto what the editor shows (the source's rule, its
## if block, or the call line a routine's line came from).
func _remap(v: ProgramValidation) -> void:
	for issue in v.issues:
		var r: Variant = issue["rule"]
		var p: Variant = issue["part"]
		if r != null and _origin.has(r):
			issue["rule"] = _origin[r]
		if p != null and _origin.has(p):
			issue["part"] = _origin[p]


## Every rule, then each "if" block as the rule it means (ProgramRule.flat): what pricing,
## validation and the registry checks go through. Editing and saving use `rules`.
func flat_rules() -> Array[ProgramRule]:
	var out: Array[ProgramRule] = []
	for r in rules:
		out.append_array(r.flat())
	return out


## Blocks, a call counting as one (on a resolved copy: its source's count).
func action_count() -> int:
	if _actions_override >= 0:
		return _actions_override
	var n := 0
	for r in rules:
		n += r.action_count()
	return n


## Checks the script against `limits`. A script with calls is checked as its resolved copy (its
## routines' lines priced and checked on this skill), with a call as one block, and every problem
## is put back on the line the player wrote (the call, for a routine's lines).
func validate(limits: SkillProgramLimits) -> ProgramValidation:
	if limits != null and has_calls():
		var resolved := resolve(limits.routines, limits)
		var v := resolved._validate_plain(limits)
		resolved._remap(v)
		for p in resolved._call_problems:
			v.add_issue("%s rule: %s" % [_owner_name((p[0] as ProgramRule).owner), p[2]], p[3], p[4], p[0], p[1])
		return v
	return _validate_plain(limits)


func _validate_plain(limits: SkillProgramLimits) -> ProgramValidation:
	tag_registry_reads()
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
	var labels := {}            # ProgramRule -> its label, so an "if" block can name its rule
	var all := flat_rules()
	for i in all.size():
		var rule := all[i]
		var label := ""
		if rule.is_branch():
			label = "%s, if %d" % [labels.get(rule.parent, "Rule"), rule.branch_index + 1]
		else:
			per_owner[rule.owner] = per_owner.get(rule.owner, 0) + 1
			label = "%s rule %d" % [_owner_name(rule.owner), per_owner[rule.owner]]
			labels[rule] = label
		if rule.owner != "" and not (rule.owner in limits.knob_owner.values()):
			if not rule.is_branch():
				v.add_issue("%s: that support isn't socketed in this skill." % label,
					"its support gem isn't socketed in this skill",
					"socket the gem again, or delete this rule", rule)
			continue
		if not rule.is_branch() and not rule.branches.is_empty():
			if not limits.allows("if"):
				v.add_issue("%s: if blocks aren't available at your rank." % label,
					"if blocks aren't available at your rank (Strategist)", "delete the if block", rule, rule.branches[0])
			elif rule.loop != null:
				v.add_issue("%s: a rule with a loop can't have if blocks." % label,
					"a rule with a loop can't have if blocks",
					"move the if block's lines to a rule without a loop, or delete the loop", rule, rule.branches[0])
		if rule.is_branch():
			if rule.parent.loop != null or not limits.allows("if"):
				continue                               # reported on the rule above
			if rule.own_conditions().is_empty():
				v.add_issue("%s has no condition." % label, "this if has no condition yet",
					"drag a condition onto this if line (target in registry, target_life_below...)", rule)
				continue
			if rule.effects.is_empty():
				if not rule.branch().has_meta(&"call_failed"):     # a failed call says so itself
					v.add_issue("%s does nothing." % label, "this if does nothing yet",
						"drag a knob from SNIPPETS under it, or delete the if", rule)
				continue
		elif rule.effects.is_empty() and rule.loop == null and rule.branches.is_empty():
			if rule.has_meta(&"call_failed"):
				continue                                       # its call's own error explains it
			v.add_issue("%s has no effects." % label, "this rule does nothing yet",
				"drag a knob from SNIPPETS under it, or delete the rule", rule)
			continue
		var repeated := rule.repeated_condition()
		if repeated != "" and not (rule.is_branch() and rule.parent.repeated_condition() == repeated):
			v.add_issue("%s: %s() is used more than once. Each condition can appear once per rule." % [label, repeated],
				"%s() is already used in this rule" % repeated,
				"delete this line: each condition can appear once per rule", rule, _second_use(rule))
			continue
		var missing: ProgramCondition = null
		for c in rule.own_conditions():
			if c.required_support() != "" and not limits.support_ids.has(c.required_support()):
				missing = c
		if missing != null:
			var gem := _owner_name(missing.required_support())
			v.add_issue("%s: %s needs the %s gem in this skill." % [label, "that block", gem],
				"needs the %s gem in this skill" % gem,
				"socket %s, or delete this line" % gem, rule, missing)
			continue
		# Blocks above the player's rank (Ranks.LOCKED_BLOCKS): only an old save or library
		# script can still hold one, since the editor doesn't offer them.
		var locked: ProgramCondition = null
		for c in rule.own_conditions():
			if not limits.allows("cond:" + c.type_id()):
				locked = c
		if locked != null:
			var lfn := locked.palette_name().to_lower().replace(" ", "_")
			v.add_issue("%s: %s() isn't available at your rank." % [label, lfn],
				"%s() isn't available at your rank" % lfn, "delete this line", rule, locked)
			continue
		if rule.loop != null and not limits.allows("loop"):
			v.add_issue("%s: loops aren't available at your rank." % label,
				"loops aren't available at your rank", "delete the loop", rule, rule.loop)
			continue
		if rule.only_on_repeats() and not has_loop and not (rule.is_branch() and rule.parent.only_on_repeats()):
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
			if e.ramps() and not ScriptRegisters.can_grow(knob):
				var why := "it's read before the cast starts" if knob.always_only or knob.kind == SkillKnob.Kind.STAT \
						else "it can't change gradually"
				v.add_issue("%s: %s can't grow with the registry." % [label, knob.display_name],
					"%s can't grow with the registry: %s" % [e.knob, why],
					"click its %s until the line is a plain value" % e.ramp_text(), rule, e)
				continue
			if e.ramps() and knob.cost_for(e.steps) < 0.0:      # points back for a drawback that starts at nothing
				v.add_issue("%s: only a buff can grow with the registry." % label,
					"only a buff can grow with the registry, and this pays points back",
					"raise its value above 0, or click its %s until the line is a plain value" % e.ramp_text(), rule, e)
				continue
			if e.ramps() and (e.steps > knob.max_steps or _grows_twice(e) or growth_room(e, knob) <= 0):
				var problem := "%s grows too fast: the most is one step's worth per %d enemies in the registry" % [e.knob, ScriptRegisters.RAMP_PER_STEP]
				var cure := "lower its value"
				if _grows_twice(e):
					problem = "only one line per knob can grow, and %s already has one" % e.knob
					cure = "delete this line, or click its %s until the line is a plain value" % e.ramp_text()
				elif growth_room(e, knob) <= 0:
					problem = "%s has no room left to grow: other lines reach its limit" % e.knob
					cure = "lower the other %s lines" % e.knob
				v.add_issue("%s: %s." % [label, problem], problem, cure, rule, e)
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
						and knob.kind != SkillKnob.Kind.VARIABLE and not SkillProgramLimits.per_hit_knob(knob) \
						and not limits.per_hit_any_knob():
					v.add_issue("%s: per-hit conditions can't change %s." % [label, knob.display_name],
						"per-hit rules can change damage, leech, barrier, guard and support effects that happen on a hit or kill (explosions, breakpoints, tremors, charge, error damage, forks): %s is decided before the skill hits" % e.knob,
						"move this line to an always: rule, or to a rule without per-hit conditions", rule, e)
					continue
			raw_cost += line_cost(knob, e)
			var pushes := raising if e.steps > 0 else lowering
			if not pushes.has(e.knob):
				pushes[e.knob] = []
			pushes[e.knob].append([rule, e])
			if e.ramps():
				pass                                   # it only uses the room the flat lines leave
			elif rule.is_baked():
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
				var c := line_cost(k, e)
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
		for rule in flat_rules():
			seen[rule.owner] = seen.get(rule.owner, 0) + 1
			for c in rule.own_conditions():
				var charge := c as ChargeAtLeastCondition
				if charge == null or charge.n <= capacity:
					continue
				var label := "%s rule %d" % [_owner_name(rule.owner), seen[rule.owner]]
				v.add_issue("%s: charge >= %d never fires, this skill holds at most %d charge." % [label, charge.n, capacity],
					"never fires: this skill holds at most %d charge" % capacity,
					"lower the number to %d or less, or raise Charge capacity in an always: rule (+%d per step)" % [
						capacity, int(cap_knob.step)], rule, charge)

	_check_registers(v)

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


## Scripts that can't be what the player meant: reading the registry when nothing ever adds to it
## (it would stay empty), and a size comparison no size can change (>= 0) isn't a condition at all.
func _check_registers(v: ProgramValidation) -> void:
	var seen := {}
	var adds := _adds_to_registry()
	var fix := "add registry.add(target) to a rule: always: adds every enemy the skill hits"
	for rule in flat_rules():
		seen[rule.owner] = seen.get(rule.owner, 0) + 1
		var label := "%s rule %d" % [_owner_name(rule.owner), seen[rule.owner]]
		for c in rule.own_conditions():
			var read := c as VarCondition
			if read == null:
				continue
			var constant := read.constant_answer()
			if constant != "":
				var text := "registry.size %s %d is %s true" % [read.op_text(), read.value, constant]
				v.add_issue("%s: %s." % [label, text], text, "change the operator or the size", rule, c)
			elif not adds:
				v.add_issue("%s: nothing ever adds to the registry, so it stays empty." % label,
					"nothing ever adds to the registry, so it stays empty", fix, rule, c)
		for e in rule.effects:
			if e.ramps() and e.steps != 0 and not adds:
				v.add_issue("%s: nothing ever adds to the registry, so this buff stays at nothing." % label,
					"nothing ever adds to the registry, so this buff stays at nothing", fix, rule, e)


## Tells every "target in registry" check whether this script spends marks (has a
## registry.remove), which sets its discount (VarCondition.cost_multiplier). Called by validate,
## so pricing, the editor and the applied skill all agree.
func tag_registry_reads() -> void:
	var spends := false
	for rule in flat_rules():
		for e in rule.effects:
			spends = spends or (ScriptRegisters.is_write(e.knob) and e.write_op() == "remove")
	for rule in flat_rules():
		for c in rule.conditions:
			if c is VarCondition:
				(c as VarCondition).spent = spends


## True when a line adds enemies to the registry.
func _adds_to_registry() -> bool:
	for rule in flat_rules():
		for e in rule.effects:
			if ScriptRegisters.raises(e):
				return true
	return false


## True when this script keeps a registry: something adds enemies to it, and a rule reads it (target
## in registry, registry.size) or a buff grows with its size. What the Strategist exam asks for.
## Adds only ever happen as hits land, so they are always about the fight.
func keeps_a_count() -> bool:
	if not _adds_to_registry():
		return false
	for rule in flat_rules():
		for c in rule.conditions:
			if c is VarCondition:
				return true
		for e in rule.effects:
			if e.ramps():
				return true
	return false


## What a line costs before any rule discount. A growing buff is priced on the room it can fill, and
## is cheaper because the registry only fills as the skill hits enemies.
## Buff steps get pricier the more a knob has (SkillKnob.STEP_COST_GROWTH), counting every buff
## line on it in the script, so splitting a buff over lines doesn't dodge it. Each line pays the
## average step price for its share, so the order of lines doesn't matter. Drawbacks stay flat.
func line_cost(knob: SkillKnob, e: ProgramEffect) -> float:
	if e.ramps() and e.steps > 0:
		var room := maxi(growth_room(e, knob), 0)
		var full := room * _avg_buff_step_cost(knob)
		return full * ScriptRegisters.ramp_cost_share(e.steps, room)
	if not knob.is_buff(e.steps):
		return knob.cost_for(e.steps)
	return absi(e.steps) * _avg_buff_step_cost(knob)


## Every buff step this script puts on `knob`: flat buff lines, plus the room each growing line fills.
func buff_steps_on(knob: SkillKnob) -> int:
	var n := 0
	for rule in flat_rules():
		for e in rule.effects:
			if e.knob != knob.id or ScriptRegisters.is_write(e.knob):
				continue
			if e.ramps():
				if e.steps > 0:
					n += maxi(growth_room(e, knob), 0)
			elif knob.is_buff(e.steps):
				n += absi(e.steps)
	return n


func _avg_buff_step_cost(knob: SkillKnob) -> float:
	var n := buff_steps_on(knob)
	return knob.buff_cost(n) / n if n > 0 else knob.first_step_cost()


## How many steps a growing buff can reach: the knob's limit, less this script's flat buffs on it.
## They all count, active or not, the same way the knob's limit counts them.
func growth_room(e: ProgramEffect, knob: SkillKnob) -> int:
	var room := knob.max_steps
	for rule in flat_rules():
		for other in rule.effects:
			if other.knob == e.knob and not other.ramps() and other.steps > 0:
				room -= other.steps
	return room


func _grows_twice(e: ProgramEffect) -> bool:
	for rule in flat_rules():
		for other in rule.effects:
			if other == e:
				return false
			if other.knob == e.knob and other.ramps():
				return true
	return false


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
		if seen.has(c.type_id()) and not c.allows_repeats():
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
