class_name TryExceptSupport
extends SupportBehavior
## Blast only.  try { blast(); } except (Missed) { refund(); errors += 1; }
## A miss is caught instead of wasted, on every cast, no script needed:
##   A Blast whose explosion hits no enemy refunds its mana (except_refund of it) and stores an
##   ERROR stack (up to except_max_stacks). The next explosion that does hit handles them all:
##   +except_stack_damage per stack on everything it hits, then the stacks are cleared.
##   The cast right after a miss also counts for the  except missed:  block.
##   In a loop, a repeat that hits nothing is still refunded and retried as before
##   (ProgramLoopRunner does that part).
## Flags (SkillGemRegistry._support_flag_modifiers, scriptable through the knobs):
##   except_refund         share of the mana a missed cast gets back (1.0 = all of it)
##   except_max_stacks     the most ERROR stacks it holds
##   except_stack_damage   more damage per stack when they are handled (0.25 = +25%)
##   except_retries        loop repeats that may miss and be tried again, per cast
##
## Stacks live on the character (per skill gem), like Variable Store's charge, so they survive
## re-socketing and the skill bar can show them. Only the original cast counts: loop repeats,
## Multicast holograms and follow-up hits (Pointer hops, on-kill explosions) are left alone.

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
	hit.damage *= 1.0 + cast.flag("except_stack_damage") * stacks
	cast.extra["except_handled"] = stacks


func on_hit(cast: SkillCast, target: Node, _hit: HitInfo) -> void:
	if _counts(cast) and not target.is_in_group(&"breakables"):
		cast.extra["except_hits"] = int(cast.extra.get("except_hits", 0)) + 1


## After each explosion (one per projectile): did this one find an enemy?
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
	# Missed: catch it
	owner.set_meta(META_MISSED + key, true)
	var mana := cast.caster.get("mana") as ManaComponent
	if mana != null:
		var shots := maxf(cast.flag("max_projectiles"), 1.0)     # several projectiles share the cost
		mana.restore(cast.skill.get_mana_cost() * clampf(cast.flag("except_refund"), 0.0, 1.0) / shots)
	var cap := int(round(cast.flag("except_max_stacks")))
	var now := stacks_of(owner, cast.skill)
	if now < cap:
		owner.set_meta(META_STACKS + key, now + 1)
		_pop(cast, center, "EXCEPTION %d/%d" % [now + 1, cap], COL_ERROR)


## The original cast of a player's or enemy's Blast, not a repeat, hologram or follow-up hit.
static func _counts(cast: SkillCast) -> bool:
	return cast.depth == 0 and not cast.extra.get("hologram", false)


static func stacks_of(caster: Node, skill: SkillInstance) -> int:
	var owner := VariableStoreSupport.owner_of(caster)
	if owner == null or skill == null or skill.gem == null:
		return 0
	return int(owner.get_meta(META_STACKS + String(skill.gem.id), 0))


## True when this skill's last cast hit nothing (MissedCondition reads it).
static func last_missed(caster: Node, skill: SkillInstance) -> bool:
	var owner := VariableStoreSupport.owner_of(caster)
	if owner == null or skill == null or skill.gem == null:
		return false
	return bool(owner.get_meta(META_MISSED + String(skill.gem.id), false))


## Whether a skill has this support socketed (the skill bar asks, to show the stacks).
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
