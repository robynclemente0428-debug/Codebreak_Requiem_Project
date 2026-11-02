class_name ProgramLoopRunner
extends RefCounted
## Runs the repeats of ONE cast whose program has loops (see ProgramLoop for the rules).
## ProgramSupport makes one in before_release and keeps it until the loop ends.
##
## One "iteration" = the original cast or one repeat. When it is done (a short gap for most
## skills, the explosion for Blast), the runner decides whether to repeat:
##   1. BREAK: a loop whose break fired (a kill, or nothing hit) stops
##   2. FOR loops that fired on the cast still owe repeats -> repeat
##   3. WHILE loops: their conditions are checked again -> repeat while true, up to their max
##   then the shared cap and the mana for the repeat must allow it.
## Try / Except (support): a repeat that hit nothing is forgiven a few times per cast. Its mana
## comes back, it doesn't count toward the cap, and it is tried again.

const GAP := 0.22               # seconds between an iteration and the next repeat
const IMPACT_GAP := 0.1         # after a Blast explosion
## Prints each repeat decision to Output ("[Loop] ..."), to see why a loop did or didn't run.
const DEBUG := true

var support: ProgramSupport
var root: SkillCast
## The iteration in progress (the root cast, then each repeat).
var current: SkillCast
var cap := ProgramLoop.BASE_CAP
## Repeats done so far.
var index := 0
var finished := false

## What the iteration in progress did (for break, target_alive and Pointer).
var hits := 0
var kills := 0
var last_targets: Array = []
var last_impact: Variant = null
var last_direction := Vector3.ZERO

var _tickets: Array[ProgramRule] = []     # FOR repeats still owed, in order
var _whiles: Array[ProgramRule] = []
## FOR loops whose conditions are about what the cast hit (target_alive...): checked once, when
## the original cast has landed, instead of before it (when nothing has been hit yet).
var _late_fors: Array[ProgramRule] = []
var _while_used := {}                     # rule -> repeats it has run
var _stopped := {}                        # rule -> true once its break fired
var _iter_done := false
var _tree: SceneTree
var _current_rule: ProgramRule            # the loop running the repeat in progress
var _current_paid := 0.0                  # mana that repeat cost
var _forgiven := 0                        # Try / Except retries used
var _hit_so_far: Array = []               # everyone the cast and its repeats have hit


func _init(p_support: ProgramSupport, p_root: SkillCast, p_cap: int,
		tickets: Array[ProgramRule], whiles: Array[ProgramRule], late_fors: Array[ProgramRule] = []) -> void:
	support = p_support
	root = p_root
	cap = p_cap
	_tickets = tickets
	_whiles = whiles
	_late_fors = late_fors


## Called in before_release, just before the original cast's release().
func start() -> void:
	_tree = root.caster.get_tree()
	root.extra[ProgramSupport.LOOP_KEY] = self
	root.extra["loop_index"] = 0
	root.extra["loop_cap"] = cap
	_begin(root)


## Mana one repeat costs.
func repeat_mana_cost() -> float:
	return root.skill.get_mana_cost() * ProgramLoop.MANA_FRACTION * support.limits.repeat_mana_mult()


## TargetAliveCondition: did the last iteration hit something that is still alive?
func any_target_alive() -> bool:
	for t in last_targets:
		if is_instance_valid(t) and not SkillBehavior.is_dead(t):
			return true
	return false


# ---------- called by ProgramSupport ----------

func record_hit(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	if finished or cast != current or target.is_in_group(&"breakables"):
		return
	hits += 1
	if hit.killed:
		kills += 1
	if not (target in last_targets):
		last_targets.append(target)


## Blast: the iteration is done when its shot explodes (the first one, with several projectiles).
func on_impact(cast: SkillCast, center: Vector3, direction: Vector3) -> void:
	if finished or cast != current or _iter_done or last_impact != null:
		return
	last_impact = center
	last_direction = direction
	_tree.create_timer(IMPACT_GAP, false).timeout.connect(_iteration_done.bind(cast))


# ---------- the loop ----------

func _begin(cast: SkillCast) -> void:
	current = cast
	_iter_done = false
	hits = 0
	kills = 0
	last_targets = []
	last_impact = null
	var wait := GAP
	if cast.behavior.waits_for_impact():
		# Fallback in case the shot never explodes: its flight time and a bit
		wait = cast.flag("range") / maxf(cast.flag("speed"), 1.0) + 0.6
	_tree.create_timer(wait, false).timeout.connect(_iteration_done.bind(cast))


func _iteration_done(cast: SkillCast) -> void:
	if finished or cast != current or _iter_done:
		return
	_iter_done = true
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
		_finish()                                # out of memory
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
	if not SkillTargets.is_enemy(root.caster):      # the Architect exam counts these
		GameEvents.report("loop_repeat", "stop" if rule.loop.stops_itself() else "for")
	_repeat(rule)


## Try / Except: the repeat in progress hit nothing. Refund it and try it again from the caster,
## as the same repeat (same loop index, so the cap and the damage falloff don't move).
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


## The loop rule that runs the next repeat, or null when every loop is done.
func _next_rule() -> ProgramRule:
	if current == root and not _late_fors.is_empty():
		for r in _late_fors:                     # the cast just landed: now they can be judged
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
		if _stopped.has(rule):
			continue
		match rule.loop.break_on:
			ProgramLoop.Break.KILL:
				if kills > 0:
					_stopped[rule] = true
			ProgramLoop.Break.MISS:
				if hits == 0:
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
			support.announce(current, r)          # spends Variable Store charge, quests, traits
			return r
	return null


func _repeat(rule: ProgramRule, retry := false) -> void:
	_current_rule = rule
	var child := SkillCast.new(root.caster, root.skill, root.stats, root.behavior)
	child.depth = 1                              # on-kill and echo supports leave repeats alone
	child.flag_bonus = root.flag_bonus.duplicate()
	child.damage_mult = root.damage_mult * pow(ProgramLoop.FALLOFF, index)
	child.extra = root.extra.duplicate()
	child.extra["loop_index"] = index
	child.extra["loop_repeat"] = true
	child.extra["loop_retry"] = retry            # except missed:
	for t in last_targets:
		if not (t in _hit_so_far):
			_hit_so_far.append(t)
	child.extra["loop_hit_so_far"] = _hit_so_far.duplicate()     # Pointer looks for someone new
	support.apply_repeat_rules(child, rule)      # loop == N, stack_overflow... and the loop body
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
