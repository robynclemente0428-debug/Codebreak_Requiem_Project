class_name VariableStoreSupport
extends SupportBehavior

const META_PREFIX := "variable_store_"
const EFFECT_PER_CHARGE := 0.25


func on_hit(cast: SkillCast, target: Node, _hit: HitInfo) -> void:
	if target.is_in_group(&"breakables"):
		return
	var owner := owner_of(cast.caster)
	if owner == null:
		return
	var cap := int(cast.flag("var_store_max"))
	var now := read(owner, cast.skill)
	if now < cap:
		owner.set_meta(_key(cast.skill), mini(now + maxi(int(_hit.flag("var_store_gain")), 1), cap))


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


const CAPACITY_KNOB := &"store_capacity"


static func capacity_with(steps: int, knob: SkillKnob) -> int:
	var def: SupportGemDefinition = SkillGemRegistry.get_support_gem("variable_store_support")
	var base: float = def.flag_modifiers.get("var_store_max", 10.0) if def != null else 10.0
	return int(round(base + knob.value_for(steps)))


static func rule_effect_mult(rule: ProgramRule) -> float:
	var mult := 1.0
	for c in rule.conditions:
		if c is ChargeAtLeastCondition:
			mult *= 1.0 + EFFECT_PER_CHARGE * (c as ChargeAtLeastCondition).n
	return mult


static func on_skill(skill: SkillInstance) -> bool:
	if skill == null:
		return false
	for s in skill.support_behaviors:
		if s is VariableStoreSupport:
			return true
	return false


static func _key(skill: SkillInstance) -> String:
	return META_PREFIX + String(skill.gem.id)
