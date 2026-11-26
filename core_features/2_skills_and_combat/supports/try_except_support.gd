class_name TryExceptSupport
extends SupportBehavior

const META_STACKS := "try_except_stacks_"
const META_MISSED := "try_except_missed_"
const COL_ERROR := Color(1.0, 0.35, 0.35)
const COL_HANDLED := Color(0.4, 1.0, 0.6)


func modify_hit(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	if not _counts(cast) or target.is_in_group(&"breakables"):
		return
	var stacks := stacks_of(cast.caster, cast.skill)
	if stacks <= 0:
		return
	hit.damage *= 1.0 + hit.flag("except_stack_damage") * stacks
	cast.extra["except_handled"] = stacks


func on_hit(cast: SkillCast, target: Node, _hit: HitInfo) -> void:
	if _counts(cast) and not target.is_in_group(&"breakables"):
		cast.extra["except_hits"] = int(cast.extra.get("except_hits", 0)) + 1


func on_area_impact(cast: SkillCast, center: Vector3, _direction: Vector3) -> void:
	if not _counts(cast):
		return
	var hits := int(cast.extra.get("except_hits", 0))
	cast.extra["except_hits"] = 0
	var owner := VariableStoreSupport.owner_of(cast.caster)
	if owner == null:
		return
	var key := String(cast.skill.gem.id)
	if hits > 0:
		owner.set_meta(META_MISSED + key, false)
		var handled := int(cast.extra.get("except_handled", 0))
		if handled > 0 and stacks_of(owner, cast.skill) > 0:
			owner.set_meta(META_STACKS + key, 0)
			_pop(cast, center, "HANDLED x%d" % handled, COL_HANDLED)
		return
	owner.set_meta(META_MISSED + key, true)
	var mana := cast.caster.get("mana") as ManaComponent
	if mana != null:
		var shots := maxf(cast.flag("max_projectiles"), 1.0)
		mana.restore(cast.skill.get_mana_cost() * clampf(cast.flag("except_refund"), 0.0, 1.0) / shots)
	var cap := int(round(cast.flag("except_max_stacks")))
	var now := stacks_of(owner, cast.skill)
	if now < cap:
		owner.set_meta(META_STACKS + key, now + 1)
		_pop(cast, center, "EXCEPTION %d/%d" % [now + 1, cap], COL_ERROR)


static func _counts(cast: SkillCast) -> bool:
	return cast.depth == 0 and not cast.extra.get("hologram", false)


static func stacks_of(caster: Node, skill: SkillInstance) -> int:
	var owner := VariableStoreSupport.owner_of(caster)
	if owner == null or skill == null or skill.gem == null:
		return 0
	return int(owner.get_meta(META_STACKS + String(skill.gem.id), 0))


static func last_missed(caster: Node, skill: SkillInstance) -> bool:
	var owner := VariableStoreSupport.owner_of(caster)
	if owner == null or skill == null or skill.gem == null:
		return false
	return bool(owner.get_meta(META_MISSED + String(skill.gem.id), false))


static func on_skill(skill: SkillInstance) -> bool:
	if skill == null:
		return false
	for s in skill.support_behaviors:
		if s is TryExceptSupport:
			return true
	return false


static func _pop(cast: SkillCast, at: Vector3, text: String, color: Color) -> void:
	if cast.caster.is_in_group("players"):
		cast.caster.get_tree().call_group("damage_numbers", "pop_text", at + Vector3.UP * 1.4, text, color)
