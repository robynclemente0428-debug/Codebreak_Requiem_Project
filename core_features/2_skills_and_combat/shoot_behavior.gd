class_name ShootBehavior
extends SkillBehavior

const FLOOR_CLEARANCE := 0.2
const PROJECTILE_SCENE := preload("res://systems/skills/scenes/shoot/shoot_projectile.tscn")

func release(cast: SkillCast) -> void:
	var shot := _origin_and_aim(cast.caster, cast.flag("spawn_height"), cast.flag("spawn_forward"))
	var directions := SkillDeliveries.fan_directions(shot[1],
			int(cast.flag("max_projectiles")), cast.flag("spread_angle"))
	for direction in directions:
		_spawn_projectile(cast, shot[0], direction)
	MuzzleFlash.spawn(cast.effect_parent(), shot[0], shot[1])
	SoundManager.play_gunshot(cast.caster)


func _origin_and_aim(caster: Node3D, spawn_height: float, spawn_forward: float) -> Array:
	var origin := SkillDeliveries.spawn_point(caster, spawn_height, spawn_forward)
	var aim := SkillDeliveries.forward(caster)
	if caster.has_method("get_muzzle_point"):
		var muzzle = caster.get_muzzle_point()
		if muzzle is Vector3:
			origin = muzzle
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
	projectile.tint = ShootProjectile.TINT_PLAYER if caster.is_in_group("players") 			else ShootProjectile.TINT_ENEMY
	projectile.speed = cast.flag("speed")
	projectile.max_distance = cast.flag("range") if max_distance < 0.0 else max_distance
	projectile.pierce = maxi(int(cast.flag("pierce")), 0)
	projectile.floor_y = caster.global_position.y + FLOOR_CLEARANCE
	projectile.enemy_group = SkillTargets.target_group(caster)
	projectile.hit_mask = SkillTargets.projectile_mask(caster, projectile.hit_mask)
	if not exclude.is_empty():
		projectile.exclude = exclude.duplicate()
	elif caster is CollisionObject3D:
		projectile.exclude = [caster.get_rid()]
	if exclude.is_empty():
		projectile.point_blank_from = Vector3(caster.global_position.x, origin.y, caster.global_position.z)

	cast.effect_parent().add_child(projectile)
	projectile.global_position = origin

	projectile.hit_enemy.connect(_on_hit_enemy.bind(projectile, cast))
	projectile.hit_world.connect(_on_hit_world.bind(cast))


func _on_hit_enemy(target: Node, position: Vector3, pierced_so_far: int,
		projectile: ShootProjectile, cast: SkillCast) -> void:
	if not cast.is_valid() or not is_instance_valid(target):
		return
	var keep := maxf(1.0 - cast.flag("pierce_falloff"), 0.0)
	ShootTracers.spark(cast.effect_parent(), position, 0.3, projectile.tint if is_instance_valid(projectile) \
			else ShootProjectile.TINT_PLAYER)
	var info := cast.hit(target, pow(keep, pierced_so_far))
	if is_instance_valid(projectile):
		projectile.pierce = maxi(projectile.pierce, int(cast.flag("pierce")))
	if pierced_so_far == 0 and info.flag("fork_count") >= 1.0 and not cast.extra.get("forked", false) \
			and not target.is_in_group(&"breakables") and is_instance_valid(projectile):
		_fork(cast, projectile, position, info)


func _fork(cast: SkillCast, projectile: ShootProjectile, at: Vector3, info: HitInfo = null) -> void:
	var child := cast.spawn_child()
	child.extra = cast.extra.duplicate()
	child.extra["forked"] = true
	if info != null:
		for k in ["fork_count", "fork_angle"]:
			if info.flag_bonus.has(k):
				child.flag_bonus[k] = float(child.flag_bonus.get(k, 0.0)) + float(info.flag_bonus[k])
	child.damage_mult *= maxf(cast.flag("fork_damage"), 0.0)
	for s in cast.skill.support_behaviors:
		if s is ProgramSupport:
			(s as ProgramSupport).apply_fork_rules(child)
	var reach := maxf(projectile.max_distance - projectile.travelled(), cast.flag("range") * 0.5)
	var dirs := SkillDeliveries.fan_directions(projectile.direction,
			int(round(child.flag("fork_count"))), child.flag("fork_angle"))
	ShootTracers.spark(cast.effect_parent(), at, 0.45, Color(0.4, 0.95, 1.0))
	for d in dirs:
		_spawn_projectile(child, at, d, projectile.exclude, reach)


func _on_hit_world(position: Vector3, cast: SkillCast) -> void:
	if cast.is_valid():
		ShootTracers.spark(cast.effect_parent(), position, 0.25, Color(0.8, 0.8, 0.8))
