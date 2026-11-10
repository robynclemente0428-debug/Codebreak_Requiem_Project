class_name NullLaws
extends RefCounted
## THE NULL LAWS (Act IV): deep in the Null Zone, AXIOM's rules come apart. One law at a time
## rewrites the world; a NullLawDirector in the zone picks them in turn and announces each.
## Every law does two things: it bends the player's SCRIPTS that use its block, and it changes
## every FIGHT, so it's felt whatever the script.
##   life_inverted    scripts: MY LIFE BELOW n% fires while life is ABOVE 100-n%  (CasterLifeBelowCondition)
##                    fights:  your hits grow as your life falls, x0.7 .. x1.6      (NullLawTouch)
##   near_is_far      scripts: ENEMIES NEARBY counts the enemies BEYOND its radius (EnemiesNearbyCondition)
##                    fights:  your hits are weak up close and strong at range, x0.6 .. x1.5 (NullLawTouch)
##   loops_plus_one   scripts: every FOR and WHILE loop repeats once more          (ProgramLoopRunner, ProgramSupport)
##                    fights:  every hit you take repeats, half as hard, a moment later (NullLawDirector)
##   counters_forget  scripts: taking a hit clears the script's registry            (ProgramSupport registers)
##                    fights:  every hit you take also drains mana                  (NullLawDirector)
## The answer is the script-set key: a set written for each law, swapped as the world changes.

## The law in force ("" = none). Set by NullLawDirector, cleared when its zone unloads.
static var law := ""

const LAWS := {
	"life_inverted": {
		"name": "LIFE READS INVERTED",
		"rule": "MY LIFE BELOW n% fires while your life is ABOVE 100-n%.",
		"effect": "Your hits grow as your life falls: weak at full life, x1.6 near death.",
		"vesper": "It's reading your life backwards. Down here, hurt reads as healthy.",
	},
	"near_is_far": {
		"name": "NEAR MEANS FAR",
		"rule": "ENEMIES NEARBY counts the enemies BEYOND its radius, not inside it.",
		"effect": "Your hits are weak up close (x0.6) and strong at range (x1.5). Keep your distance.",
		"vesper": "Distance is only a suggestion to the Null. Near is far now.",
	},
	"loops_plus_one": {
		"name": "LOOPS RUN ONCE MORE",
		"rule": "Every FOR and WHILE loop repeats one extra time, and costs mana for it.",
		"effect": "Every hit you take repeats a moment later, half as hard.",
		"vesper": "It likes your loops. It's adding to them.",
	},
	"counters_forget": {
		"name": "REGISTRY FORGETS ON HIT",
		"rule": "Taking a hit wipes your script's registry: every enemy in it is forgotten.",
		"effect": "Every hit you take also drains your mana.",
		"vesper": "Every time it touches you, it takes something back. Don't let it count you.",
	},
}
## How far "near is far" looks past the radius: enemies up to this many times the radius count.
const FAR_REACH := 4.0
## NEAR MEANS FAR in fights: the player's hits scale from NEAR_MULT at NEAR_M metres or closer
## to FAR_MULT at FAR_M metres or further.
const NEAR_M := 4.0
const FAR_M := 10.0
const NEAR_MULT := 0.6
const FAR_MULT := 1.5
## LIFE READS INVERTED in fights: the player's hits scale from FULL_MULT at full life to LOW_MULT
## at no life.
const FULL_MULT := 0.7
const LOW_MULT := 1.6
## LOOPS RUN ONCE MORE in fights: a hit taken repeats after ECHO_DELAY seconds at ECHO_SHARE of it.
const ECHO_DELAY := 0.35
const ECHO_SHARE := 0.5
## REGISTRY FORGETS ON HIT in fights: each hit taken drains this share of maximum mana.
const MANA_DRAIN := 0.06


## True while `id` is the law and `caster` is a player.
static func on(id: String, caster: Node) -> bool:
	return law == id and caster != null and is_instance_valid(caster) and caster.is_in_group("players")


## How many repeats a loop runs for this caster under the current law.
static func loop_count(loop: ProgramLoop, caster: Node) -> int:
	if loop == null:
		return 0
	return loop.count + (1 if on("loops_plus_one", caster) else 0)


static func distance_mult(metres: float) -> float:
	return lerpf(NEAR_MULT, FAR_MULT, clampf((metres - NEAR_M) / (FAR_M - NEAR_M), 0.0, 1.0))


static func inverted_life_mult(life_fraction: float) -> float:
	return lerpf(LOW_MULT, FULL_MULT, clampf(life_fraction, 0.0, 1.0))


static func effect_of(id: String) -> String:
	return str(LAWS.get(id, {}).get("effect", ""))


static func name_of(id: String) -> String:
	return str(LAWS.get(id, {}).get("name", id.to_upper()))


static func rule_of(id: String) -> String:
	return str(LAWS.get(id, {}).get("rule", ""))


static func vesper_of(id: String) -> String:
	return str(LAWS.get(id, {}).get("vesper", ""))
