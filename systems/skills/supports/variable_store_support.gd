class_name VariableStoreSupport
extends SupportBehavior
## Blast only.  charge += hits;  if (charge >= N) { spend(N); boost(); }
## Every enemy the skill hits stores +var_store_gain charge (up to var_store_max). The charge is
## kept between casts. On its own it does nothing: you spend it with the condition block
##     WHEN charge >= N   (ChargeAtLeastCondition, only with this gem)
## When a rule with it fires, N charge is used up, and the rule's effects are x(1 + 0.25 x N)
## stronger than their knob steps (EFFECT_PER_CHARGE). So a script like
##     WHEN charge >= 6  ->  projectiles += 2, radius += 1 m     (x2.5: +5 projectiles, +2.5 m)
## builds up over a few casts and then lets one big Blast go.
## Flags (SkillGemRegistry._support_flag_modifiers, scriptable through the knobs):
##   var_store_gain   charge per enemy hit
##   var_store_max    the most charge it can hold
##
## The charge lives on the character (per skill gem), so it survives re-socketing and is shared
## with Multicast holograms. The skill bar shows it on the skill's slot.

const META_PREFIX := "variable_store_"
## Spending charge makes the rule hit harder: its effects are x(1 + this x N) for
## WHEN charge >= N (N = 4 -> x2.0, N = 10 -> x3.5). Additive, so saving up stays sane.
const EFFECT_PER_CHARGE := 0.25


func on_hit(cast: SkillCast, target: Node, _hit: HitInfo) -> void:
	if target.is_in_group(&"breakables"):
		return                                     # barrels don't count
	var owner := owner_of(cast.caster)
	if owner == null:
		return
	var cap := int(cast.flag("var_store_max"))
	var now := read(owner, cast.skill)
	if now < cap:
		owner.set_meta(_key(cast.skill), mini(now + maxi(int(cast.flag("var_store_gain")), 1), cap))


## The character whose charge this is (a Multicast hologram stores on its owner).
static func owner_of(caster: Node) -> Node:
	if not is_instance_valid(caster):
		return null
	var src = caster.get("source")
	return src if src is Node and is_instance_valid(src) else caster


static func read(caster: Node, skill: SkillInstance) -> int:
	var owner := owner_of(caster)
	if owner == null or skill == null or skill.gem == null:
		return 0
	return int(owner.get_meta(_key(skill), 0))


static func spend(caster: Node, skill: SkillInstance, amount: int) -> void:
	var owner := owner_of(caster)
	if owner == null or skill == null or skill.gem == null:
		return
	owner.set_meta(_key(skill), maxi(read(owner, skill) - amount, 0))


## The effect multiplier for a rule that spends charge (1.0 for any other rule).
static func rule_effect_mult(rule: ProgramRule) -> float:
	var mult := 1.0
	for c in rule.conditions:
		if c is ChargeAtLeastCondition:
			mult *= 1.0 + EFFECT_PER_CHARGE * (c as ChargeAtLeastCondition).n
	return mult


## Whether a skill has this support socketed (the skill bar asks, to show the counter).
static func on_skill(skill: SkillInstance) -> bool:
	if skill == null:
		return false
	for s in skill.support_behaviors:
		if s is VariableStoreSupport:
			return true
	return false


static func _key(skill: SkillInstance) -> String:
	return META_PREFIX + String(skill.gem.id)
