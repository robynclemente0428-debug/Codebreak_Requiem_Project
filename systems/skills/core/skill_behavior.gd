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
## Defensive flags (the DEFENSE knobs in skill scripts, data/skill_programs/defense_knobs.tres):
##   leech          share of the damage each hit deals that heals the caster (0.04 = 4%)
##   barrier        a shield worth this share of the caster's max life on every cast (0.03 = 3%),
##                  for BARRIER_SECONDS
##   guard          share of damage taken removed for the length of the cast (0.1 = 10%)

const BARRIER_SECONDS := 4.0
const GUARD_MIN_SECONDS := 0.6
const GUARD_MAX_SECONDS := 2.0          # slow skills (or no weapon: 0 attack speed) can't guard forever


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
	_apply_defense(cast)
	release(cast)


## Barrier and guard from the cast's flags (after the supports, so WHEN rules count).
## Only the original cast: echoes, repeats and holograms don't shield you again.
func _apply_defense(cast: SkillCast) -> void:
	if cast.depth > 0 or cast.extra.get("hologram", false):
		return
	var hp := cast.caster.get("health") as HealthComponent
	if hp == null:
		return
	var barrier := cast.flag("barrier")
	if barrier > 0.0 and hp.stats != null:
		hp.add_barrier(barrier * hp.stats.get_stat(StatTypes.Stat.MAX_HEALTH), BARRIER_SECONDS)
	var guard := cast.flag("guard")
	if guard > 0.0:
		hp.add_guard(guard, clampf(recovery_time(cast), GUARD_MIN_SECONDS, GUARD_MAX_SECONDS))


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
	if cast.caster.get("is_remote") == true:        # co-op: a remote copy's cast is for show,
		return info                                 # its owner's machine deals the damage
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
	var traits: Array = target.get("traits") if "traits" in target else []   # Firewalled, Reflector...
	var on_copy: bool = target.get("is_remote") == true and target is EnemyBase    # co-op: the host's enemy
	if not traits.is_empty() or on_copy:
		info.facts = HitFacts.from_cast(cast)       # what the traits may know about the hit (they never read cast)
	if on_copy:
		Coop.hit_facts = info.facts                 # sent with the hit: the host's traits judge it,
		traits = []                                 # not this copy's (see Coop._e_hit)
	for t: EnemyTrait in traits:
		t.modify_incoming(info)
	if info.cancelled:
		return info
	if info.absorbed:               # a boss lock took it: it landed, for nothing
		if target_health.current_health <= 0.0:
			return info
		info.landed = true
		cast.already_hit.append(target)
		for t: EnemyTrait in traits:
			if is_instance_valid(t):
				t.after_hit(info)
		for s in cast.skill.support_behaviors:
			s.on_hit(cast, target, info)
		return info
	var own: Array = cast.caster.get("traits") if "traits" in cast.caster else []   # HandshakeLock
	for t: EnemyTrait in own:
		if is_instance_valid(t):
			t.on_outgoing(info)

	# Co-op: a real hit (a player's or an enemy's skill), sent on to whoever owns the target
	Coop.hit_source = Coop.Hit.PLAYER if cast.caster is Player else Coop.Hit.ENEMY
	Coop.damage_by = Coop.my_id() if cast.caster is Player and Coop.in_game else 0   # our own hit (DamageNumbers)
	info.dealt = target_health.take_damage(info.damage)
	Coop.damage_by = 0
	Coop.hit_source = Coop.Hit.NONE
	Coop.hit_facts = null
	if info.dealt <= 0.0:
		return info                 # the hit didn't land (target already dead)
	info.landed = true
	info.killed = target_health.current_health <= 0.0
	Coop.my_hit(target, cast, info)     # co-op client: the host says later how it landed (Coop._e_landed)
	cast.already_hit.append(target)
	for t: EnemyTrait in traits:
		if is_instance_valid(t):
			t.after_hit(info)

	# Co-op, a hit on the host's enemy: its lock may yet absorb it, so what a landed hit gives
	# waits for the host's word (Coop._e_landed calls landing_rewards then, with the host's damage)
	if not target.is_in_group(&"breakables") and not on_copy:   # barrels don't feed life / mana on hit
		landing_rewards(cast, info)

	for s in cast.skill.support_behaviors:
		s.on_hit(cast, target, info)
		if info.killed:
			s.on_kill(cast, target, info)
	return info


## What a hit that really landed gives its caster: life and mana on hit, leech (of info.dealt),
## and a per-hit rule's barrier and guard. An absorbed hit gives none of it. (Co-op: Coop._e_landed.)
func landing_rewards(cast: SkillCast, info: HitInfo) -> void:
	if not cast.is_valid():
		return
	_apply_on_hit_stats(cast)
	var leech := cast.flag("leech") + info.leech_bonus      # + a per-hit rule's leech
	var caster_hp := cast.caster.get("health") as HealthComponent
	if leech > 0.0 and caster_hp != null:
		caster_hp.heal(info.dealt * leech)
	if caster_hp != null:                       # barrier / guard from a per-hit rule, on landing
		if info.barrier_bonus > 0.0 and caster_hp.stats != null:
			caster_hp.add_barrier(info.barrier_bonus * caster_hp.stats.get_stat(StatTypes.Stat.MAX_HEALTH), BARRIER_SECONDS)
		if info.guard_bonus > 0.0:
			caster_hp.add_guard(info.guard_bonus, clampf(recovery_time(cast), GUARD_MIN_SECONDS, GUARD_MAX_SECONDS))


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
