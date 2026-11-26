class_name ProgramLoopRunner
extends RefCounted

const GAP := 0.22
const IMPACT_GAP := 0.1
const DEBUG := true


var support: ProgramSupport
var root: SkillCast
var current: SkillCast
var cap := ProgramLoop.BASE_CAP
var index := 0
var finished := false

var hits := 0
var kills := 0
var landed := false
var landed_hits := 0
var landed_kills := 0
var last_targets: Array = []
var last_impact: Variant = null
var last_direction := Vector3.ZERO

var _tickets: Array[ProgramRule] = []
var _whiles: Array[ProgramRule] = []
var _late_fors: Array[ProgramRule] = []
var _while_used := {}
var _stopped := {}
var _iter_done := false
var _tree: SceneTree
var _current_rule: ProgramRule
var _current_paid := 0.0
var _forgiven := 0
var _hit_so_far: Array = []


func _init(p_support: ProgramSupport, p_root: SkillCast, p_cap: int,
		tickets: Array[ProgramRule], whiles: Array[ProgramRule], late_fors: Array[ProgramRule] = []) -> void:
	support = p_support
	root = p_root
	cap = p_cap
	_tickets = tickets
	_whiles = whiles
	_late_fors = late_fors


func start() -> void:
	_tree = root.caster.get_tree()
	root.extra[ProgramSupport.LOOP_KEY] = self
	root.extra["loop_index"] = 0
	root.extra["loop_cap"] = cap
	_begin(root)


func repeat_mana_cost() -> float:
	return root.skill.get_mana_cost() * ProgramLoop.MANA_FRACTION * support.limits.repeat_mana_mult()


func any_target_alive() -> bool:
	for t in last_targets:
		if is_instance_valid(t) and not SkillBehavior.is_dead(t):
			return true
	return false


func record_hit(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	if finished or cast != current or target.is_in_group(&"breakables"):
		return
	hits += 1
	if hit.killed:
		kills += 1
	if not (target in last_targets):
		last_targets.append(target)


func on_impact(cast: SkillCast, center: Vector3, direction: Vector3) -> void:
	if finished or cast != current or _iter_done or last_impact != null:
		return
	last_impact = center
	last_direction = direction
	_tree.create_timer(IMPACT_GAP, false).timeout.connect(_iteration_done.bind(cast))


func _begin(cast: SkillCast) -> void:
	current = cast
	_iter_done = false
	hits = 0
	kills = 0
	last_targets = []
	last_impact = null
	var wait := GAP
	if cast.behavior.waits_for_impact():
		wait = cast.flag("range") / maxf(cast.flag("speed"), 1.0) + 0.6
	_tree.create_timer(wait, false).timeout.connect(_iteration_done.bind(cast))


func _iteration_done(cast: SkillCast) -> void:
	if finished or cast != current or _iter_done:
		return
	_iter_done = true
	landed = true
	landed_hits = hits
	landed_kills = kills
	if not root.is_valid() or SkillBehavior.is_dead(root.caster):
		_log("stop: caster gone or dead")
		_finish()
		return
	var mana := root.caster.get("mana") as ManaComponent
	var cost := repeat_mana_cost()
	if DEBUG:
		var alive := 0
		for t in last_targets:
			if is_instance_valid(t) and not SkillBehavior.is_dead(t):
				alive += 1
		_log("iteration %d landed: %d hits, %d kills, %d targets (%d alive), cast #%s, mana %.1f / repeat costs %.1f" % [
			index, hits, kills, last_targets.size(), alive, str(root.extra.get(ProgramSupport.CAST_NUMBER_KEY, "?")),
			mana.current_mana if mana != null and mana.get("current_mana") != null else -1.0, cost])
	if current != root and hits == 0 and _forgiven < int(round(root.flag("except_retries"))):
		_except(mana, cost)
		return
	if index >= cap:
		_log("stop: reached the cap (%d)" % cap)
		_finish()
		return
	if mana != null and cost > 0.0 and not mana.has_enough(cost):
		_log("stop: not enough mana for a repeat")
		_finish()
		return
	var rule := _next_rule()
	if rule == null:
		_log("stop: no loop wants another repeat")
		_finish()
		return
	_log("repeat %d (rule: %s)" % [index + 1, _rule_text(rule)])
	_current_paid = 0.0
	if mana != null and cost > 0.0 and mana.spend(cost):
		_current_paid = cost
	index += 1
	if not SkillTargets.is_enemy(root.caster):
		GameEvents.report("loop_repeat", "stop" if rule.loop_stops_itself() else "for")
	_repeat(rule)


func _except(mana: ManaComponent, cost: float) -> void:
	_forgiven += 1
	if mana != null and _current_paid > 0.0:
		mana.restore(_current_paid * clampf(root.flag("except_refund"), 0.0, 1.0))
	_current_paid = 0.0
	if mana != null and cost > 0.0:
		if not mana.has_enough(cost):
			_finish()
			return
		mana.spend(cost)
		_current_paid = cost
	_repeat(_current_rule, true)


func _next_rule() -> ProgramRule:
	if current == root and not _late_fors.is_empty():
		for r in _late_fors:
			if DEBUG:
				var parts: Array[String] = []
				for c in r.conditions:
					parts.append("%s=%s" % [c.type_id(), str(c.is_true(root, null))])
				_log("judging FOR rule after landing: %s" % ", ".join(parts))
			if r.all_true(root, null):
				support.announce(root, r)
				for i in r.loop.count:
					_tickets.append(r)
		_late_fors.clear()
	for rule in _tickets + _whiles:
		if not _stopped.has(rule) and _breaks_now(rule):
			_stopped[rule] = true
	while not _tickets.is_empty():
		var r: ProgramRule = _tickets.pop_front()
		if not _stopped.has(r):
			return r
	for r in _whiles:
		if _stopped.has(r) or int(_while_used.get(r, 0)) >= r.loop.count:
			continue
		if r.all_true(current, null):
			_while_used[r] = int(_while_used.get(r, 0)) + 1
			support.announce(current, r)
			return r
	return null


func _breaks_now(rule: ProgramRule) -> bool:
	for i in rule.branches.size():
		var b := rule.branches[i]
		if not b.breaks or b.conditions.is_empty():
			continue
		var all := true
		for c in b.conditions:
			if not c.is_true(current, null):
				all = false
				break
		if all:
			_log("break: if %s" % " and ".join(b.conditions.map(func(c: ProgramCondition) -> String: return c.type_id())))
			support.announce(current, rule.branch_rule(i))
			return true
	return false


func _repeat(rule: ProgramRule, retry := false) -> void:
	_current_rule = rule
	var child := SkillCast.new(root.caster, root.skill, root.stats, root.behavior)
	child.depth = 1
	child.flag_bonus = root.flag_bonus.duplicate()
	child.damage_mult = root.damage_mult * pow(ProgramLoop.FALLOFF, index)
	child.extra = root.extra.duplicate()
	child.extra["loop_index"] = index
	child.extra["loop_repeat"] = true
	child.extra["loop_retry"] = retry
	for t in last_targets:
		if not (t in _hit_so_far):
			_hit_so_far.append(t)
	child.extra["loop_hit_so_far"] = _hit_so_far.duplicate()
	child.extra[ProgramSupport.LOOP_RULE_KEY] = support.rule_key(rule)
	support.apply_repeat_rules(child, rule)
	var from = null if retry else last_impact
	var dir := last_direction
	_begin(child)
	root.behavior.repeat_release(child, from, dir)


func _finish() -> void:
	finished = true
	support.runner_done(self)


func _log(text: String) -> void:
	if DEBUG and root != null and is_instance_valid(root.caster) and root.caster.is_in_group("players"):
		print("[Loop] %s: %s" % [root.skill.gem.id, text])


func _rule_text(rule: ProgramRule) -> String:
	var parts: Array[String] = []
	for c in rule.conditions:
		parts.append(c.type_id())
	return ("when " + " and ".join(parts)) if not parts.is_empty() else "always"
