class_name ScriptRegisters
extends RefCounted
## Counters (what players call them; the code says registers): a script's memory. Every skill's
## script has two, x and y, whole numbers
## that keep their value between casts. They live on the script (SkillProgram.registers), so each
## script set keeps its own and rebuilding the skill leaves them alone. They start at 0, and clear
## when the script is applied, on a change of area, or CLEAR_AFTER seconds out of combat.
##
##   when hit_recently(3.0s):
##       x += 1
##   when x >= 3:
##       damage += 25%
##       x = 0
##
## Both blocks are modular, like the Act II patch puzzles: every part is a token you click.
##   READ   when [x] [>=] [3]:   a VarCondition. Variable x / y, any of OPS, value 0 to MAX_VALUE.
##   WRITE  [x] [+=] [1]         a ProgramEffect on the one knob WRITE_KNOB (Kind.VARIABLE), holding
##                               its variable and operator; its steps are the value.
## Writes cost no points and don't count as blocks: a counter should never push a script out of
## its efficiency tier.
##
## A buff can also grow with a counter, its value token set to x or y:
##   when hit_recently(2.0s):
##       x += 1
##   always:
##       damage += x * 2%         (ProgramEffect.ramp)
## The buff keeps growing until it reaches the knob's limit, less the script's flat lines on that
## knob (SkillProgram.growth_room). A knob can have one growing line. Its value sets how fast it gets
## there, and the price follows: a share of what the whole room would cost flat, from RAMP_COST_SLOW
## for the slowest line to RAMP_COST_FAST for the fastest, if a WHEN about the fight raises the
## counter. Otherwise (always: x = 5) nothing has to be earned, so it pays for the room in full.
## A counter a buff grows with can only rise once per cast, however many hits or rules raise it.
## Only values that can change gradually can grow (can_grow), not whole numbers like pierce.
##
## A cast reads first and writes after: every WHEN rule of a cast sees the registers as they were
## when it started, then the writes land in rule order. So the order of the rules never changes
## what they mean. Loop repeats and per-hit rules write straight away, one repeat or hit at a time,
## which is what lets  while x < 3:  stop itself.
##
## A read needs a line that raises the register, and can't be a comparison that no value changes
## (SkillProgram.validate). If nothing lowers the register, the script is fine (a one-way switch:
## when y == 1:) and the read keeps its discount: the switch clears after the fight, so it has to be
## earned again each time.

const NAMES := ["x", "y"]
const MAX_VALUE := 99
## The most one write can name (x += 5, x = 5). The counter climbs past it a write at a time.
const WRITE_MAX := 5
## The comparison operators, in the Act II patch puzzles' order.
const OPS := ["<", ">", "<=", ">=", "==", "!="]
const WRITE_OPS := ["=", "+=", "-="]
const WRITE_KNOB := &"var"
## Seconds without landing a hit or being hit before a script's counters clear.
const CLEAR_AFTER := 10.0
## How many counts of a growing buff make one of its knob's steps, at a value of 1: damage has 5%
## steps, so x * 1% takes 5 counts to add a step.
const RAMP_PER_STEP := 5
## What a growing buff costs, as a share of its room's flat price (SkillProgram.line_cost).
const RAMP_COST_SLOW := 0.3
const RAMP_COST_FAST := 0.6
## The flags that can grow. Damage always can. The rest are whole numbers, or read at the wrong time.
const GROW_KNOBS: Array[StringName] = [&"radius", &"range_bonus", &"arc_angle", &"range", &"spread", &"speed", &"leech", &"barrier", &"guard"]

static var _knobs: Array[SkillKnob] = []


## The write block, added to every programmable skill (SkillProgramLimits.for_socket).
static func knobs() -> Array[SkillKnob]:
	if _knobs.is_empty():
		var k := SkillKnob.new()
		k.id = WRITE_KNOB
		k.display_name = "counter"
		k.kind = SkillKnob.Kind.VARIABLE
		k.step = 1.0
		k.min_steps = 0
		k.max_steps = 9999                      # the steps are values here, not a limited resource
		k.cost_per_step = 0.0
		k.unit = ""
		_knobs.append(k)
	return _knobs


static func is_write(knob_id: StringName) -> bool:
	return knob_id == WRITE_KNOB


## True for a line that can push its register up.
static func raises(e: ProgramEffect) -> bool:
	return is_write(e.knob) and e.steps > 0 and e.write_op() != "-="


static func can_grow(knob: SkillKnob) -> bool:
	return knob != null and not knob.always_only \
			and (knob.kind == SkillKnob.Kind.DAMAGE or GROW_KNOBS.has(knob.id))


## How many knob steps a growing buff of `value` gives at this count, up to `room`.
static func ramp_steps(count: int, value: int, room: int) -> float:
	return clampf(float(count) * value / RAMP_PER_STEP, 0.0, float(maxi(room, 0)))


## The count at which a growing buff of `value` fills `room`.
static func ramp_reach(value: int, room: int) -> int:
	return ceili(float(room) * RAMP_PER_STEP / maxi(value, 1))


## The share of its room's flat price a growing buff pays when it has to be earned in the fight.
static func ramp_cost_share(value: int, room: int) -> float:
	if room <= 1:
		return RAMP_COST_FAST
	return lerpf(RAMP_COST_SLOW, RAMP_COST_FAST, clampf(float(value - 1) / (room - 1), 0.0, 1.0))


## `value` after this write.
static func written(e: ProgramEffect, value: int) -> int:
	match e.write_op():
		"=":
			return clampi(e.steps, 0, MAX_VALUE)
		"-=":
			return clampi(value - e.steps, 0, MAX_VALUE)
	return clampi(value + e.steps, 0, MAX_VALUE)


static func compare(value: int, op: String, n: int) -> bool:
	match op:
		"<": return value < n
		">": return value > n
		"<=": return value <= n
		">=": return value >= n
		"==": return value == n
		"!=": return value != n
	return false
