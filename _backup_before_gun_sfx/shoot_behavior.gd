class_name ShootBehavior
extends SkillBehavior
## Fires fast bullets from a rifle or sniper. Each bullet damages the enemies it passes through.
## Flags (set per gem in SkillGemRegistry, changeable by supports through flag_modifiers):
##   max_projectiles  how many bullets one cast fires (1 = a single shot)
##   spread_angle     degrees between neighbouring bullets, so more bullets = wider fan
##   speed            bullet speed in metres per second
##   range            how far a bullet flies before it disappears
##   pierce           extra enemies a bullet passes through (0 = stops at the first)
##   pierce_falloff   damage lost per enemy already pierced (0.2 = 20% less each time)
##   spawn_height     metres above the caster's feet where it starts
##   spawn_forward    metres in front of the caster where it starts
##   recovery_mult    how much longer than a normal attack the cast takes
## Fork support (fork_count > 0): a bullet that hits its first enemy splits into fork_count
## bullets, fork_angle degrees apart, flying on from that enemy for fork_damage of the damage.
## Forked bullets don't fork again. Their cast has extra["forked"] = true, and the script's
## WHEN forked rules apply to it (ProgramSupport.apply_fork_rules).

## Hits count from this far above the caster's feet up to the bullet (floor never counts).
const FLOOR_CLEARANCE := 0.2
const PROJECTILE_SCENE := preload("res://systems/skills/scenes/shoot/shoot_projectile.tscn")

func release(cast: SkillCast) -> void:
	var shot := _origin_and_aim(cast.caster, cast.flag("spawn_height"), cast.flag("spawn_forward"))
	var directions := SkillDeliveries.fan_directions(shot[1],
			int(cast.flag("max_projectiles")), cast.flag("spread_angle"))
	for direction in directions:
		_spawn_projectile(cast, shot[0], direction)
	MuzzleFlash.spawn(cast.effect_parent(), shot[0], shot[1])    # one flash, however many bullets


## [origin, flat direction] of the next shot.
## The player's bullets come out of the gun's barrel (enemies and holograms keep the default).
func _origin_and_aim(caster: Node3D, spawn_height: float, spawn_forward: float) -> Array:
	var origin := SkillDeliveries.spawn_point(caster, spawn_height, spawn_forward)
	var aim := SkillDeliveries.forward(caster)
	if caster.has_method("get_muzzle_point"):
		var muzzle = caster.get_muzzle_point()
		if muzzle is Vector3:
			origin = muzzle
			# From the shoulder, fire at the aim point so the shot crosses the cursor
			if caster.has_method("get_aim_point"):
				var to: Vector3 = (caster.get_aim_point() as Vector3) - origin
				to.y = 0.0
				if to.length() > 0.5:
					aim = to.normalized()
	return [origin, aim]


func aim_preview(caster: Node3D, skill: SkillInstance) -> Array:
	var shot := _origin_and_aim(caster, skill.get_flag("spawn_height"), skill.get_flag("spawn_forward"))
	var out := []
	for d in SkillDeliveries.fan_directions(shot[1], int(skill.get_flag("max_projectiles")),
			skill.get_flag("spread_angle")):
		out.append({"from": shot[0], "direction": d, "range": skill.get_flag("range"),
				"radius": 0.0, "pierce": int(skill.get_flag("pierce"))})
	return out


func _spawn_projectile(cast: SkillCast, origin: Vector3, direction: Vector3,
		exclude: Array[RID] = [], max_distance := -1.0) -> void:
	var caster := cast.caster
	var projectile := PROJECTILE_SCENE.instantiate() as ShootProjectile
	projectile.direction = direction
	projectile.speed = cast.flag("speed")
	projectile.max_distance = cast.flag("range") if max_distance < 0.0 else max_distance
	projectile.pierce = maxi(int(cast.flag("pierce")), 0)
	# Fired from the gun at chest height: still hit barrels and short enemies under the shot
	projectile.floor_y = caster.global_position.y + FLOOR_CLEARANCE
	# Enemy bullets hit players and ignore other enemies, like Blast does.
	projectile.enemy_group = SkillTargets.target_group(caster)
	projectile.hit_mask = SkillTargets.projectile_mask(caster, projectile.hit_mask)
	if not exclude.is_empty():
		projectile.exclude = exclude.duplicate()       # a fork skips what its parent already hit
	elif caster is CollisionObject3D:
		projectile.exclude = [caster.get_rid()]          # never hit the caster itself

	# Add it next to the caster, NOT to current_scene: the 3D world lives inside a SubViewport.
	cast.effect_parent().add_child(projectile)
	projectile.global_position = origin

	# Signal arguments come first, then the values bound here.
	projectile.hit_enemy.connect(_on_hit_enemy.bind(projectile, cast))
	projectile.hit_world.connect(_on_hit_world.bind(cast))


func _on_hit_enemy(target: Node, position: Vector3, pierced_so_far: int,
		projectile: ShootProjectile, cast: SkillCast) -> void:
	if not cast.is_valid() or not is_instance_valid(target):
		return
	# Each enemy already pierced makes the bullet weaker: 20% falloff -> 100%, 80%, 64%, ...
	var keep := maxf(1.0 - cast.flag("pierce_falloff"), 0.0)
	ImpactEffect.spawn(cast.effect_parent(), position, 0.3, Color(1.0, 0.85, 0.4))
	cast.hit(target, pow(keep, pierced_so_far))
	# A per-hit rule may just have raised pierce for this cast (Assassin: WHEN target life < X ->
	# pierce +1). The bullet only decides whether to stop after this returns, so it can still
	# pick that up and fly on.
	if is_instance_valid(projectile):
		projectile.pierce = maxi(projectile.pierce, int(cast.flag("pierce")))
	if pierced_so_far == 0 and cast.flag("fork_count") >= 1.0 and not cast.extra.get("forked", false) \
			and not target.is_in_group(&"breakables") and is_instance_valid(projectile):
		_fork(cast, projectile, position)


## Splits a bullet where it hit its first enemy (Fork support).
func _fork(cast: SkillCast, projectile: ShootProjectile, at: Vector3) -> void:
	var child := cast.spawn_child()
	child.extra = cast.extra.duplicate()
	child.extra["forked"] = true
	child.damage_mult *= maxf(cast.flag("fork_damage"), 0.0)
	for s in cast.skill.support_behaviors:
		if s is ProgramSupport:
			(s as ProgramSupport).apply_fork_rules(child)       # WHEN forked: ...
	var reach := maxf(projectile.max_distance - projectile.travelled(), cast.flag("range") * 0.5)
	var dirs := SkillDeliveries.fan_directions(projectile.direction,
			int(round(child.flag("fork_count"))), child.flag("fork_angle"))
	ImpactEffect.spawn(cast.effect_parent(), at, 0.45, Color(0.4, 0.95, 1.0))
	for d in dirs:
		_spawn_projectile(child, at, d, projectile.exclude, reach)


func _on_hit_world(position: Vector3, cast: SkillCast) -> void:
	if cast.is_valid():
		ImpactEffect.spawn(cast.effect_parent(), position, 0.25, Color(0.8, 0.8, 0.8))
