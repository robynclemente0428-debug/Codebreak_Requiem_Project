class_name ProgramSupport
extends SupportBehavior
## Runs the conditional rules of a player's SkillProgram during each cast.
## (ALWAYS rules don't need this: SkillInstance bakes them in when the skill is rebuilt.)
## SkillInstance adds one automatically when the socket has a valid program.

const CAST_NUMBER_KEY := "program_cast_number"
## What per-repeat rules (WHEN loop == N, ...) added to the original cast, so repeats can take it back off.
const REPEAT_UNDO_KEY := "program_repeat_undo"
## The ProgramLoopRunner running this cast's loops (only on casts that loop).
const LOOP_KEY := "program_loop"
## The condition ids of every WHEN rule that fired for this cast ("enemies_nearby", ...), so
## something it hits can tell which rules answered (ChallengeLock). See fired_conditions().
const FIRED_KEY := "program_fired"
## registry.add / remove from this cast's rules, waiting for its hits (_write_hit_entries).
const HIT_WRITES_KEY := "registry_hit_writes"
## The rules (instance ids) whose WHEN fired for this cast, so their "if" blocks can tell
## (rule_fired). Repeats, copies and follow-up casts (SkillCast.spawn_child) keep it.
const RULES_FIRED_KEY := "program_rules_fired"

var program: SkillProgram
var limits: SkillProgramLimits
## The program's rules with each "if" block as the rule it means (SkillProgram.flat_rules),
## rebuilt for every cast.
var _flat: Array[ProgramRule] = []
var _cast_count := 0
## The script's memory, the Registry (ScriptRegisters): a set of enemies, instance id -> true.
## It lives on the program, so it outlasts this support when the skill is rebuilt.
var registers: Dictionary:
	get:
		return program.state().registers           # a resolved copy (routines): its source's
var _caster: Node3D
## Loops still running (kept here so they live until they finish).
var _runners: Array[ProgramLoopRunner] = []
## Assassin: attack speed from per-hit rules, for the skill's next cast (see speed_mult).
const HIT_SPEED_WINDOW := 2.5     # seconds the bonus waits for the next attack
var _hit_speed := 0.0
var _hit_speed_msec := 0
var _law_hit_msec := -1                    # REGISTRY FORGETS ON HIT: the last hit already forgotten

const NullLawsRef := preload("res://systems/world/null_laws.gd")   # Act IV's Null Laws


func _init(p_program: SkillProgram = null, p_limits: SkillProgramLimits = null) -> void:
	program = p_program
	limits = p_limits


## CAST rules: checked once, after the windup, before the skill picks its targets.
## Loop rules don't change the cast itself: FOR loops whose conditions are true, and every
## WHILE loop, are handed to a ProgramLoopRunner that repeats the skill after it lands.
func before_release(cast: SkillCast) -> void:
	if cast.extra.get("hologram", false) or cast.depth > 0:
		return                                   # Multicast copy / repeat: rules already applied
	_caster = cast.caster
	_clear_stale_registers()
	# This cast started with any per-hit attack speed bonus (its cooldown and animation were set
	# before now): it's used up. Hits from this cast can earn the next one.
	_hit_speed = 0.0
	# With Finishing Blow socketed, "every Nth cast" counts the same combo swings it does (a pause
	# starts both over), so every_nth_cast(3) lands exactly on a 3rd-swing finisher.
	if _counts_swings(cast.skill):
		cast.extra[CAST_NUMBER_KEY] = cast.skill.count_swing(cast)
	else:
		_cast_count += 1
		cast.extra[CAST_NUMBER_KEY] = _cast_count
	var undo := {"damage": 1.0, "flags": {}}
	var tickets: Array[ProgramRule] = []
	var whiles: Array[ProgramRule] = []
	var late_fors: Array[ProgramRule] = []
	_flat = program.flat_rules()
	for rule in program.rules:                     # always: rules that call a routine run every cast
		if rule.is_always() and rule.loop == null:
			_report_calls(rule, cast)
	for rule in _flat:
		if rule.scope() != ProgramCondition.Scope.CAST:
			continue
		if rule.loop != null:
			if rule.loop.mode == ProgramLoop.Mode.WHILE:
				whiles.append(rule)              # checked after the cast lands
			elif _is_repeat_rule(rule):
				late_fors.append(rule)           # target_alive & co. only mean something once it lands
			elif rule.is_always() or rule.all_true(cast, null):
				if not rule.is_always():
					announce(cast, rule)
				for i in NullLawsRef.loop_count(rule.loop, cast.caster):   # LOOPS RUN ONCE MORE
					tickets.append(rule)
			continue
		if rule.is_always():
			_write_registers(rule, cast)         # the rest of an always: rule is baked into the skill
			_apply_effects(cast, rule, {}, true)
			continue
		if not rule.all_true(cast, null):
			continue
		_fire_cast_rule(cast, rule, undo if _is_repeat_rule(rule) else {})
	cast.extra[REPEAT_UNDO_KEY] = undo
	if tickets.is_empty() and whiles.is_empty() and late_fors.is_empty():
		return
	var runner := ProgramLoopRunner.new(self, cast, limits.loop_cap(), tickets, whiles, late_fors)
	_runners.append(runner)
	runner.start()


## A repeat starts from the original cast's numbers. The per-repeat rules that fired for the
## original (loop 0) are taken back off, then the per-repeat rules for this repeat apply, then
## the body of the loop that runs it. Other WHEN rules are not checked again, so charges aren't
## spent twice and every-Nth counts hold.
func apply_repeat_rules(child: SkillCast, loop_rule: ProgramRule = null) -> void:
	var undo: Dictionary = child.extra.get(REPEAT_UNDO_KEY, {})
	if not undo.is_empty():
		child.damage_mult /= maxf(float(undo["damage"]), 0.0001)
		for k in undo["flags"]:
			child.flag_bonus[k] = child.flag_bonus.get(k, 0.0) - float(undo["flags"][k])
	child.extra[REPEAT_UNDO_KEY] = {}
	for rule in _rules():
		if rule.loop != null or rule.is_always() or rule.scope() != ProgramCondition.Scope.CAST \
				or not _is_repeat_rule(rule):
			continue
		if rule.all_true(child, null):
			_fire_cast_rule(child, rule, {})
	if loop_rule != null:
		_apply_effects(child, loop_rule, {})


## Finishing Blow and Overclock count the skill's combo swings / shots in a row: every_nth_cast
## counts the same ones so they line up.
static func _counts_swings(skill: SkillInstance) -> bool:
	for s in skill.support_behaviors:
		if s is FinishingBlowSupport or s is OverclockSupport:
			return true
	return false


## Fork (Shoot): a forked bullet's cast. It starts from the cast it split off (whose WHEN rules
## already applied), then the rules about forks (WHEN forked ...) apply on top.
func apply_fork_rules(child: SkillCast) -> void:
	for rule in _rules():
		if rule.loop != null or rule.is_always() or rule.scope() != ProgramCondition.Scope.CAST:
			continue
		var about_forks := false
		for c in rule.conditions:
			if c is ForkedCondition:
				about_forks = true
		if about_forks and rule.all_true(child, null):
			_fire_cast_rule(child, rule, {})


func runner_done(runner: ProgramLoopRunner) -> void:
	_runners.erase(runner)


static func _is_repeat_rule(rule: ProgramRule) -> bool:
	for c in rule.conditions:
		if c.per_repeat():
			return true
	return false


## A WHEN (or loop) rule fired: quests, class trait, and conditions that spend something.
## An "if" block announces only its own conditions: its rule announced the rest.
func announce(cast: SkillCast, rule: ProgramRule) -> void:
	_mark_fired(cast, rule)
	_report_triggered(rule, cast)
	_report_calls(rule, cast)
	_trait_fired(cast, rule)
	var fired: Array = cast.extra.get(RULES_FIRED_KEY, [])
	if not rule.is_branch() and not rule.get_instance_id() in fired:
		cast.extra[RULES_FIRED_KEY] = fired + [rule.get_instance_id()]     # a new array: copies share
	for c in rule.own_conditions():
		c.on_fired(cast)                                    # Variable Store spends its charge


## True when `rule`'s WHEN fired for this cast (or for the cast it repeats or follows up).
static func rule_fired(cast: SkillCast, rule: ProgramRule) -> bool:
	return cast != null and rule != null and rule.get_instance_id() in cast.extra.get(RULES_FIRED_KEY, [])


## The rules to run: this cast's flat list (built in before_release), or a fresh one.
func _rules() -> Array[ProgramRule]:
	if _flat.is_empty() and program != null:
		_flat = program.flat_rules()
	return _flat


## A rule's place in the program, stable across casts: "2", or "2.0" for its first if block.
func _rule_key(rule: ProgramRule) -> String:
	if rule.is_branch():
		return "%d.%d" % [program.rules.find(rule.parent), rule.branch_index]
	return str(program.rules.find(rule))


## Applies one CAST rule. `record` (optional) collects what it added: {"damage", "flags"}.
func _fire_cast_rule(cast: SkillCast, rule: ProgramRule, record: Dictionary) -> void:
	announce(cast, rule)
	_apply_effects(cast, rule, record)


## `only_growing`: just the buffs growing with a counter (the rest of an always: rule is baked in).
func _apply_effects(cast: SkillCast, rule: ProgramRule, record: Dictionary, only_growing := false) -> void:
	var mult := limits.rule_effect_mult(rule)              # Gladiator: every-Nth rules x1.5
	for e in rule.effects:
		if only_growing and not e.ramps():
			continue
		var knob := limits.get_knob(e.knob)
		if knob == null:
			continue
		var v := knob.step * _steps_now(e, knob, cast) * mult
		match knob.kind:
			SkillKnob.Kind.VARIABLE:
				_queue_write(e, cast, null)
			SkillKnob.Kind.DAMAGE:
				cast.damage_mult *= 1.0 + v
				if not record.is_empty():
					record["damage"] = float(record["damage"]) * (1.0 + v)
			SkillKnob.Kind.FLAG:
				cast.flag_bonus[knob.flag_key] = cast.flag_bonus.get(knob.flag_key, 0.0) + v
				if not record.is_empty():
					record["flags"][knob.flag_key] = float(record["flags"].get(knob.flag_key, 0.0)) + v


# ---------- THE REGISTRY (ScriptRegisters) ----------
func _write_registers(rule: ProgramRule, cast: SkillCast) -> void:
	for e in rule.effects:
		if ScriptRegisters.is_write(e.knob):
			_queue_write(e, cast, null)


## `target`: the enemy a per-hit rule is about, written at once. Without one (a cast rule), the
## write waits on the cast and acts on every enemy it hits (_write_hit_entries).
func _queue_write(e: ProgramEffect, cast: SkillCast, target: Node) -> void:
	if target != null:
		ScriptRegisters.write(registers, e, target)
	elif cast != null:                           # a new array: repeats and copies share the old one
		cast.extra[HIT_WRITES_KEY] = (cast.extra.get(HIT_WRITES_KEY, []) as Array) + [e]


## How many of its knob's steps an effect gives now: its value, unless it grows with registry.size.
## The exam counts the set paying out here like a rule reading it.
func _steps_now(e: ProgramEffect, knob: SkillKnob, cast: SkillCast, _target: Node = null) -> float:
	if not e.ramps():
		return float(e.steps)
	var count := ScriptRegisters.size_of(registers)
	if count > 0 and not SkillTargets.is_enemy(cast.caster):
		GameEvents.report("rule_triggered", "var_growth")
	return ScriptRegisters.ramp_steps(count, e.steps, program.growth_room(e, knob))


## The fight is over: CLEAR_AFTER seconds without landing a hit or being hit, or a new area.
func _clear_stale_registers() -> void:
	if not is_instance_valid(_caster):
		return
	var now := Time.get_ticks_msec()
	var st := program.state()                    # the registry's clock lives on the script the player wrote
	if st.last_active_msec < 0:
		st.last_active_msec = now                  # a new script's fight starts here
	var active := st.last_active_msec
	var hp := _caster.get("health") as HealthComponent
	if hp != null:
		active = maxi(active, hp.last_damaged_msec)
	var am := _caster.get_tree().get_first_node_in_group("area_manager") as AreaManager if _caster.is_inside_tree() else null
	var area := am.current_area.get_instance_id() if am != null and am.current_area != null else st.area_id
	if st.area_id == 0:
		st.area_id = area
	if area != st.area_id or now - active > int(ScriptRegisters.CLEAR_AFTER * 1000.0):
		registers.clear()
		st.area_id = area
	# REGISTRY FORGETS ON HIT: a hit since the last cast clears it
	if hp != null and NullLawsRef.on("counters_forget", _caster):
		if _law_hit_msec < 0:
			_law_hit_msec = hp.last_damaged_msec           # hits from before the law don't count
		elif hp.last_damaged_msec > _law_hit_msec:
			_law_hit_msec = hp.last_damaged_msec
			registers.clear()
	else:
		_law_hit_msec = -1


## The ProgramSupport running a skill's script (null = none).
static func of(skill: SkillInstance) -> ProgramSupport:
	if skill != null:
		for s in skill.support_behaviors:
			if s is ProgramSupport:
				return s
	return null


## What the skill bar shows for a script using the registry: "[n]", the enemies in the set.
## "" = none.
func registers_badge() -> String:
	_clear_stale_registers()
	for rule in _rules():
		for e in rule.effects:
			if ScriptRegisters.is_write(e.knob):
				return "[%d]" % ScriptRegisters.size_of(registers)
	return ""


## Loops count what each cast and repeat hit (for break and target_alive).
func on_hit(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	var runner := cast.extra.get(LOOP_KEY) as ProgramLoopRunner
	if runner != null:
		runner.record_hit(cast, target, hit)


## Blast: a loop's next repeat waits for the explosion and starts from there.
func on_area_impact(cast: SkillCast, center: Vector3, direction: Vector3) -> void:
	var runner := cast.extra.get(LOOP_KEY) as ProgramLoopRunner
	if runner != null:
		runner.on_impact(cast, center, direction)


## HIT rules: checked for every target, before damage is applied.
func modify_hit(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	program.state().last_active_msec = Time.get_ticks_msec()
	var hit_writes: Array[ProgramEffect] = []    # land after every per-hit rule has read the set
	for rule in _rules():
		if rule.is_always() or rule.loop != null or rule.scope() != ProgramCondition.Scope.HIT:
			continue
		if not rule.all_true(cast, target):
			continue
		_mark_fired(cast, rule)
		_report_triggered(rule, cast)
		_trait_fired(cast, rule)
		var mult := limits.rule_effect_mult(rule)
		var flags_key := "program_hit_flags_%s" % _rule_key(rule)
		for e in rule.effects:
			var knob := limits.get_knob(e.knob)
			if knob == null:
				continue
			if knob.kind == SkillKnob.Kind.VARIABLE:
				hit_writes.append(e)               # per hit: on the enemy being hit
			elif knob.kind == SkillKnob.Kind.DAMAGE:
				hit.damage *= 1.0 + knob.step * _steps_now(e, knob, cast, target) * mult
			elif SkillProgramLimits.hit_defense_knob(knob) and not limits.per_hit_any_knob():
				_hit_defense(cast, rule, knob, e, hit)
			elif SkillProgramLimits.hit_support_knob(knob) and not limits.per_hit_any_knob():
				# a support gem's flag, for this hit only (a marked enemy explodes bigger...)
				var add := knob.step * _steps_now(e, knob, cast, target) * limits.rule_effect_mult(rule, false)
				hit.flag_bonus[knob.flag_key] = float(hit.flag_bonus.get(knob.flag_key, 0.0)) + add
			elif limits.per_hit_attack_speed(knob) and not cast.extra.has(flags_key):
				# Assassin: the next cast of this skill is faster (once per rule per cast)
				_hit_speed += knob.value_for(e.steps) * mult
				_hit_speed_msec = Time.get_ticks_msec()
			elif knob.kind == SkillKnob.Kind.FLAG and limits.per_hit_any_knob() \
					and not cast.extra.has(flags_key):
				# Assassin: a per-hit flag change lasts for the rest of this cast, added once
				cast.flag_bonus[knob.flag_key] = cast.flag_bonus.get(knob.flag_key, 0.0) + knob.step * _steps_now(e, knob, cast, target) * mult
		if limits.per_hit_any_knob():
			cast.extra[flags_key] = true
	_write_hit_entries(cast, target, hit_writes)


## The cast's registry.add / remove (from always:, WHEN and loop rules), then this hit's own from
## per-hit rules, act on the enemy just hit, after its per-hit rules have read the set.
func _write_hit_entries(cast: SkillCast, target: Node, hit_writes: Array[ProgramEffect]) -> void:
	for e in cast.extra.get(HIT_WRITES_KEY, []):
		ScriptRegisters.write(registers, e, target)
	for e in hit_writes:
		ScriptRegisters.write(registers, e, target)


## A per-hit rule's leech, barrier or guard. Leech adds to this hit's own leech. Barrier and guard
## go to the caster when the hit lands, once per rule per cast (a repeat or copy of the cast
## shares the original's), so one swing through ten enemies shields you once, not ten times.
## The per-hit damage bonus (Assassin) doesn't apply; every-Nth (Gladiator) does.
func _hit_defense(cast: SkillCast, rule: ProgramRule, knob: SkillKnob, e: ProgramEffect, hit: HitInfo) -> void:
	var v := knob.step * _steps_now(e, knob, cast, hit.target) * limits.rule_effect_mult(rule, false)
	if v <= 0.0:
		return
	if knob.id == &"leech":
		hit.leech_bonus += v
		return
	var once := "program_hit_def_%s_%s" % [_rule_key(rule), knob.id]
	if cast.extra.has(once):
		return
	cast.extra[once] = true
	if knob.id == &"barrier":
		hit.barrier_bonus += v
	else:
		hit.guard_bonus += v


## Assassin: a per-hit rule with attack speed fired on the last cast's hits. The skill's next
## cast is that much faster (or slower, for a drawback), if it starts within HIT_SPEED_WINDOW.
func speed_mult(_skill: SkillInstance) -> float:
	if _hit_speed == 0.0 or (Time.get_ticks_msec() - _hit_speed_msec) / 1000.0 > HIT_SPEED_WINDOW:
		return 1.0
	return maxf(1.0 + _hit_speed, 0.1)


## Notes on the cast which conditions this rule fired on (FIRED_KEY).
static func _mark_fired(cast: SkillCast, rule: ProgramRule) -> void:
	var fired: Array = cast.extra.get(FIRED_KEY, [])
	for c in rule.own_conditions():
		if not c.fired_id() in fired:
			fired.append(c.fired_id())
	cast.extra[FIRED_KEY] = fired


## The condition ids whose WHEN rules fired for `cast`: its own, and those of the cast that
## started its loop (a loop's repeats answer for the rule that started them).
static func fired_conditions(cast: SkillCast) -> Array:
	if cast == null:
		return []
	var out: Array = cast.extra.get(FIRED_KEY, []).duplicate()
	var runner := cast.extra.get(LOOP_KEY) as ProgramLoopRunner
	if runner != null and runner.root != null and runner.root != cast:
		for id in runner.root.extra.get(FIRED_KEY, []):
			if not id in out:
				out.append(id)
	return out


## Class trait reaction to a WHEN rule firing (Paladin's armour buff). One buff per rule.
func _trait_fired(cast: SkillCast, rule: ProgramRule) -> void:
	if limits.class_trait != null and not SkillTargets.is_enemy(cast.caster):
		limits.class_trait.on_rule_fired(cast.caster, "%d_%s" % [get_instance_id(), _rule_key(rule)])


## Quest event: a WHEN rule actually fired in combat ("rule_triggered", condition id).
## Only the player's casts count.
func _report_triggered(rule: ProgramRule, cast: SkillCast) -> void:
	if SkillTargets.is_enemy(cast.caster):
		return
	for c in rule.own_conditions():
		GameEvents.report("rule_triggered", c.type_id())
	# Which rule of which skill: "<gem id>#<rule index>" (the exam debrief counts these)
	if cast.skill != null and cast.skill.gem != null:
		GameEvents.report("rule_fired", "%s#%s" % [cast.skill.gem.id, _rule_key(rule)])


## A rule (or if block) that calls a routine ran: "routine_called", "<routine index>|<skill gem id>"
## for each call (the Engineer exam counts them). Set by SkillProgram.resolve; only the player's casts.
func _report_calls(rule: ProgramRule, cast: SkillCast) -> void:
	if SkillTargets.is_enemy(cast.caster) or cast.skill == null or cast.skill.gem == null:
		return
	var holder: Object = rule.branch() if rule.is_branch() else rule
	if holder == null or not holder.has_meta(&"calls"):
		return
	for index in holder.get_meta(&"calls"):
		GameEvents.report("routine_called", "%d|%s" % [int(index), cast.skill.gem.id])
