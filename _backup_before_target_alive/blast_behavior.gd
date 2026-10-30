class_name BlastBehavior
extends SkillBehavior
## Fires a projectile that explodes on impact, damaging every enemy in a circle.
## Flags (set per gem in SkillGemRegistry, changeable by supports through flag_modifiers):
##   max_projectiles  how many projectiles one cast fires (1 = a single shot)
##   spread_angle     degrees between neighbouring projectiles, so more projectiles = wider fan
##   speed            projectile speed in metres per second
##   range            how far it flies before exploding on its own
##   radius           explosion radius in metres
##   max_targets      cap on how many enemies one explosion can hit
##   spawn_height     metres above the caster's feet where it starts
##   spawn_forward    metres in front of the caster where it starts
##   recovery_mult    how much longer than a normal attack the cast takes
##
## Projectiles are drawn and moved by a BlastSwarm (one MultiMesh per team), not by nodes.

const PLAYER_SWARM_GROUP := &"player_blast_swarm"
const ENEMY_SWARM_GROUP := &"enemy_blast_swarm"
const BASE_HIT_MASK := 5     # world (layer 1) + enemies (layer 3); SkillTargets adapts it per caster

func release(cast: SkillCast) -> void:
	var caster := cast.caster
	var swarm := _find_swarm(caster)
	if swarm == null:
		push_error("BlastBehavior: no BlastSwarm found for %s" % caster.name)
		return

	var style := SkillStyle.for_caster(caster)
	swarm.set_style(style)               # player swarm puts on the equipped orb's shader

	var origin := SkillDeliveries.spawn_point(caster, cast.flag("spawn_height"), cast.flag("spawn_forward"))
	var exclude_rid := RID()
	if caster is CollisionObject3D:
		exclude_rid = caster.get_rid()                   # never explode on the caster itself
	var mask := SkillTargets.projectile_mask(caster, BASE_HIT_MASK)

	var directions := SkillDeliveries.fan_directions(cast.forward(),
			int(cast.flag("max_projectiles")), cast.flag("spread_angle"))
	for direction in directions:
		# The Callable receives the impact position first, then the values bound here.
		swarm.spawn(origin, direction, style["primary"],
			cast.flag("speed"), cast.flag("range"), mask, exclude_rid,
			_explode.bind(cast, style, direction))


func aim_preview(caster: Node3D, skill: SkillInstance) -> Array:
	var origin := SkillDeliveries.spawn_point(caster, skill.get_flag("spawn_height"), skill.get_flag("spawn_forward"))
	var out := []
	for d in SkillDeliveries.fan_directions(SkillDeliveries.forward(caster),
			int(skill.get_flag("max_projectiles")), skill.get_flag("spread_angle")):
		out.append({"from": origin, "direction": d, "range": skill.get_flag("range"),
				"radius": skill.get_flag("radius"), "pierce": 0})
	return out


## Loop repeats wait for the last shot to explode (so breaks, target_alive and Pointer know what
## it hit), then fire one shot from the caster, the way the caster is facing right now.

func waits_for_impact() -> bool:
	return true


func repeat_release(cast: SkillCast, from_impact: Variant, _direction: Vector3) -> void:
	var origin := SkillDeliveries.spawn_point(cast.caster, cast.flag("spawn_height"), cast.flag("spawn_forward"))
	var aim := {"from": origin, "direction": cast.forward(), "range": cast.flag("range"),
		"seek_from": from_impact if from_impact is Vector3 else origin}
	for s in cast.skill.support_behaviors:
		s.aim_repeat(cast, aim)                  # Pointer picks a target
	fire_shot(cast, aim["from"], aim["direction"], aim["range"])


## The player and enemies each have their own swarm, so the orb shader only touches the player's.
## Uses SkillTargets.is_enemy(), the same test that picks the hit mask, so the two always agree.
func _find_swarm(caster: Node3D) -> BlastSwarm:
	var group := ENEMY_SWARM_GROUP if SkillTargets.is_enemy(caster) else PLAYER_SWARM_GROUP
	return caster.get_tree().get_first_node_in_group(group) as BlastSwarm


## The shot can outlive its caster (the enemy dies, the area is swapped), so check the cast first.
func _explode(center: Vector3, cast: SkillCast, style: Dictionary, direction := Vector3.ZERO) -> void:
	if not cast.is_valid():
		return
	var radius := cast.flag("radius") * float(cast.extra.get("radius_mult", 1.0))
	ImpactEffect.spawn(cast.effect_parent(), center, radius, style["secondary"], style["primary"])
	SoundManager.play_blast_impact(cast.effect_parent(), center)
	for target in SkillDeliveries.hits_in_circle(cast, center, radius, int(cast.flag("max_targets"))):
		cast.hit(target)
	for s in cast.skill.support_behaviors:
		s.on_area_impact(cast, center, direction)


## One extra shot for a cast that already exists (loop repeats), from any point.
func fire_shot(cast: SkillCast, origin: Vector3, direction: Vector3, max_range: float) -> void:
	var caster := cast.caster
	if not cast.is_valid():
		return
	var swarm := _find_swarm(caster)
	if swarm == null:
		return
	var style := SkillStyle.for_caster(caster)
	var exclude_rid := RID()
	if caster is CollisionObject3D:
		exclude_rid = caster.get_rid()
	swarm.spawn(origin, direction, style["primary"], cast.flag("speed"), maxf(max_range, 0.5),
			SkillTargets.projectile_mask(caster, BASE_HIT_MASK), exclude_rid,
			_explode.bind(cast, style, direction))
