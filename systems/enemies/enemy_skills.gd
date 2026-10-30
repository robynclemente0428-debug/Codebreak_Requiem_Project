class_name EnemySkills
extends Node
## Lets an enemy use the same skill gems as the player (Slam, Blast, Strike, Shoot...).
## EnemySpawner adds one to every enemy whose EnemyDefinition lists skills.
##
## Every check_interval seconds it looks for the nearest player. If a skill is off cooldown and
## the player is inside its reach, the enemy turns toward the player and casts it, exactly like
## the player's own skills: SkillInstance.cast() runs the same behavior script.

@export var check_interval: float = 0.25
## Minimum seconds before the SAME skill can be used again, on top of its own recovery time.
@export var skill_cooldown: float = 6.0
## Random extra seconds added to that cooldown, so a group of enemies doesn't slam in unison.
@export var cooldown_jitter: float = 2.0
## Skills with a long reach (projectiles) only start from this distance or closer.
@export var max_cast_distance: float = 12.0
@export var cast_lock_fraction: float = 1.0
var _caster: Node3D
var _stats: StatComponent
var _skills: Array[SkillInstance] = []
var _ready_at: Dictionary = {}         # SkillInstance -> time in ms when it may be used again
var _busy_until := 0                   # ms: no other cast while one is in progress
var _timer := 0.0


## `gems` is an Array of SkillGemDefinition (the same resources the player's gems hold).
## `supports` link to every skill they fit; `support_ids` maps a skill gem id to extra
## support ids for that skill only (see EnemyDefinition.skill_supports / skill_support_ids).
func setup(caster: Node3D, stats: StatComponent, gems: Array,
		flag_overrides: Dictionary = {}, supports: Array = [], support_ids: Dictionary = {}) -> void:
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
		skill.rebuild()                          # rebuild() skips supports that don't fit the gem
		_skills.append(skill)
		# Stagger the first use so a fresh spawn doesn't open with an instant slam
		_ready_at[skill] = Time.get_ticks_msec() + int(randf_range(1.0, 3.0) * 1000.0)
		print("[EnemySkills] gem=%s overrides=%s supports=%s" % [gem.id, flag_overrides.get(gem.id, "NONE"),
				skill.supports.map(func(s: SupportGemDefinition) -> String: return s.id)])


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
	for skill in _skills:                                   # list order = priority
		if now < int(_ready_at.get(skill, 0)):
			continue
		if dist > minf(_reach(skill), max_cast_distance):
			continue
		_cast(skill, target, now)
		return


func _cast(skill: SkillInstance, target: Node3D, now: int) -> void:
	_face(target)
	var recovery := skill.get_cooldown(_stats)             # seconds the cast itself takes
	_busy_until = now + int(recovery * 1000.0)
	var wait := maxf(recovery, skill_cooldown) + randf_range(0.0, cooldown_jitter)
	_ready_at[skill] = now + int(wait * 1000.0)
	var ai = _caster.get("ai")
	if ai != null and "busy_time" in ai:
		ai.busy_time = recovery * cast_lock_fraction                   # the AI stands still for the cast
	skill.cast(_caster, _stats, null)                      # enemies have no mana


## Same convention as the player: the behaviors fire along the body's +Z.
func _face(target: Node3D) -> void:
	var to := target.global_position - _caster.global_position
	to.y = 0.0
	if to.length_squared() > 0.001:
		_caster.global_rotation.y = atan2(to.x, to.z)


## How far from the caster the skill can reach, read from the gem's own flags.
func _reach(skill: SkillInstance) -> float:
	var reach := skill.get_flag("radius") + skill.get_flag("center_offset")   # Slam
	reach = maxf(reach, skill.get_flag("range"))                              # Blast, Shoot
	if skill.get_flag("arc_angle") > 0.0:                                     # Strike
		reach = maxf(reach, skill.get_melee_range(_stats))
	return reach


## Only cast at whoever the AI is actually hunting, so skills respect aggro range and line of
## sight. Without an AI, fall back to the nearest player.
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
