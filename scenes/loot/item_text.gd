class_name ItemText
extends RefCounted
## Turns items into display text. The same wording the inventory panel uses, in one
## shared place so tooltips and panels always agree.

## Display names for stats in item text. Anything missing falls back to the enum name.
const STAT_LABELS := {
	StatTypes.Stat.MAX_HEALTH: "Maximum Life",
	StatTypes.Stat.ARMOUR: "Armour",
	StatTypes.Stat.MOVE_SPEED: "Movement Speed",
	StatTypes.Stat.MIN_ATTACK_DAMAGE: "Attack Damage",
	StatTypes.Stat.MAX_ATTACK_DAMAGE: "Attack Damage",
	StatTypes.Stat.ATTACK_SPEED: "Attack Speed",
	StatTypes.Stat.CRIT_CHANCE: "Critical Strike Chance",
	StatTypes.Stat.CRIT_MULTIPLIER: "Critical Strike Multiplier",
	StatTypes.Stat.LIFE_ON_HIT: "Life on Hit",
	StatTypes.Stat.MANA: "Maximum Mana",
	StatTypes.Stat.SKILL_DAMAGE_MULT: "Skill Damage",
	StatTypes.Stat.STRENGTH: "Strength",
	StatTypes.Stat.DEXTERITY: "Dexterity",
	StatTypes.Stat.INTELLIGENCE: "Intelligence",
	StatTypes.Stat.REGENERATION: "Life Regeneration",
}


static func type_name(def: ItemDefinition) -> String:
	if def.weapon_type != null:
		return def.weapon_type.display_name.to_upper()
	if def.equipment_type != null:
		return def.equipment_type.display_name.to_upper()
	return "ITEM"


static func stat_label(stat: int) -> String:
	if STAT_LABELS.has(stat):
		return STAT_LABELS[stat]
	return str(StatTypes.Stat.find_key(stat)).capitalize()


## Shows min and max attack damage together as one "10 - 20" line.
static func base_lines(base: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var mn: int = StatTypes.Stat.MIN_ATTACK_DAMAGE
	var mx: int = StatTypes.Stat.MAX_ATTACK_DAMAGE
	var paired := base.has(mn) and base.has(mx)
	if paired:
		out.append("Attack Damage  %d - %d" % [roundi(base[mn]), roundi(base[mx])])
	for stat in base.keys():
		if paired and (stat == mn or stat == mx):
			continue
		out.append("%s  %s" % [stat_label(stat), flat_text(stat, base[stat])])
	return out


static func flat_text(stat: int, v: float) -> String:
	match stat:
		StatTypes.Stat.CRIT_CHANCE, StatTypes.Stat.SKILL_DAMAGE_MULT:
			return "%+.1f%%" % (v * 100.0)
		StatTypes.Stat.CRIT_MULTIPLIER:
			return "%+.2f" % v
		StatTypes.Stat.ATTACK_SPEED, StatTypes.Stat.MOVE_SPEED, \
		StatTypes.Stat.LIFE_ON_HIT, StatTypes.Stat.REGENERATION:
			return "%+.1f" % v
	return "%+d" % roundi(v)


static func pct(v: float) -> String:
	return ("%.1f" % (v * 100.0)).trim_suffix(".0")


static func range_name(a: AffixDefinition) -> String:
	var n1 := stat_label(a.min_stat)
	var n2 := stat_label(a.max_stat)
	return n1 if n1 == n2 else "%s and %s" % [n1, n2]


static func affix_text(entry: Dictionary) -> String:
	var a: AffixDefinition = entry["affix"]
	var v: float = float(entry.get("rolled_value", 0.0))
	match a.shape:
		AffixDefinition.AffixShape.DAMAGE_RANGE:
			return "Adds %d - %d %s" % [roundi(entry["rolled_min"]), roundi(entry["rolled_max"]), range_name(a)]
		AffixDefinition.AffixShape.PERCENT_RANGE:
			return "%s%% %s %s" % [pct(absf(v)), "increased" if v >= 0.0 else "reduced", range_name(a)]
		AffixDefinition.AffixShape.PERCENT_MULT_RANGE:
			return "%s%% %s %s" % [pct(absf(v)), "more" if v >= 0.0 else "less", range_name(a)]
	var label := stat_label(a.stat)
	match a.op:
		Modifier.ModOp.FLAT_ADD:
			return "%s %s" % [flat_text(a.stat, v), label]
		Modifier.ModOp.PERCENT_ADD:
			return "%s%% %s %s" % [pct(absf(v)), "increased" if v >= 0.0 else "reduced", label]
		Modifier.ModOp.PERCENT_MULT:
			return "%s%% %s %s" % [pct(absf(v)), "more" if v >= 0.0 else "less", label]
	return "%s: %s" % [label, str(v)]
