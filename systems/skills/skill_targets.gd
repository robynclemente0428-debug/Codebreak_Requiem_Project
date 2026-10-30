class_name SkillTargets
extends RefCounted
## Who a skill hurts depends on who casts it: player skills hit enemies, enemy skills hit players.
## Every behavior asks this class for its targets instead of hardcoding a group.
##
##     var enemies := SkillTargets.candidates(caster)       # instead of get_nodes_in_group("enemies")

## Physics layer VALUE of your Player body (layer 1 = 1, layer 2 = 2, layer 3 = 4, layer 4 = 8...).
## Only projectiles fired by enemies use it. Check Player > Collision > Layer and set it to match.
const PLAYER_LAYER_MASK := 2
const WORLD_LAYER_MASK := 1


## True when the caster is an enemy. This checks the type, not the "enemies" group, because a
## dying enemy leaves the group and its last shots must still count as an enemy's.
static func is_enemy(caster: Node) -> bool:
	return caster is EnemyBase or (caster != null and caster.has_meta(&"hologram_of_enemy"))


static func target_group(caster: Node) -> StringName:
	return &"players" if is_enemy(caster) else &"enemies"


static func candidates(caster: Node) -> Array:
	return caster.get_tree().get_nodes_in_group(target_group(caster))


## What a skill can actually hit: candidates() plus breakable props (barrels, caches) for
## player casters. Conditions like "enemies nearby" keep using candidates(), so props never
## count as enemies.
static func hittable(caster: Node) -> Array:
	var out := candidates(caster)
	if not is_enemy(caster):
		out.append_array(caster.get_tree().get_nodes_in_group(&"breakables"))
	return out


## Layers a projectile explodes on. Players keep the projectile's own default mask.
## Enemies get world + player, so their shots ignore other enemies.
static func projectile_mask(caster: Node, default_mask: int) -> int:
	if is_enemy(caster):
		return WORLD_LAYER_MASK | PLAYER_LAYER_MASK
	return default_mask
