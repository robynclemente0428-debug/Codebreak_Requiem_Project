class_name SupportBehavior
extends RefCounted
## Base class for support gems that change what a skill DOES, not just its numbers.
## Number-only supports (Cleave, Many Projectiles) don't need a script: their stat_modifiers and
## flag_modifiers are enough. Give a SupportGemDefinition a behavior_script when it needs a new rule.
##
## Override only the hooks you need. Tuning values should be flags (set in SkillGemRegistry's
## _support_flag_modifiers) and read with cast.flag("..."), so other supports can change them too.
##
## SkillInstance makes one instance per socketed support, so don't keep per-cast state here:
## put it in cast.extra.

## The SupportGemDefinition this script belongs to.
var definition: SupportGemDefinition


## Once per cast, after the animation's impact frame and before the skill's release().
func before_release(_cast: SkillCast) -> void:
	pass


## Before damage is applied. Change hit.damage, or set hit.cancelled = true.
func modify_hit(_cast: SkillCast, _target: Node, _hit: HitInfo) -> void:
	pass


## After damage landed on a target.
func on_hit(_cast: SkillCast, _target: Node, _hit: HitInfo) -> void:
	pass


## After a hit from this skill killed its target (called right after on_hit).
func on_kill(_cast: SkillCast, _target: Node, _hit: HitInfo) -> void:
	pass


## After an area skill's explosion (Blast) hit everything it was going to hit.
## `direction` is the way the shot was travelling (flat).
func on_area_impact(_cast: SkillCast, _center: Vector3, _direction: Vector3) -> void:
	pass


## Attack speed multiplier for the next cast of this skill (Overclock). 1.0 = unchanged.
## Applied to the cooldown and the animation, before the cast starts.
func speed_mult(_skill: SkillInstance) -> float:
	return 1.0


## Before a loop repeat of a projectile skill (Blast) is fired from the caster. Change the shot
## in `aim`:
##   "from"       Vector3  where the shot starts (the caster)
##   "direction"  Vector3  flat direction it flies (where the caster faces)
##   "range"      float    how far it flies
##   "seek_from"  Vector3  where the last shot exploded (the caster if it never did)
## Pointer aims repeats at the next enemy here.
func aim_repeat(_cast: SkillCast, _aim: Dictionary) -> void:
	pass
