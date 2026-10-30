class_name DamageRoller

static func roll_damage(stats: StatComponent, min_stat: StatTypes.Stat, max_stat: StatTypes.Stat) -> float:
	var min_dmg := stats.get_stat(min_stat)
	var max_dmg := stats.get_stat(max_stat)
	if max_dmg < min_dmg:
		max_dmg = min_dmg
	return randf_range(min_dmg, max_dmg)

static func roll_damage_with_crit(stats: StatComponent, min_stat: StatTypes.Stat, max_stat: StatTypes.Stat) -> Dictionary:
	var base := roll_damage(stats, min_stat, max_stat)
	var is_crit := randf() < stats.get_stat(StatTypes.Stat.CRIT_CHANCE)
	var final: float = base * stats.get_stat(StatTypes.Stat.CRIT_MULTIPLIER) if is_crit else base
	return {"damage": final, "is_crit": is_crit}
