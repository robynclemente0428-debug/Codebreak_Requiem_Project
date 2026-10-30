class_name ExplodeOnKillSupport
extends SupportBehavior
## Enemies killed by the supported skill explode, damaging enemies around them.
## Flags (set in SkillGemRegistry._support_flag_modifiers, so other supports can change them):
##   explode_radius       metres around the dead enemy
##   explode_damage       fraction of a normal hit of this skill (0.5 = half damage)
##   explode_max_targets  cap on how many enemies one explosion can hit
##
## Explosions don't trigger more explosions: kills made BY an explosion are ignored (depth > 0).

func on_kill(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	if cast.depth > 0:
		return
	var radius := cast.flag("explode_radius")
	if radius <= 0.0:
		return
	var sub := cast.spawn_child()
	ImpactEffect.spawn(cast.effect_parent(), hit.position, radius,
			Color(1.0, 0.35, 0.15), Color(1.0, 0.7, 0.3))
	for other in SkillDeliveries.hits_in_circle(sub, hit.position, radius,
			int(cast.flag("explode_max_targets")), [target]):
		sub.hit(other, cast.flag("explode_damage"))
