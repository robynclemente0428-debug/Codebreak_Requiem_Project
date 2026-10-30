class_name ProgramLoop
extends Resource
## A loop block inside a rule: the skill casts itself again (a "repeat") after it lands.
## Loops are core blocks, every skill has them. The rule's knob effects become the loop body:
## they only apply to the repeats this loop runs, not to the original cast.
##
##   when every_nth_cast(3):           FOR    the conditions are checked once, on the cast;
##       for i in range(2):                   then the skill repeats exactly 2 times
##           damage += 10%
##           cast()
##
##   while enemies_nearby(3, 4.0m):    WHILE  the conditions are checked again before every
##       cast(max=4)                          repeat; it stops when they turn false (or at max)
##       if killed: break              BREAK  stop early: once a repeat kills, or hits nothing
##
## Balance (see ProgramLoopRunner for the runtime side):
##   - every cast has a hard cap of repeats (BASE_CAP, For Loop gem: more). All loops of one cast
##     share it. The repeat that reaches the cap is a "stack overflow" (StackOverflowCondition).
##   - each repeat costs mana (MANA_FRACTION of the skill's cost) and deals FALLOFF times the
##     damage of the one before it. Out of mana = the loop ends.
##   - point cost by risk: FOR is guaranteed so it costs the most per repeat, WHILE might stop
##     early, BREAK can only cut a loop short. Conditions in the rule discount it like buffs.
##   - repeats never start loops, echoes or holograms of their own (they skip before_release and
##     run one level deep), so loops can't multiply with Multicast or Aftershock.

enum Mode { FOR, WHILE }
enum Break { NONE, KILL, MISS }

const BASE_CAP := 5
const FOR_COST := 6.0           # points per guaranteed repeat
const WHILE_COST := 3.5         # points per repeat of the while's max
const BREAK_COST_MULT := 0.7
const FALLOFF := 0.7            # repeat N deals FALLOFF^N of the cast's damage
const MANA_FRACTION := 0.5      # of the skill's mana cost, paid by every repeat

@export var mode: Mode = Mode.FOR
## FOR: how many repeats. WHILE: the most repeats it may run.
@export var count: int = 1
@export var break_on: Break = Break.NONE


static func make(p_mode: Mode, p_count := 1) -> ProgramLoop:
	var l := ProgramLoop.new()
	l.mode = p_mode
	l.count = p_count
	return l


## The loop block, plus one more when it has a break.
func action_count() -> int:
	return 1 + (1 if break_on != Break.NONE else 0)


## Points before the rule's condition discount. `gem_mult` is the For Loop gem's discount.
func cost(gem_mult := 1.0) -> float:
	var c := (FOR_COST if mode == Mode.FOR else WHILE_COST) * count
	if break_on != Break.NONE:
		c *= BREAK_COST_MULT
	return c * gem_mult


## "killed" / "missed": the word shown in  if killed: break
func break_word() -> String:
	return "missed" if break_on == Break.MISS else "killed"


func describe() -> String:
	var s := "repeat %dx" % count if mode == Mode.FOR else "repeat while true (max %d)" % count
	match break_on:
		Break.KILL:
			s += ", break on kill"
		Break.MISS:
			s += ", break if nothing hit"
	return s


func to_dict() -> Dictionary:
	var d := {"mode": "while" if mode == Mode.WHILE else "for", "count": count}
	if break_on != Break.NONE:
		d["break"] = "miss" if break_on == Break.MISS else "kill"
	return d


static func from_dict(d: Dictionary) -> ProgramLoop:
	var l := make(Mode.WHILE if str(d.get("mode", "for")) == "while" else Mode.FOR, int(d.get("count", 1)))
	match str(d.get("break", "")):
		"kill":
			l.break_on = Break.KILL
		"miss":
			l.break_on = Break.MISS
	return l
