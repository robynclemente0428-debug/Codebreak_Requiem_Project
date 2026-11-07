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

var program: SkillProgram
var limits: SkillProgramLimits
var _cast_count := 0
## The script's memory: register name -> value (ScriptRegisters). It lives on the program, so it
## outlasts this support when the skill is rebuilt.
var registers: Dictionary:
	get:
		return program.registers
var _caster: Node3D
## While a cast's rules are being judged, writes wait here, so every rule reads the same values.
var _pending_writes: Array[ProgramEffect] = []
var _judging := false
## The counters a growing buff reads that have already risen this cast: they only rise once.
var _raised := {}
## Loops still running (kept here so they live until they finish).
var _runners: Array[ProgramLoopRunner] = []
## Assassin: attack speed from per-hit rules, for the skill's next cast (see speed_mult).
const HIT_SPEED_WINDOW := 2.5     # seconds the bonus waits for the next attack
var _hit_speed := 0.0
var _hit_speed_msec := 0


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
	_raised.clear()
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
	_judging = true
	for rule in program.rules:
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
				for i in rule.loop.count:
					tickets.append(rule)
			continue
		if rule.is_always():
			_write_registers(rule)               # the rest of an always: rule is baked into the skill
			_apply_effects(cast, rule, {}, true)
			continue
		if not rule.all_true(cast, null):
			continue
		_fire_cast_rule(cast, rule, undo if _is_repeat_rule(rule) else {})
	_judging = false
	for e in _pending_writes:
		_write_register(e)
	_pending_writes.clear()
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
	for rule in program.rules:
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
	for rule in program.rules:
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
func announce(cast: SkillCast, rule: ProgramRule) -> void:
	_mark_fired(cast, rule)
	_report_triggered(rule, cast)
	_trait_fired(cast, rule)
	for c in rule.conditions:
		c.on_fired(cast)                                    # Variable Store spends its charge


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
				_queue_write(e)
			SkillKnob.Kind.DAMAGE:
				cast.damage_mult *= 1.0 + v
				if not record.is_empty():
					record["damage"] = float(record["damage"]) * (1.0 + v)
			SkillKnob.Kind.FLAG:
				cast.flag_bonus[knob.flag_key] = cast.flag_bonus.get(knob.flag_key, 0.0) + v
				if not record.is_empty():
					record["flags"][knob.flag_key] = float(record["flags"].get(knob.flag_key, 0.0)) + v


# ---------- REGISTERS (ScriptRegisters) ----------
func _write_registers(rule: ProgramRule) -> void:
	for e in rule.effects:
		if ScriptRegisters.is_write(e.knob):
			_queue_write(e)


func _queue_write(e: ProgramEffect) -> void:
	if _judging:
		_pending_writes.append(e)
	else:
		_write_register(e)


func _write_register(e: ProgramEffect) -> void:
	var reg := e.register_name()
	var before := int(registers.get(reg, 0))
	var after := ScriptRegisters.written(e, before)
	if after > before and _grows_with(reg):
		if _raised.has(reg):
			return
		_raised[reg] = true
	registers[reg] = after


func _grows_with(reg: String) -> bool:
	for rule in program.rules:
		for e in rule.effects:
			if e.ramps() and e.ramp_register() == reg:
				return true
	return false


## How many of its knob's steps an effect gives now: its value, unless it grows with a counter. The
## exam counts a counter paying out here like a rule reading it.
func _steps_now(e: ProgramEffect, knob: SkillKnob, cast: SkillCast) -> float:
	if not e.ramps():
		return float(e.steps)
	var count := int(registers.get(e.ramp_register(), 0))
	if count > 0 and not SkillTargets.is_enemy(cast.caster):
		GameEvents.report("rule_triggered", "var_growth")
	return ScriptRegisters.ramp_steps(count, e.steps, program.growth_room(e, knob))


## The fight is over: CLEAR_AFTER seconds without landing a hit or being hit, or a new area.
func _clear_stale_registers() -> void:
	if not is_instance_valid(_caster):
		return
	var now := Time.get_ticks_msec()
	if program.last_active_msec < 0:
		program.last_active_msec = now             # a new script's fight starts here
	var active := program.last_active_msec
	var hp := _caster.get("health") as HealthComponent
	if hp != null:
		active = maxi(active, hp.last_damaged_msec)
	var am := _caster.get_tree().get_first_node_in_group("area_manager") as AreaManager if _caster.is_inside_tree() else null
	var area := am.current_area.get_instance_id() if am != null and am.current_area != null else program.area_id
	if program.area_id == 0:
		program.area_id = area
	if area != program.area_id or now - active > int(ScriptRegisters.CLEAR_AFTER * 1000.0):
		registers.clear()
		program.area_id = area


## The ProgramSupport running a skill's script (null = none).
static func of(skill: SkillInstance) -> ProgramSupport:
	if skill != null:
		for s in skill.support_behaviors:
			if s is ProgramSupport:
				return s
	return null


static func register_value(skill: SkillInstance, reg: String) -> int:
	var support := of(skill)
	return int(support.registers.get(reg, 0)) if support != null else 0


## What the skill bar shows for a script using registers: "x=3", or "3|1" with both. "" = none.
func registers_badge() -> String:
	_clear_stale_registers()
	var used: Array[String] = []
	for reg in ScriptRegisters.NAMES:
		if _uses_register(reg):
			used.append(reg)
	match used.size():
		1:
			return "%s=%d" % [used[0], int(registers.get(used[0], 0))]
		2:
			return "%d|%d" % [int(registers.get("x", 0)), int(registers.get("y", 0))]
	return ""


func _uses_register(reg: String) -> bool:
	for rule in program.rules:
		for e in rule.effects:
			if ScriptRegisters.is_write(e.knob) and e.register_name() == reg:
				return true
			if e.ramps() and e.ramp_register() == reg:
				return true
	return false


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
	program.last_active_msec = Time.get_ticks_msec()
	for rule in program.rules:
		if rule.is_always() or rule.loop != null or rule.scope() != ProgramCondition.Scope.HIT:
			continue
		if not rule.all_true(cast, target):
			continue
		_mark_fired(cast, rule)
		_report_triggered(rule, cast)
		_trait_fired(cast, rule)
		var mult := limits.rule_effect_mult(rule)
		var flags_key := "program_hit_flags_%d" % program.rules.find(rule)
		for e in rule.effects:
			var knob := limits.get_knob(e.knob)
			if knob == null:
				continue
			if knob.kind == SkillKnob.Kind.VARIABLE:
				_write_register(e)
			elif knob.kind == SkillKnob.Kind.DAMAGE:
				hit.damage *= 1.0 + knob.step * _steps_now(e, knob, cast) * mult
			elif limits.per_hit_attack_speed(knob) and not cast.extra.has(flags_key):
				# Assassin: the next cast of this skill is faster (once per rule per cast)
				_hit_speed += knob.value_for(e.steps) * mult
				_hit_speed_msec = Time.get_ticks_msec()
			elif knob.kind == SkillKnob.Kind.FLAG and limits.per_hit_any_knob() \
					and not cast.extra.has(flags_key):
				# Assassin: a per-hit flag change lasts for the rest of this cast, added once
				cast.flag_bonus[knob.flag_key] = cast.flag_bonus.get(knob.flag_key, 0.0) + knob.step * _steps_now(e, knob, cast) * mult
		if limits.per_hit_any_knob():
			cast.extra[flags_key] = true


## Assassin: a per-hit rule with attack speed fired on the last cast's hits. The skill's next
## cast is that much faster (or slower, for a drawback), if it starts within HIT_SPEED_WINDOW.
func speed_mult(_skill: SkillInstance) -> float:
	if _hit_speed == 0.0 or (Time.get_ticks_msec() - _hit_speed_msec) / 1000.0 > HIT_SPEED_WINDOW:
		return 1.0
	return maxf(1.0 + _hit_speed, 0.1)


## Notes on the cast which conditions this rule fired on (FIRED_KEY).
static func _mark_fired(cast: SkillCast, rule: ProgramRule) -> void:
	var fired: Array = cast.extra.get(FIRED_KEY, [])
	for c in rule.conditions:
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
		limits.class_trait.on_rule_fired(cast.caster, "%d_%d" % [get_instance_id(), program.rules.find(rule)])


## Quest event: a WHEN rule actually fired in combat ("rule_triggered", condition id).
## Only the player's casts count.
func _report_triggered(rule: ProgramRule, cast: SkillCast) -> void:
	if SkillTargets.is_enemy(cast.caster):
		return
	for c in rule.conditions:
		GameEvents.report("rule_triggered", c.type_id())
	# Which rule of which skill: "<gem id>#<rule index>" (the exam debrief counts these)
	if cast.skill != null and cast.skill.gem != null:
		GameEvents.report("rule_fired", "%s#%d" % [cast.skill.gem.id, program.rules.find(rule)])
