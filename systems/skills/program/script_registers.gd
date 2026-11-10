class_name ScriptRegisters
extends RefCounted
## The Registry (what players call it; the code still says registers): a script's memory, and the
## Strategist rank's unlock. It is a set of enemies: an enemy is either in it or not. The set
## lives on the script (SkillProgram.registers, enemy instance id -> true), so each script set
## keeps its own and rebuilding the skill leaves it alone. It starts empty, and clears when the
## script is applied, on a change of area, or CLEAR_AFTER seconds out of combat. An enemy that
## dies leaves it (prune), so it only ever holds the living.
##
##   always:
##       registry.add(target)            every enemy this cast hits joins the set
##   when target in registry:            checked per hit, against the enemy being hit
##       damage += 50%                   so only hits on enemies already in the set get it
##
## WRITE  registry.add(target), registry.remove(target): a ProgramEffect on the one knob WRITE_KNOB
##        (Kind.VARIABLE); its op is the operation (WRITE_OPS). Written from a cast rule (always:,
##        a WHEN, a loop), it acts on every enemy the cast hits, as each hit lands. Written from a
##        per-hit rule, it acts on the enemy being hit. Writes cost no points and don't count as
##        blocks: the registry should never push a script out of its efficiency tier.
## READ   a VarCondition, two forms (READ_KEYS):
##          when target in registry:        / not in: membership, checked per hit (Scope.HIT),
##                                            so the rule can only change damage, leech, barrier
##                                            and guard
##          when registry.size >= 3:        how many enemies are in the set, checked per cast,
##                                            any of OPS, 0 to MAX_VALUE. It changes mid-cast as
##                                            hits land, so  while registry.size < 3:  stops itself.
## GROW   a buff can grow with registry.size (ProgramEffect.ramp):
##          damage += registry.size * 2%       more enemies in the set, more damage
##        It keeps growing until it reaches the knob's limit, less the script's flat lines on that
##        knob (SkillProgram.growth_room). A knob can have one growing line. Its value sets how fast
##        it gets there, and the price follows: a share of what the whole room would cost flat,
##        from RAMP_COST_SLOW for the slowest line to RAMP_COST_FAST for the fastest. Only values
##        that can change gradually can grow (can_grow), not whole numbers like pierce.
##
## A hit reads first and writes after: its per-hit rules see the set as it was before that hit,
## then the hit's adds and removes land. So  always: registry.add(target)  with
## when target in registry:  pays out from the second hit on an enemy, not the first.
##
## A read needs a line that adds to the set, and a size comparison can't be one no size changes
## (SkillProgram.validate).

## The write operations, in the op slot of a write (ProgramEffect.op).
const WRITE_OPS := ["add", "remove"]
## The two kinds of read (VarCondition.key): membership of the enemy being hit, or the set's size.
const READ_KEYS := ["target", "size"]
## Membership operators (VarCondition.op when key is "target").
const MEMBER_OPS := ["in", "not in"]
## Size comparison operators (VarCondition.op when key is "size"), in the Act II patch puzzles' order.
const OPS := ["<", ">", "<=", ">=", "==", "!="]
## The largest size a comparison can name.
const MAX_VALUE := 99
const WRITE_KNOB := &"var"
## Seconds without landing a hit or being hit before a script's registry clears.
const CLEAR_AFTER := 10.0
## How many enemies of a growing buff make one of its knob's steps, at a value of 1: damage has 5%
## steps, so registry.size * 1% takes 5 enemies to add a step.
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
		k.display_name = "registry"
		k.kind = SkillKnob.Kind.VARIABLE
		k.step = 1.0
		k.min_steps = 0
		k.max_steps = 9999                      # writes carry no amount: steps is always 1
		k.cost_per_step = 0.0
		k.unit = ""
		_knobs.append(k)
	return _knobs


static func is_write(knob_id: StringName) -> bool:
	return knob_id == WRITE_KNOB


## True for a line that adds enemies to the set.
static func raises(e: ProgramEffect) -> bool:
	return is_write(e.knob) and e.write_op() == "add"


static func can_grow(knob: SkillKnob) -> bool:
	return knob != null and not knob.always_only \
			and (knob.kind == SkillKnob.Kind.DAMAGE or GROW_KNOBS.has(knob.id))


## How many knob steps a growing buff of `value` gives at this size, up to `room`.
static func ramp_steps(count: int, value: int, room: int) -> float:
	return clampf(float(count) * value / RAMP_PER_STEP, 0.0, float(maxi(room, 0)))


## The size at which a growing buff of `value` fills `room`.
static func ramp_reach(value: int, room: int) -> int:
	return ceili(float(room) * RAMP_PER_STEP / maxi(value, 1))


## The share of its room's flat price a growing buff pays.
static func ramp_cost_share(value: int, room: int) -> float:
	if room <= 1:
		return RAMP_COST_FAST
	return lerpf(RAMP_COST_SLOW, RAMP_COST_FAST, clampf(float(value - 1) / (room - 1), 0.0, 1.0))


static func compare(value: int, op: String, n: int) -> bool:
	match op:
		"<": return value < n
		">": return value > n
		"<=": return value <= n
		">=": return value >= n
		"==": return value == n
		"!=": return value != n
	return false


# ---------- THE SET ----------

## The key an enemy has in the set, or null for something that isn't an enemy (a prop, nothing).
static func entry_key(target: Node) -> Variant:
	if target == null or not is_instance_valid(target) or target.is_in_group(&"breakables"):
		return null
	return target.get_instance_id()


static func has(store: Dictionary, target: Node) -> bool:
	var at: Variant = entry_key(target)
	return at != null and store.has(at)


## Applies a write to `target`. Returns true when the set changed.
static func write(store: Dictionary, e: ProgramEffect, target: Node) -> bool:
	var at: Variant = entry_key(target)
	if at == null:
		return false
	if e.write_op() == "add":
		if store.has(at) or SkillBehavior.is_dead(target):
			return false
		store[at] = true
		return true
	return store.erase(at)


## How many enemies are in the set.
static func size_of(store: Dictionary) -> int:
	prune(store)
	return store.size()


## Drops enemies that died or left: the set only holds the living.
static func prune(store: Dictionary) -> void:
	for k in store.keys():
		var node := instance_from_id(k) as Node if k is int else null
		if node == null or not node.is_inside_tree() or SkillBehavior.is_dead(node):
			store.erase(k)
