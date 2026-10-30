class_name SkillCast
extends RefCounted
## Everything about ONE use of a skill: who cast it, which skill, the stats it was cast with,
## and anything that has to be remembered while its projectiles are still flying.
##
## SkillBehavior and SkillInstance are shared between casts, so per-cast state goes here,
## never on the behavior. Bind the cast into callbacks instead of caster/skill/stats:
##     projectile.hit_enemy.connect(_on_hit_enemy.bind(cast))
## and check cast.is_valid() first in the callback, because the caster may have died since.

var caster: Node3D
var skill: SkillInstance
## The effective stats: the caster's final stats with the gem's and supports' modifiers on top.
var stats: StatComponent
var behavior: SkillBehavior
## 0 = a real cast. 1+ = a cast a support triggered (an explosion on kill, a chain...).
## Supports check it so triggered hits don't trigger themselves forever.
var depth := 0
## Targets this cast has already damaged.
var already_hit: Array = []
## Free space for supports and behaviors (chain count left, a spawned zone, ...).
var extra: Dictionary = {}
## Per-cast flag changes (from conditional program rules). Added on top of the skill's flags,
## only for this cast, so they never leak into the next one.
var flag_bonus: Dictionary = {}
## Per-cast damage multiplier (from conditional program rules). Applied in SkillBehavior.hit().
var damage_mult := 1.0


func _init(p_caster: Node3D, p_skill: SkillInstance, p_stats: StatComponent,
		p_behavior: SkillBehavior) -> void:
	caster = p_caster
	skill = p_skill
	stats = p_stats
	behavior = p_behavior


## False once the caster or its stats have been freed (enemy died, area changed).
func is_valid() -> bool:
	return is_instance_valid(caster) and is_instance_valid(stats)


## A flag from the gem, summed with its supports' flag modifiers and this cast's flag_bonus.
func flag(key: String) -> float:
	return skill.get_flag(key) + flag_bonus.get(key, 0.0)


## Melee reach in metres: the caster's ATTACK_RANGE plus this cast's "range_bonus" flag.
func melee_range() -> float:
	return maxf(stats.get_stat(StatTypes.Stat.ATTACK_RANGE) + flag("range_bonus"), 0.0)


## Damage a target with this cast. See SkillBehavior.hit().
func hit(target: Node, damage_mult := 1.0) -> HitInfo:
	return behavior.hit(self, target, damage_mult)


## A new cast for a follow-up effect (explosion, chain). Same skill and stats, one level deeper.
func spawn_child() -> SkillCast:
	var child := SkillCast.new(caster, skill, stats, behavior)
	child.depth = depth + 1
	child.already_hit = already_hit.duplicate()
	child.flag_bonus = flag_bonus.duplicate()
	child.damage_mult = damage_mult
	return child


## Flat facing direction of the caster (+Z, the convention all behaviors use).
func forward() -> Vector3:
	return SkillDeliveries.forward(caster)


## Where effects and projectiles should be added: next to the caster, inside the 3D world.
func effect_parent() -> Node:
	return caster.get_parent()
