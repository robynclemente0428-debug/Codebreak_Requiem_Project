class_name GrammarLock
extends PortLock
## GRAMMAR (Null Weaver Prime): it speaks a rule in the Null's grammar, two conditions joined by
## AND, and only a cast that answers in the same grammar gets through (see PortLock). The answer
## is one WHEN rule holding exactly those two conditions, firing on the cast that hits it. Any
## other cast is noise: absorbed. A right answer opens the port; when it closes, it speaks again,
## and never the same sentence twice in a row. Vesper translates each one as it's spoken.
##     "SPEAKS: WHEN ENEMIES NEARBY AND MY LIFE BELOW"   a new sentence (and on the lock banner)
##     "WRONG GRAMMAR // HEARD: HIT RECENTLY"            a cast whose rules didn't say it
##     "GRAMMAR ACCEPTED // PORT OPEN"                   the right rule fired on the hit

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "GRAMMAR"
const HINT := "It speaks a rule: two conditions joined by AND. Answer with one WHEN rule holding exactly those two, firing on the hit. Swap script sets as it changes."

## Its sentences: CAST-scope conditions the player can satisfy against it, two per rule.
const SENTENCES := [
	{"ids": ["enemies_nearby", "caster_life_below"], "vesper": "when they're close, and you're bleeding"},
	{"ids": ["enemies_nearby", "hit_recently"], "vesper": "when they're close, and it has just touched you"},
	{"ids": ["hit_recently", "every_nth_cast"], "vesper": "when it has touched you, and on the beat"},
	{"ids": ["enemies_attacking_me", "caster_life_below"], "vesper": "when they're all on you, and you're bleeding"},
]
const WORDS := {
	"enemies_nearby": "ENEMIES NEARBY",
	"caster_life_below": "MY LIFE BELOW",
	"hit_recently": "HIT RECENTLY",
	"every_nth_cast": "EVERY NTH CAST",
	"enemies_attacking_me": "ENEMIES ATTACKING ME",
}
const COL_GRAMMAR := Color(0.85, 0.6, 1.0)
const COL_VESPER := Color(0.78, 0.55, 1.0)
const WRONG_GAP := 1.3

## Seconds before it speaks first, once it has noticed someone.
@export var first_delay := 2.5
## A sentence it hasn't been answered in this long is replaced by another.
@export var speak_every := 22.0

var sentence := -1                               # index in SENTENCES (-1 = not spoken yet)
var _left := -1.0                                # < 0 = it hasn't noticed anyone yet


## The two condition ids it wants now ([] before it has spoken).
func wanted() -> Array:
	return SENTENCES[sentence]["ids"] if sentence >= 0 else []


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	open_time = 5.0


func modify_incoming(info: HitInfo) -> void:
	super(info)
	if not info.absorbed:
		return
	if sentence < 0:
		pop("SILENCE // IT HASN'T SPOKEN", Color(COL_GRAMMAR, 0.7), WRONG_GAP)
		return
	if info.cast == null or not info.cast.is_valid():
		return
	if answers(info.cast, wanted()):
		info.absorbed = false                     # the answer itself lands
		open_port("GRAMMAR ACCEPTED // PORT OPEN")
		return
	var heard: Array = []
	for id in ProgramSupport.fired_conditions(info.cast):
		heard.append(WORDS.get(id, str(id).replace("_", " ").to_upper()))
	fail("WRONG GRAMMAR // HEARD: %s" % (" + ".join(PackedStringArray(heard)) if not heard.is_empty() else "NOTHING"),
		Color(COL_REJECT, 0.9))


## True when one of the cast's WHEN rules holds exactly `ids` and both of them fired.
static func answers(cast: SkillCast, ids: Array) -> bool:
	if ids.size() != 2:
		return false
	var fired: Array = ProgramSupport.fired_conditions(cast)
	if not (ids[0] in fired and ids[1] in fired):
		return false
	var support := ProgramSupport.of(cast.skill)
	if support == null or support.program == null:
		return false
	for rule in support.program.flat_rules():
		if rule.conditions.size() != 2:
			continue
		var have := [rule.conditions[0].type_id(), rule.conditions[1].type_id()]
		if ids[0] in have and ids[1] in have:
			return true
	return false


func _closed_process(delta: float) -> void:
	if _left < 0.0:
		var ai = enemy.get("ai")
		if ai != null and ai.state != AIComponent.State.IDLE:
			_left = first_delay                   # noticed a player: it speaks soon
		return
	_left -= delta
	if _left <= 0.0:
		_speak()


func _on_closed() -> void:
	_speak()


func _speak() -> void:
	var pick := randi() % SENTENCES.size()
	if pick == sentence:
		pick = (pick + 1) % SENTENCES.size()
	sentence = pick
	_left = speak_every
	var ids: Array = SENTENCES[sentence]["ids"]
	say("SPEAKS: WHEN %s AND %s" % [WORDS[ids[0]], WORDS[ids[1]]], COL_GRAMMAR, 1.15)
	QuestItems.toast(get_tree(), "VESPER: \"It's saying: %s.\"" % SENTENCES[sentence]["vesper"], COL_VESPER)
