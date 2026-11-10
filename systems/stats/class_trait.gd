class_name ClassTrait
extends Resource
## A class's innate passive: always on, can't be changed. Most of them bend the skill-program
## rules, so every class scripts its skills a little differently.
## One .tres per class in res://data/class_traits/, named after the class id (raider.tres...).
## ClassData.get_trait() finds it. Every number defaults to "no effect".

## The trait of a class id ("raider"...), or null.
static func for_class(class_id: String) -> ClassTrait:
	var path := "res://data/class_traits/%s.tres" % class_id
	return load(path) as ClassTrait if class_id != "" and ResourceLoader.exists(path) else null


@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Program knobs")
## Points every knob step costs (and drawbacks pay back), x this. Raider: 1.5
@export var knob_cost_mult: float = 1.0
## How much every knob step changes, x this. Raider: 2.5
@export var knob_effect_mult: float = 1.0
## Extra program points on every skill. Enchanter: 3
@export var extra_points: float = 0.0
## Points spent on buffs (and on WHEN rules and loops) x this. Drawbacks still pay back their
## full value, so this is a real discount. Enchanter: 0.75 (25% less)
@export var buff_cost_mult: float = 1.0
## Rules with an "every Nth cast" condition cost x this... Gladiator: 0.5
@export var nth_rule_cost_mult: float = 1.0
## ...and their knob steps change x this. Gladiator: 1.5
@export var nth_rule_effect_mult: float = 1.0
## ...plus this much more for each step rarer than every 2nd cast, so rarer rules hit harder.
## Gladiator: 0.25 (every 2nd x1.5, every 3rd x1.75, every 4th x2.0 ... every 6th x2.5)
@export var nth_rule_effect_per_n: float = 0.0
## Rules with a per-hit condition (WHEN target life below...) cost x this... Assassin: 0.5
@export var hit_rule_cost_mult: float = 1.0
## ...and their damage steps change x this (not their leech, barrier or guard). Assassin: 2.0
@export var hit_rule_effect_mult: float = 1.0
## Per-hit rules (target life below) may change any flag knob too, not only damage.
## (Not used by any class right now.)
@export var per_hit_any_knob: bool = false

@export_group("Stats")
## Increased armour for each ALWAYS rule in your applied programs. Paladin: 0.10
@export var armour_per_always_rule: float = 0.0
## Increased armour for a few seconds each time a WHEN rule fires. Paladin: 0.10
@export var armour_per_when_fire: float = 0.0
@export var when_buff_seconds: float = 4.0
## Increased skill damage for every full 10 armour you have, read on each cast. Paladin: 0.01
@export var damage_per_10_armour: float = 0.0
## Flat movement speed for each rule in your applied programs. (Not used by any class right now.)
@export var move_speed_per_rule: float = 0.0
## Flat movement speed for each knob step in your applied programs (every step of every
## effect that costs points: -1 mana cost counts, drawbacks and variable writes don't). Rogue: 0.15
@export var move_speed_per_knob_step: float = 0.0
## More damage on skill hits while you are moving. (Not used by any class right now.)
@export var moving_damage_more: float = 0.0
## More damage on skill hits while you are moving, for each 1 movement speed you have.
## Rogue: 0.15 (base speed 5 = 75% more)
@export var moving_damage_more_per_speed: float = 0.0
## More damage on a hit against an enemy still at full life (the opening shot). Assassin: 0.5
@export var full_life_damage_more: float = 0.0

@export_group("Movement")
## Walk through enemies instead of being blocked by them (they still can't walk through you,
## and still hit you). Rogue
@export var phase_through_enemies: bool = false


## The cost / effect multipliers for one rule ("every Nth cast" rules and per-hit rules can
## have their own; a rule with both gets both).
func rule_cost_mult(rule: ProgramRule) -> float:
	return (nth_rule_cost_mult if _is_nth(rule) else 1.0) * (hit_rule_cost_mult if _is_per_hit(rule) else 1.0)


## `include_hit`: false for a per-hit rule's leech / barrier / guard, which the per-hit bonus
## (Assassin: damage steps count double) doesn't cover.
func rule_effect_mult(rule: ProgramRule, include_hit := true) -> float:
	return (nth_effect_mult(rule) if _is_nth(rule) else 1.0) \
			* (hit_rule_effect_mult if include_hit and _is_per_hit(rule) else 1.0)


## Gladiator: every-Nth rules get stronger the rarer they fire.
func nth_effect_mult(rule: ProgramRule) -> float:
	var n := 2
	for c in rule.conditions:
		if c is EveryNthCastCondition:
			n = maxi(n, (c as EveryNthCastCondition).n)
	return nth_rule_effect_mult + nth_rule_effect_per_n * (n - 2)


static func _is_per_hit(rule: ProgramRule) -> bool:
	return rule != null and rule.loop == null and rule.scope() == ProgramCondition.Scope.HIT


static func _is_nth(rule: ProgramRule) -> bool:
	if rule == null:
		return false
	for c in rule.conditions:
		if c is EveryNthCastCondition:
			return true
	return false


## A copy of a knob with this trait's cost and effect multipliers baked in, so pricing,
## validation, applying the program and the editor's numbers all agree.
func adjust_knob(k: SkillKnob) -> SkillKnob:
	if is_equal_approx(knob_cost_mult, 1.0) and is_equal_approx(knob_effect_mult, 1.0):
		return k
	var c := k.duplicate() as SkillKnob
	c.cost_per_step = k.cost_per_step * knob_cost_mult
	c.step = k.step * knob_effect_mult
	return c


# ---------- RUNTIME EFFECTS ----------
const RULES_SOURCE := "class_trait_rules"

## Paladin / Rogue: stat bonuses from how many rules your applied programs have.
## SkillComponent calls this whenever a socket or program changes.
func apply_rule_bonuses(stats: StatComponent, always_rules: int, total_rules: int, knob_steps: int = 0) -> void:
	if stats == null:
		return
	stats.remove_by_source(RULES_SOURCE)
	if armour_per_always_rule > 0.0 and always_rules > 0:
		stats.add_modifier(_mod(StatTypes.Stat.ARMOUR, Modifier.ModOp.PERCENT_ADD,
				armour_per_always_rule * always_rules, RULES_SOURCE))
	if move_speed_per_rule > 0.0 and total_rules > 0:
		stats.add_modifier(_mod(StatTypes.Stat.MOVE_SPEED, Modifier.ModOp.FLAT_ADD,
				move_speed_per_rule * total_rules, RULES_SOURCE))
	if move_speed_per_knob_step > 0.0 and knob_steps > 0:
		stats.add_modifier(_mod(StatTypes.Stat.MOVE_SPEED, Modifier.ModOp.FLAT_ADD,
				move_speed_per_knob_step * knob_steps, RULES_SOURCE))


## Paladin: increased skill damage from current armour (every full 10), added to a cast's
## effective stats by SkillInstance.build_effective_stats.
func armour_damage_increase(caster_stats: StatComponent) -> float:
	if damage_per_10_armour <= 0.0 or caster_stats == null:
		return 0.0
	return damage_per_10_armour * floorf(maxf(caster_stats.get_stat(StatTypes.Stat.ARMOUR), 0.0) / 10.0)


## Paladin: a WHEN rule fired. Its armour buff starts, or restarts if it was still running.
func on_rule_fired(caster: Node, key: String) -> void:
	if armour_per_when_fire <= 0.0 or not is_instance_valid(caster):
		return
	var stats := caster.get("stats") as StatComponent
	if stats == null:
		return
	var source := "class_trait_when_%s" % key
	stats.remove_by_source(source)
	stats.add_modifier(_mod(StatTypes.Stat.ARMOUR, Modifier.ModOp.PERCENT_ADD, armour_per_when_fire, source))
	var token: int = int(stats.get_meta(source, 0)) + 1
	stats.set_meta(source, token)
	var timer := caster.get_tree().create_timer(when_buff_seconds, false)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(stats) and int(stats.get_meta(source, 0)) == token:
			stats.remove_by_source(source))


## Rogue / Assassin: the damage multiplier for a hit right now (before the damage lands).
func hit_damage_mult(caster: Node, target: Node = null) -> float:
	var m := 1.0
	if (moving_damage_more > 0.0 or moving_damage_more_per_speed > 0.0) and caster is CharacterBody3D:
		var v := (caster as CharacterBody3D).velocity
		if Vector2(v.x, v.z).length() > 0.5:
			m *= 1.0 + moving_damage_more
			var stats := caster.get("stats") as StatComponent
			if moving_damage_more_per_speed > 0.0 and stats != null:
				m *= 1.0 + moving_damage_more_per_speed * maxf(stats.get_stat(StatTypes.Stat.MOVE_SPEED), 0.0)
	if full_life_damage_more > 0.0 and target != null and not target.is_in_group(&"breakables") \
			and ProgramCondition.health_fraction(target) >= 0.999:
		m *= 1.0 + full_life_damage_more                       # the opening shot
	return m


## One line per effect, for the script editor and the class screen.
func summary() -> PackedStringArray:
	var out := PackedStringArray()
	if not is_equal_approx(knob_cost_mult, 1.0) or not is_equal_approx(knob_effect_mult, 1.0):
		out.append("knob steps cost x%s, effect x%s" % [_n(knob_cost_mult), _n(knob_effect_mult)])
	if extra_points != 0.0:
		out.append("%+d program points" % roundi(extra_points))
	if not is_equal_approx(buff_cost_mult, 1.0):
		out.append("buffs cost %d%% %s points" % [roundi(absf(1.0 - buff_cost_mult) * 100.0),
			"fewer" if buff_cost_mult < 1.0 else "more"])
	if not is_equal_approx(nth_rule_cost_mult, 1.0) or not is_equal_approx(nth_rule_effect_mult, 1.0):
		var eff := "x%s" % _n(nth_rule_effect_mult)
		if nth_rule_effect_per_n > 0.0:
			eff += " (+%s per N above 2)" % _n(nth_rule_effect_per_n)
		out.append("every-Nth-cast rules cost x%s, effect %s" % [_n(nth_rule_cost_mult), eff])
	if not is_equal_approx(hit_rule_cost_mult, 1.0) or not is_equal_approx(hit_rule_effect_mult, 1.0):
		out.append("per-hit rules cost x%s, effect x%s" % [_n(hit_rule_cost_mult), _n(hit_rule_effect_mult)])
	if per_hit_any_knob:
		out.append("per-hit rules can change any flag knob, and attack speed for your next attack")
	if armour_per_always_rule > 0.0:
		out.append("+%d%% armour per ALWAYS rule" % roundi(armour_per_always_rule * 100.0))
	if armour_per_when_fire > 0.0:
		out.append("+%d%% armour for %ds when a WHEN rule fires" % [roundi(armour_per_when_fire * 100.0), roundi(when_buff_seconds)])
	if damage_per_10_armour > 0.0:
		out.append("%s%% increased damage per 10 armour" % _n(damage_per_10_armour * 100.0))
	if move_speed_per_rule > 0.0:
		out.append("+%s movement speed per rule" % _n(move_speed_per_rule))
	if move_speed_per_knob_step > 0.0:
		out.append("+%s movement speed per knob step" % _n(move_speed_per_knob_step))
	if moving_damage_more > 0.0:
		out.append("%d%% more damage while moving" % roundi(moving_damage_more * 100.0))
	if moving_damage_more_per_speed > 0.0:
		out.append("%d%% more damage per 1 movement speed while moving" % roundi(moving_damage_more_per_speed * 100.0))
	if full_life_damage_more > 0.0:
		out.append("%d%% more damage against enemies at full life" % roundi(full_life_damage_more * 100.0))
	if phase_through_enemies:
		out.append("move through enemies")
	return out


static func _n(v: float) -> String:
	return str(snappedf(v, 0.01)).trim_suffix(".0")


static func _mod(stat: int, op: int, value: float, source: String) -> Modifier:
	var m := Modifier.new()
	m.stat = stat
	m.op = op
	m.value = value
	m.source_id = source
	return m
