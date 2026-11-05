class_name TremorChainSupport
extends SupportBehavior
## Slam only. Every enemy the slam kills sets off a smaller slam where it fell, and kills from
## that tremor set off another, up to tremor_max_chain links deep.
## Flags (SkillGemRegistry._support_flag_modifiers, scriptable through the knobs):
##   tremor_max_chain   how many links a chain can grow (1 = only the slam's own kills tremor)
##   tremor_damage      fraction of a normal hit each tremor deals (0.5 = 50%)
##   tremor_radius      fraction of the slam's radius each tremor covers (0.6 = 60%)
##   tremor_delay       seconds between a kill and its tremor (so the chain reads as a ripple)
##
## The chain counter lives in cast.extra["tremor"], so tremors from Aftershock echoes count too.

func on_kill(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	var link: int = cast.extra.get("tremor", 0)
	if link >= int(round(cast.flag("tremor_max_chain"))):
		return
	var radius := cast.flag("radius") * cast.flag("tremor_radius")
	if radius <= 0.1:
		return
	_tremor(cast, target, hit.position, radius, link + 1)


func _tremor(cast: SkillCast, dead: Node, at: Vector3, radius: float, link: int) -> void:
	await cast.caster.get_tree().create_timer(maxf(cast.flag("tremor_delay"), 0.0), false).timeout
	if not cast.is_valid() or SkillBehavior.is_dead(cast.caster):
		return
	var sub := cast.spawn_child()
	sub.extra["tremor"] = link
	ImpactEffect.spawn(cast.effect_parent(), at, radius, Color(1.0, 0.45, 0.2), Color(1.0, 0.75, 0.35))
	for other in SkillDeliveries.hits_in_circle(sub, at, radius, SkillDeliveries.NO_CAP, [dead]):
		sub.hit(other, cast.flag("tremor_damage"))
