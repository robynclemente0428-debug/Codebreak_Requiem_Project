class_name EnemySkills
extends Node

@export var check_interval: float = 0.25
@export var skill_cooldown: float = 6.0
@export var cooldown_jitter: float = 2.0
@export var max_cast_distance: float = 12.0
@export var cast_lock_fraction: float = 1.0
var _caster: Node3D
var _stats: StatComponent
var _skills: Array[SkillInstance] = []
var _ready_at: Dictionary = {}
var _busy_until := 0
var _timer := 0.0


func setup(caster: Node3D, stats: StatComponent, gems: Array,
		flag_overrides: Dictionary = {}, supports: Array = [], support_ids: Dictionary = {},
		loops: Dictionary = {}) -> void:
	_caster = caster
	_stats = stats
	for gem in gems:
		if gem == null:
			continue
		var skill := SkillInstance.new()
		skill.gem = gem
		skill.flag_overrides = flag_overrides.get(gem.id, {})
		for sup in supports:
			if sup is SupportGemDefinition and sup not in skill.supports:
				skill.supports.append(sup)
		for id in support_ids.get(gem.id, []):
			var sup := SkillGemRegistry.get_support_gem(str(id))
			if sup == null:
				push_warning("EnemySkills: no support gem '%s' (for %s)" % [id, gem.id])
			elif sup not in skill.supports:
				skill.supports.append(sup)
		if int(loops.get(gem.id, 0)) > 0:
			_give_loop(skill, int(loops[gem.id]))
		skill.rebuild()
		_skills.append(skill)
		_ready_at[skill] = Time.get_ticks_msec() + int(randf_range(1.0, 3.0) * 1000.0)
		print("[EnemySkills] gem=%s overrides=%s supports=%s" % [gem.id, flag_overrides.get(gem.id, "NONE"),
				skill.supports.map(func(s: SupportGemDefinition) -> String: return s.id)])


func copy_skill(gem: SkillGemDefinition) -> void:
	if gem == null or (_skills.size() == 1 and _skills[0].gem == gem):
		return
	var skill := SkillInstance.new()
	skill.gem = gem
	skill.rebuild()
	_skills.clear()
	_ready_at.clear()
	_skills.append(skill)
	_ready_at[skill] = Time.get_ticks_msec() + 1500


func add_copied(skill: SkillInstance) -> void:
	if skill == null or skill in _skills:
		return
	_skills.push_front(skill)
	_ready_at[skill] = Time.get_ticks_msec() + 900


func stun(seconds: float) -> void:
	_busy_until = maxi(_busy_until, Time.get_ticks_msec() + int(seconds * 1000.0))


func _give_loop(skill: SkillInstance, repeats: int) -> void:
	var rule := ProgramRule.new()
	rule.loop = ProgramLoop.make(ProgramLoop.Mode.FOR, repeats)
	var program := SkillProgram.new()
	program.rules.append(rule)
	skill.program = program
	skill.rank = Ranks.LADDER.size() - 1
	skill.bonus_points = 100.0


func _process(delta: float) -> void:
	if _skills.is_empty() or not is_instance_valid(_caster):
		return
	_timer += delta
	if _timer < check_interval:
		return
	_timer = 0.0

	var now := Time.get_ticks_msec()
	if now < _busy_until or _is_dead():
		return
	var target := _pick_target()
	if target == null:
		return

	var dist := _flat_distance(target)
	for skill in _skills:
		if now < int(_ready_at.get(skill, 0)):
			continue
		if dist > minf(_reach(skill), max_cast_distance):
			continue
		_cast(skill, target, now)
		return


func _cast(skill: SkillInstance, target: Node3D, now: int) -> void:
	_face(target)
	var recovery := skill.get_cooldown(_stats)
	_busy_until = now + int(recovery * 1000.0)
	var wait := maxf(recovery, skill_cooldown) + randf_range(0.0, cooldown_jitter)
	_ready_at[skill] = now + int(wait * 1000.0)
	var ai = _caster.get("ai")
	if ai != null and "busy_time" in ai:
		ai.busy_time = recovery * cast_lock_fraction
	Coop.enemy_cast(_caster, _skills.find(skill), String(skill.gem.id))
	skill.cast(_caster, _stats, null)


func remote_cast(index: int, gem_id: String, facing: float) -> void:
	if not is_instance_valid(_caster) or _is_dead():
		return
	var skill := _remote_skill(index, gem_id)
	if skill == null:
		return
	_caster.global_rotation.y = facing
	skill.cast(_caster, _stats, null)


var _borrowed: Dictionary = {}


func _remote_skill(index: int, gem_id: String) -> SkillInstance:
	if index >= 0 and index < _skills.size() and String(_skills[index].gem.id) == gem_id:
		return _skills[index]
	for s in _skills:
		if String(s.gem.id) == gem_id:
			return s
	if _borrowed.has(gem_id):
		return _borrowed[gem_id]
	var gem := SkillGemRegistry.get_skill_gem(gem_id)
	if gem == null:
		return null
	var skill := SkillInstance.new()
	skill.gem = gem
	skill.rebuild()
	_borrowed[gem_id] = skill
	return skill


func _face(target: Node3D) -> void:
	var to := target.global_position - _caster.global_position
	to.y = 0.0
	if to.length_squared() > 0.001:
		_caster.global_rotation.y = atan2(to.x, to.z)


func _reach(skill: SkillInstance) -> float:
	var reach := skill.get_flag("radius") + skill.get_flag("center_offset")
	reach = maxf(reach, skill.get_flag("range"))
	if skill.get_flag("arc_angle") > 0.0:
		reach = maxf(reach, skill.get_melee_range(_stats))
	return reach


func _pick_target() -> Node3D:
	var ai = _caster.get("ai")
	if ai != null:
		var t = ai.target
		return t as Node3D if is_instance_valid(t) else null
	return _nearest_player()


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var n := p as Node3D
		if n == null:
			continue
		var d := _flat_distance(n)
		if d < best_d:
			best_d = d
			best = n
	return best


func _flat_distance(target: Node3D) -> float:
	var d := target.global_position - _caster.global_position
	return Vector2(d.x, d.z).length()


func _is_dead() -> bool:
	var h = _caster.get("health")
	return h is HealthComponent and h.current_health <= 0.0
