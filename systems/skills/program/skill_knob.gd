class_name SkillKnob
extends Resource
## One value a player is allowed to change on a skill, with its limits and its price.
## Each gem lists its knobs in its SkillProgramLimits. Players never see or edit these numbers:
## they only choose how many STEPS to move a knob (+2 damage steps, -1 attack speed step, ...).
##
## Price: the first step costs `cost_per_step` points. Buffs have a positive cost, drawbacks pay
## points back. Buff steps get pricier: each one costs STEP_COST_GROWTH x the one before, counting
## every buff step this knob has in the script (SkillProgram.line_cost). Drawbacks pay back flat. Example: damage step = +5% for 2 points; mana cost step = +10% for -1 point.

enum Kind {
	## Skill damage. Works in every rule: always, per cast and per hit.
	DAMAGE,
	## A gem flag (range_bonus, radius, arc_angle, pierce...). Always or per-cast rules only.
	FLAG,
	## Any other stat (mana cost, attack speed, crit...). Only in ALWAYS rules, because mana and
	## cooldown are paid before any condition can be checked.
	STAT,
	## Writes the registry (ScriptRegisters): registry.add(target), registry.remove(target). Free, and works in every rule.
	VARIABLE,
}

@export var id: StringName
@export var display_name: String
@export var kind: Kind = Kind.FLAG
## Read before the cast starts (like attack speed), so only an always: rule can change it.
@export var always_only := false
## Its gem only acts on the original cast (echoes, finishers, holograms, on-kill explosions,
## Try / Except), so changing it in a loop body or a repeat-only rule does nothing.
@export var first_cast_only := false
## For DAMAGE and STAT knobs. Applied as PERCENT_MULT: 3 steps of 0.05 = 15% more.
@export var stat: StatTypes.Stat = StatTypes.Stat.SKILL_DAMAGE_MULT
## For FLAG knobs: the flag name, e.g. "range_bonus". Its value is added to the gem's flag.
@export var flag_key: String = ""
## How much one step changes the value (0.05 = 5% for stats, 0.25 = a quarter metre for range).
@export var step: float = 0.05
## Hard limits in steps, counting every rule that could be active at the same time.
@export var min_steps: int = -5
@export var max_steps: int = 5
## Points one +1 step costs. Negative = moving this knob up is a drawback (mana cost, ...).
@export var cost_per_step: float = 1.0
## How the value is shown: "%" (0.05 -> +5%), "m" (0.25 -> +0.25 m) or "" (plain number).
@export var unit: String = "%"
## Listed under DEFENSE in the script editor's snippets (leech, barrier, guard...).
@export var defensive := false


func value_for(steps: int) -> float:
	return step * steps


## Each buff step on a knob costs this much more than the step before it.
const STEP_COST_GROWTH := 1.25
## Every buff step's price x this, to make up for the rising price: a damage knob of
## cost_per_step 2 starts at 1 point. Drawbacks still pay back the full cost_per_step.
const BUFF_PRICE_MULT := 0.5


## Flat price of `steps` (sign tells buff from drawback). Buff lines in a script are priced with
## buff_cost instead; this stays the price of a drawback and of a single step.
func cost_for(steps: int) -> float:
	return cost_per_step * steps


## True when moving this knob `steps` costs points (a buff), false when it pays them back.
func is_buff(steps: int) -> bool:
	return cost_per_step * steps > 0.0


## Total price of `n` buff steps on this knob: 1, 1.25, 1.56... x the first step's price
## (cost_per_step x BUFF_PRICE_MULT).
func buff_cost(n: int) -> float:
	if n <= 0:
		return 0.0
	return first_step_cost() * (pow(STEP_COST_GROWTH, n) - 1.0) / (STEP_COST_GROWTH - 1.0)


## What the first buff step costs.
func first_step_cost() -> float:
	return absf(cost_per_step) * BUFF_PRICE_MULT


## Price of the next buff step after `n` already taken.
func next_step_cost(n: int) -> float:
	return first_step_cost() * pow(STEP_COST_GROWTH, maxi(n, 0))


func describe(steps: int) -> String:
	var v := value_for(steps)
	match unit:
		"%":
			return "%s %+d%%" % [display_name, roundi(v * 100.0)]
		"m":
			return "%s %+.2f m" % [display_name, v]
		"deg":
			return "%s %+d°" % [display_name, roundi(v)]
		_:
			# whole numbers without decimals (+1), otherwise one decimal (+0.5)
			if is_equal_approx(v, roundf(v)):
				return "%s %+d" % [display_name, roundi(v)]
			return "%s %+.1f" % [display_name, v]


## The modifier an ALWAYS rule bakes into the skill (DAMAGE and STAT knobs).
func make_modifier(steps: int, source_id: String) -> Modifier:
	var m := Modifier.new()
	m.stat = StatTypes.Stat.SKILL_DAMAGE_MULT if kind == Kind.DAMAGE else stat
	m.op = Modifier.ModOp.PERCENT_MULT
	m.value = value_for(steps)
	m.source_id = source_id
	return m
