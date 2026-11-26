class_name SkillKnob
extends Resource

enum Kind {
	DAMAGE,
	FLAG,
	STAT,
	VARIABLE,
}

@export var id: StringName
@export var display_name: String
@export var kind: Kind = Kind.FLAG
@export var always_only := false
@export var first_cast_only := false
@export var stat: StatTypes.Stat = StatTypes.Stat.SKILL_DAMAGE_MULT
@export var flag_key: String = ""
@export var step: float = 0.05
@export var min_steps: int = -5
@export var max_steps: int = 5
@export var cost_per_step: float = 1.0
@export var unit: String = "%"
@export var defensive := false


func value_for(steps: int) -> float:
	return step * steps


const STEP_COST_GROWTH := 1.25
const BUFF_PRICE_MULT := 0.5


func cost_for(steps: int) -> float:
	return cost_per_step * steps


func is_buff(steps: int) -> bool:
	return cost_per_step * steps > 0.0


func buff_cost(n: int) -> float:
	if n <= 0:
		return 0.0
	return first_step_cost() * (pow(STEP_COST_GROWTH, n) - 1.0) / (STEP_COST_GROWTH - 1.0)


func first_step_cost() -> float:
	return absf(cost_per_step) * BUFF_PRICE_MULT


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
			if is_equal_approx(v, roundf(v)):
				return "%s %+d" % [display_name, roundi(v)]
			return "%s %+.1f" % [display_name, v]


func make_modifier(steps: int, source_id: String) -> Modifier:
	var m := Modifier.new()
	m.stat = StatTypes.Stat.SKILL_DAMAGE_MULT if kind == Kind.DAMAGE else stat
	m.op = Modifier.ModOp.PERCENT_MULT
	m.value = value_for(steps)
	m.source_id = source_id
	return m
