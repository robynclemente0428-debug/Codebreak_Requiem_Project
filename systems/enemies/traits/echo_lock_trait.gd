class_name EchoLock
extends EnemyTrait
## ECHO (the Hollow Choir, and the Echo Wisps of the Static Mire): it learns the pattern of the
## attack that gets through, the skill and the WHEN rules that fired for it (DiffLock.rules_of),
## and sends that pattern back. A new pattern lands for up to `learn_window` seconds (or until its
## burst ends), then it is learned in turn. A hit with the learned pattern is absorbed, and the
## Choir answers it: a ring of sound rolls out from it to `echo_radius` over `echo_delay` seconds,
## and anyone inside when it gets there takes `echo_damage` of their maximum life (LockBlast.ring;
## armour, barrier and guard all soak it). Sized to the player's life, not their damage, so no
## build gets one-shot by it, and only one echo ring is ever out at a time, whoever sent it.
## Script sets don't count: the same rules in another set are the same pattern.
## Three answers, all Act II tools:
##   vary it      a loop whose if changes a repeat, every_nth_cast on a second rule, two skills
##   play round   keep a simple script and step out of each ring
##   tank it      when my_life_below(): barrier or leech, for the echoes that land
##     "PATTERN LEARNED: STRIKE / ENEMIES NEARBY"    the pattern that just hit it is learned
##     "ECHO: STRIKE / NO RULE"                       a hit with the learned pattern: absorbed, sent back
##     "ECHO"                                         the ring caught someone

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "ECHO"
const HINT := "It learns the last pattern that hit it (skill + the rules that fired) and sends it back as a ring. Vary your script: a loop with an if, or a second rule. Or step out of the ring."
## Its tag and body (EnemyTrait): ice blue rings, like an echo running down it.
const LOCK_COLOR := Color(0.55, 0.8, 1.0)
const LOCK_SHAPE := "ring"
const LOCK_AURA := 1                 # EnemySilhouette.AURA_ECHO
## Longest pattern text on the tag; the hover plate shows it whole.
const TAG_MAX := 24

const COL_LEARN := Color(1.0, 0.75, 0.3)
const COL_CACHED := Color(1.0, 0.3, 0.3)
const COL_RING := Color(0.55, 0.8, 1.0)
## Seconds between "ECHO: ..." pops while a learned pattern keeps hitting.
const ECHO_POP_GAP := 0.8

## A pattern that gets through is learned this long after its first hit at the latest...
@export var learn_window := 1.4
## ...or as soon as it stops hitting for this long.
@export var learn_gap := 0.6
## The return ring: how far it reaches, how long it takes to get there (the time to step out),
## and the share of maximum life it takes.
@export var echo_radius := 6.0
@export var echo_delay := 1.0
@export_range(0.0, 0.5, 0.01) var echo_damage := 0.15

## When the ring out now has finished, for every ECHO lock: one ring at a time, whoever sent it.
static var _ring_until := 0.0

var _cached := ""
var _pending := ""
var _pending_since := 0.0
var _pending_last := 0.0


## The learned pattern ("" = none yet), for tests and a HUD readout.
func cached() -> String:
	return _cached


## On its tag: the pattern it now sends back ("NOT STRIKE/ENEMIES NEARBY").
func tag_state() -> String:
	if _cached == "":
		return ""
	var s := "NOT " + _label(_cached).replace(" / ", "/")
	return s if s.length() <= TAG_MAX else s.left(TAG_MAX - 3) + "..."


func modify_incoming(info: HitInfo) -> void:
	var p := pattern_of(info)
	if p == "":
		return
	var now := _now()
	if p == _cached:
		info.absorbed = true
		pop("ECHO: %s" % _label(p), COL_CACHED, ECHO_POP_GAP)
		_send_back()
		return
	if p != _pending:
		if _pending != "":
			_learn()                                    # two new patterns at once: the older is learned
		_pending = p
		_pending_since = now
	_pending_last = now


func _process(_delta: float) -> void:
	if _pending == "" or not is_instance_valid(enemy):
		return
	var now := _now()
	if now - _pending_since > learn_window or now - _pending_last > learn_gap:
		_learn()


func _learn() -> void:
	_cached = _pending
	_pending = ""
	say("PATTERN LEARNED: %s" % _label(_cached), COL_LEARN, 0.95)


## The ring of sound, if none is out already (from this lock or any other).
func _send_back() -> void:
	var now := _now()
	if now < _ring_until or not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	_ring_until = now + echo_delay + 0.4
	LockBlast.ring(enemy.get_parent(), enemy.global_position, echo_radius, echo_delay, echo_damage,
		COL_RING, false, func() -> void: say("ECHO", COL_RING, 1.1))


## "strike|enemies_nearby": the skill gem and the WHEN rules that fired for the cast (none: "").
## "" for hits that aren't from a skill.
func pattern_of(info: HitInfo) -> String:
	if info.facts == null or info.facts.gem_id == "":   # not from a skill gem
		return ""
	return "%s|%s" % [info.facts.gem_id, DiffLock.rules_of(info.facts)]


## "STRIKE / ENEMIES NEARBY", "STRIKE / NO RULE"
func _label(p: String) -> String:
	var bits := p.split("|")
	var rules := bits[1] if bits.size() > 1 else ""
	var said := "NO RULE" if rules == "" else rules.replace("_", " ").replace(",", " + ").to_upper()
	return "%s / %s" % [bits[0].replace("_", " ").to_upper(), said]


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
