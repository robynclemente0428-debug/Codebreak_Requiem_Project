class_name SkillBehavior
extends RefCounted
## Base class for every skill script (SlamBehavior, BlastBehavior, ...).
##
## One cast runs like this:
##   execute()        plays the animation and waits for the impact frame (shared, don't override)
##   before_release   every scripted support gets a look at the cast first
##   release()        YOUR skill: find targets, spawn projectiles, then call cast.hit(target)
##   hit()            rolls damage, runs the support hooks, applies damage + life/mana on hit
##
## A new skill only needs:
##     class_name MySkillBehavior
##     extends SkillBehavior
##     func release(cast: SkillCast) -> void:
##         for target in SkillDeliveries.hits_in_circle(cast, cast.caster.global_position, 3.0, 5):
##             cast.hit(target)
##
## Flags every skill understands (set per gem in SkillGemRegistry):
##   recovery_mult  how much longer than a normal attack the cast takes (minimum 1)
##   combo_grace    extra seconds before an animation combo restarts from the first clip


## Called by SkillInstance.cast(). `stats` are the effective stats (caster + gem + supports).
func execute(caster: Node3D, skill: SkillInstance, stats: StatComponent) -> void:
	var cast := SkillCast.new(caster, skill, stats, self)
	var delay := _play_animation(cast)
	if delay > 0.0:
		# Wait for the impact / release frame of the animation
		await caster.get_tree().create_timer(delay).timeout
		# The caster may have been freed, or killed, during the wind-up: then the skill never
		# fires. (Projectiles already in flight still land; this only stops new releases.)
		if not cast.is_valid() or is_dead(cast.caster):
			return
	if is_dead(caster):
		return
	for s in skill.support_behaviors:
		s.before_release(cast)
	release(cast)


## True when this node has a HealthComponent at 0 life (a dead enemy or player).
static func is_dead(node: Node) -> bool:
	if not is_instance_valid(node):
		return true
	var h = node.get("health")
	return h is HealthComponent and h.current_health <= 0.0


## Override this in each skill.
func release(_cast: SkillCast) -> void:
	push_error("%s: release() not implemented" % get_script().resource_path)


## A loop repeat of a cast that already landed (see ProgramLoopRunner). `from_impact` is where
## the last iteration exploded (Vector3, or null), `direction` the way it was going.
## By default the skill simply releases again from the caster: Strike swings again, Slam slams
## again, Shoot fires again, Blast fires another shot. Override for a different look.
func repeat_release(cast: SkillCast, _from_impact: Variant, _direction: Vector3) -> void:
	release(cast)


## Where this skill's shots would go if cast right now, for the aim line (AimLine). One entry per
## projectile: {"from": Vector3, "direction": Vector3 (flat), "range": float, "radius": float
## (explosion radius, 0 = none), "pierce": int}. Empty = not a ranged skill (no line).
## Uses the gem's flags without per-cast bonuses, so WHEN rules don't show.
func aim_preview(_caster: Node3D, _skill: SkillInstance) -> Array:
	return []


## True when an iteration only ends at its impact (ProgramSupport.on_area_impact), so a loop
## waits for the explosion before repeating. False = repeat after a short gap.
func waits_for_impact() -> bool:
	return false


## Seconds the cast takes, before attack speed. Same maths SkillInstance.get_cooldown() uses.
func recovery_time(cast: SkillCast) -> float:
	var recovery := maxf(cast.flag("recovery_mult"), 1.0)
	return recovery / maxf(cast.stats.get_stat(StatTypes.Stat.ATTACK_SPEED) * cast.skill.speed_mult(), 0.1)


## Plays the next clip of the gem's combo. Returns the seconds until the hit frame (0 = no animation).
func _play_animation(cast: SkillCast) -> float:
	var caster := cast.caster
	if not caster.has_method("play_skill_animation"):
		return 0.0
	var cooldown := recovery_time(cast)
	var key := cast.skill.peek_animation_key(cooldown + cast.flag("combo_grace"))
	var delay: float = caster.play_skill_animation(key, cooldown)
	if delay > 0.0:
		cast.skill.advance_animation()
	return delay


## Every skill damages targets through this (usually via cast.hit(target)), so support gems and
## on-hit stats apply to all skills. damage_mult scales the rolled damage (pierce falloff, etc.).
func hit(cast: SkillCast, target: Node, damage_mult := 1.0) -> HitInfo:
	var info := HitInfo.new()
	info.cast = cast
	info.target = target
	if not cast.is_valid() or not is_instance_valid(target):
		return info
	var target_health := target.get("health") as HealthComponent
	if target_health == null:
		return info
	if target is Node3D:
		info.position = (target as Node3D).global_position
	info.damage = cast.skill.roll_damage(cast.stats) * damage_mult * cast.damage_mult
	if cast.skill.class_trait != null:
		info.damage *= cast.skill.class_trait.hit_damage_mult(cast.caster, target)   # Rogue: moving, Assassin: full life
	info.is_crit = cast.skill.last_roll_was_crit

	for s in cast.skill.support_behaviors:
		s.modify_hit(cast, target, info)
	if info.cancelled:
		return info

	info.dealt = target_health.take_damage(info.damage)
	if info.dealt <= 0.0:
		return info                 # the hit didn't land (target already dead)
	info.landed = true
	info.killed = target_health.current_health <= 0.0
	cast.already_hit.append(target)

	if not target.is_in_group(&"breakables"):      # barrels don't feed life / mana on hit
		_apply_on_hit_stats(cast)

	for s in cast.skill.support_behaviors:
		s.on_hit(cast, target, info)
		if info.killed:
			s.on_kill(cast, target, info)
	return info


func _apply_on_hit_stats(cast: SkillCast) -> void:
	var caster := cast.caster
	# Life on hit
	var life_on_hit := cast.stats.get_stat(StatTypes.Stat.LIFE_ON_HIT)
	if life_on_hit > 0.0:
		var caster_health := caster.get("health") as HealthComponent
		if caster_health != null:
			caster_health.heal(life_on_hit)

	# Mana on hit
	var mana_on_hit := cast.stats.get_stat(StatTypes.Stat.MANA_ON_HIT)
	if mana_on_hit > 0.0:
		var caster_mana := caster.get("mana") as ManaComponent
		if caster_mana != null:
			caster_mana.gain_on_hit(mana_on_hit)
