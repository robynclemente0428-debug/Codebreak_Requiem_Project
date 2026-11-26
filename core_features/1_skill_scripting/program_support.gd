class_name ProgramSupport
extends SupportBehavior

const CAST_NUMBER_KEY := "program_cast_number"
const REPEAT_UNDO_KEY := "program_repeat_undo"
const LOOP_KEY := "program_loop"
const FIRED_KEY := "program_fired"
const HIT_WRITES_KEY := "registry_hit_writes"
const RULES_FIRED_KEY := "program_rules_fired"
const LOOP_RULE_KEY := "program_loop_rule"

var program: SkillProgram
var limits: SkillProgramLimits
var _flat: Array[ProgramRule] = []
var _cast_count := 0
var registers: Dictionary:
	get:
		return program.state().registers
var _caster: Node3D
var _runners: Array[ProgramLoopRunner] = []
const HIT_SPEED_WINDOW := 2.5
var _hit_speed := 0.0
var _hit_speed_msec := 0
var _order: Array = []
var _order_frame := -1


func _init(p_program: SkillProgram = null, p_limits: SkillProgramLimits = null) -> void:
	program = p_program
	limits = p_limits


func before_release(cast: SkillCast) -> void:
	if cast.extra.get("hologram", false) or cast.depth > 0:
		return
	_caster = cast.caster
	_clear_stale_registers()
	program.state().sort_by = 0
	_order_frame = -1
	_hit_speed = 0.0
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
	for rule in program.rules:
		if rule.is_always() and rule.loop == null:
			_report_calls(rule, cast)
	for rule in _flat:
		if rule.scope() != ProgramCondition.Scope.CAST or rule.in_loop():
			continue
		if rule.loop != null:
			if rule.loop.mode == ProgramLoop.Mode.WHILE:
				whiles.append(rule)
			elif _is_repeat_rule(rule):
				late_fors.append(rule)
			elif rule.is_always() or rule.all_true(cast, null):
				if not rule.is_always():
					announce(cast, rule)
				for i in rule.loop.count:
					tickets.append(rule)
			continue
		if rule.is_always():
			_write_registers(rule, cast)
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


func apply_repeat_rules(child: SkillCast, loop_rule: ProgramRule = null) -> void:
	var undo: Dictionary = child.extra.get(REPEAT_UNDO_KEY, {})
	if not undo.is_empty():
		child.damage_mult /= maxf(float(undo["damage"]), 0.0001)
		for k in undo["flags"]:
			child.flag_bonus[k] = child.flag_bonus.get(k, 0.0) - float(undo["flags"][k])
	child.extra[REPEAT_UNDO_KEY] = {}
	for rule in _rules():
		if rule.loop != null or rule.is_always() or rule.scope() != ProgramCondition.Scope.CAST \
				or not _is_repeat_rule(rule) or rule.in_loop():
			continue
		if rule.all_true(child, null):
			_fire_cast_rule(child, rule, {})
	if loop_rule != null:
		_apply_effects(child, loop_rule, {})
		_apply_loop_branches(child, loop_rule)


func _apply_loop_branches(child: SkillCast, loop_rule: ProgramRule) -> void:
	for i in loop_rule.branches.size():
		var br := loop_rule.branch_rule(i)
		if br.effects.is_empty() or br.scope() != ProgramCondition.Scope.CAST:
			continue
		if _own_true(br, child, null):
			_fire_cast_rule(child, br, {})


static func _own_true(rule: ProgramRule, cast: SkillCast, target: Node) -> bool:
	for c in rule.own_conditions():
		if not c.is_true(cast, target):
			return false
	return true


static func _counts_swings(skill: SkillInstance) -> bool:
	for s in skill.support_behaviors:
		if s is FinishingBlowSupport or s is OverclockSupport:
			return true
	return false


func apply_fork_rules(child: SkillCast) -> void:
	for rule in _rules():
		if rule.loop != null or rule.is_always() or rule.scope() != ProgramCondition.Scope.CAST \
				or rule.in_loop():
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


func announce(cast: SkillCast, rule: ProgramRule) -> void:
	_mark_fired(cast, rule)
	_report_triggered(rule, cast)
	_report_calls(rule, cast)
	_trait_fired(cast, rule)
	var fired: Array = cast.extra.get(RULES_FIRED_KEY, [])
	if not rule.is_branch() and not rule.get_instance_id() in fired:
		cast.extra[RULES_FIRED_KEY] = fired + [rule.get_instance_id()]
	for c in rule.own_conditions():
		c.on_fired(cast)


static func rule_fired(cast: SkillCast, rule: ProgramRule) -> bool:
	return cast != null and rule != null and rule.get_instance_id() in cast.extra.get(RULES_FIRED_KEY, [])


func _rules() -> Array[ProgramRule]:
	if _flat.is_empty() and program != null:
		_flat = program.flat_rules()
	return _flat


func rule_key(rule: ProgramRule) -> String:
	return _rule_key(rule)


func _rule_key(rule: ProgramRule) -> String:
	if rule.is_branch():
		return "%d.%d" % [program.rules.find(rule.parent), rule.branch_index]
	return str(program.rules.find(rule))


func _fire_cast_rule(cast: SkillCast, rule: ProgramRule, record: Dictionary) -> void:
	announce(cast, rule)
	_apply_effects(cast, rule, record)


func _apply_effects(cast: SkillCast, rule: ProgramRule, record: Dictionary, only_growing := false) -> void:
	var mult := limits.rule_effect_mult(rule)
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


func _write_registers(rule: ProgramRule, cast: SkillCast) -> void:
	for e in rule.effects:
		if ScriptRegisters.is_write(e.knob):
			_queue_write(e, cast, null)


func _queue_write(e: ProgramEffect, cast: SkillCast, target: Node) -> void:
	if ScriptRegisters.is_sort(e):
		_set_order(e.sort_by)
		return
	if target != null:
		ScriptRegisters.write(registers, e, target)
	elif cast != null:
		cast.extra[HIT_WRITES_KEY] = (cast.extra.get(HIT_WRITES_KEY, []) as Array) + [e]


func _steps_now(e: ProgramEffect, knob: SkillKnob, cast: SkillCast, _target: Node = null) -> float:
	if not e.ramps():
		return float(e.steps)
	var count := ScriptRegisters.size_of(registers)
	if count > 0 and not SkillTargets.is_enemy(cast.caster):
		GameEvents.report("rule_triggered", "var_growth")
	return ScriptRegisters.ramp_steps(count, e.steps, program.growth_room(e, knob))


func _clear_stale_registers() -> void:
	if not is_instance_valid(_caster):
		return
	var now := Time.get_ticks_msec()
	var st := program.state()
	if st.last_active_msec < 0:
		st.last_active_msec = now
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


static func of(skill: SkillInstance) -> ProgramSupport:
	if skill != null:
		for s in skill.support_behaviors:
			if s is ProgramSupport:
				return s
	return null


func registers_badge() -> String:
	_clear_stale_registers()
	for rule in _rules():
		for e in rule.effects:
			if ScriptRegisters.is_write(e.knob):
				return "[%d]" % ScriptRegisters.size_of(registers)
	return ""


func on_hit(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	var runner := cast.extra.get(LOOP_KEY) as ProgramLoopRunner
	if runner != null:
		runner.record_hit(cast, target, hit)


func on_area_impact(cast: SkillCast, center: Vector3, direction: Vector3) -> void:
	var runner := cast.extra.get(LOOP_KEY) as ProgramLoopRunner
	if runner != null:
		runner.on_impact(cast, center, direction)


func modify_hit(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	program.state().last_active_msec = Time.get_ticks_msec()
	var hit_writes: Array[ProgramEffect] = []
	for rule in _rules():
		if rule.is_always() or rule.loop != null or rule.scope() != ProgramCondition.Scope.HIT:
			continue
		if rule.in_loop():
			if cast.extra.get(LOOP_RULE_KEY, "") != _rule_key(rule.parent) or not _own_true(rule, cast, target):
				continue
		elif not rule.all_true(cast, target):
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
				hit_writes.append(e)
			elif knob.kind == SkillKnob.Kind.DAMAGE:
				hit.damage *= 1.0 + knob.step * _steps_now(e, knob, cast, target) * mult
			elif SkillProgramLimits.hit_defense_knob(knob) and not limits.per_hit_any_knob():
				_hit_defense(cast, rule, knob, e, hit)
			elif SkillProgramLimits.hit_support_knob(knob) and not limits.per_hit_any_knob():
				var add := knob.step * _steps_now(e, knob, cast, target) * limits.rule_effect_mult(rule, false)
				hit.flag_bonus[knob.flag_key] = float(hit.flag_bonus.get(knob.flag_key, 0.0)) + add
			elif limits.per_hit_attack_speed(knob) and not cast.extra.has(flags_key):
				_hit_speed += knob.value_for(e.steps) * mult
				_hit_speed_msec = Time.get_ticks_msec()
			elif knob.kind == SkillKnob.Kind.FLAG and limits.per_hit_any_knob() \
					and not cast.extra.has(flags_key):
				cast.flag_bonus[knob.flag_key] = cast.flag_bonus.get(knob.flag_key, 0.0) + knob.step * _steps_now(e, knob, cast, target) * mult
		if limits.per_hit_any_knob():
			cast.extra[flags_key] = true
	_write_hit_entries(cast, target, hit_writes)


func _write_hit_entries(cast: SkillCast, target: Node, hit_writes: Array[ProgramEffect]) -> void:
	for e in cast.extra.get(HIT_WRITES_KEY, []):
		ScriptRegisters.write(registers, e, target)
	for e in hit_writes:
		if ScriptRegisters.is_sort(e):
			_set_order(e.sort_by)
		else:
			ScriptRegisters.write(registers, e, target)


func _set_order(sort_by: int) -> void:
	if program.state().sort_by != sort_by:
		program.state().sort_by = sort_by
		_order_frame = -1


func registry_order() -> Array:
	var frame := Engine.get_physics_frames()
	if frame != _order_frame:
		_order_frame = frame
		_order = ScriptRegisters.ordered(registers, program.state().sort_by, _caster)
	return _order


func position_of(target: Node) -> int:
	var at: Variant = ScriptRegisters.entry_key(target)
	return registry_order().find(at) if at != null else -1


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


func speed_mult(_skill: SkillInstance) -> float:
	if _hit_speed == 0.0 or (Time.get_ticks_msec() - _hit_speed_msec) / 1000.0 > HIT_SPEED_WINDOW:
		return 1.0
	return maxf(1.0 + _hit_speed, 0.1)


static func _mark_fired(cast: SkillCast, rule: ProgramRule) -> void:
	var fired: Array = cast.extra.get(FIRED_KEY, [])
	for c in rule.own_conditions():
		if not c.fired_id() in fired:
			fired.append(c.fired_id())
	cast.extra[FIRED_KEY] = fired


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


func _trait_fired(cast: SkillCast, rule: ProgramRule) -> void:
	if limits.class_trait != null and not SkillTargets.is_enemy(cast.caster):
		limits.class_trait.on_rule_fired(cast.caster, "%d_%s" % [get_instance_id(), _rule_key(rule)])


func _report_triggered(rule: ProgramRule, cast: SkillCast) -> void:
	if SkillTargets.is_enemy(cast.caster):
		return
	for c in rule.own_conditions():
		GameEvents.report("rule_triggered", c.type_id())
	if cast.skill != null and cast.skill.gem != null:
		GameEvents.report("rule_fired", "%s#%s" % [cast.skill.gem.id, _rule_key(rule)])


func _report_calls(rule: ProgramRule, cast: SkillCast) -> void:
	if SkillTargets.is_enemy(cast.caster) or cast.skill == null or cast.skill.gem == null:
		return
	var holder: Object = rule.branch() if rule.is_branch() else rule
	if holder == null or not holder.has_meta(&"calls"):
		return
	for index in holder.get_meta(&"calls"):
		GameEvents.report("routine_called", "%d|%s" % [int(index), cast.skill.gem.id])
