class_name ChecksumLock
extends PortLock
## CHECKSUM: the boss only accepts a cast whose loop repeats exactly `packets` times (see
## PortLock). It works like a receiver, in three phases:
##   RECEIVING   the first looped cast to hit it is the packet. Only that loop's repeats count
##               (the cast that started it doesn't: a FOR loop with range(2) is 2). Each repeat
##               that lands pops "LOOP 1/2", "LOOP 2/2"... A repeat counts once however many
##               projectiles, pierces or follow-ups it lands, so more bullets add nothing.
##   VERIFYING   once that loop has finished: "PACKET RECEIVED // VERIFYING...". For
##               `verify_time` seconds it takes nothing in: every hit is absorbed and ignored,
##               looped or not. So the player can keep attacking; nothing they do now spoils it.
##   VERDICT     "CHECKSUM OK // PORT OPEN"    exactly right: the packet's damage lands at once
##               "1/2 LOOPS"                   too few repeats landed (a missed repeat is missing)
##               "3/2 REJECTED"                too many
##               Then it listens again: the next looped cast to hit it is the next packet.
## While it is receiving one loop, other loops (a second cast) are ignored, not mixed in, and a
## loop it has already seen (one that hit it while it was busy) never becomes the next packet
## half-way through: only a fresh cast does, so the count is always the whole loop. Hits
## from a cast with no loop never start a packet: "LOCKED // LOOPS ONLY" now and then.

## A packet was judged: `count` loop repeats, out of the `packets` wanted (equal = the port opened).
signal burst_resolved(count: int, packets: int)

## Loop repeats a packet must have (the N in "for i in range(N)").
@export var packets := 2
## After its loop finishes, the packet still waits this long for the last repeat's hits to land
## (a Blast repeat flies, then explodes) before verifying.
@export var tail_time := 0.4
## Seconds spent verifying a packet: everything is ignored meanwhile.
@export var verify_time := 1.0

enum Phase { LISTENING, RECEIVING, VERIFYING }

const LOCKED_GAP := 1.5                          # seconds between "LOOPS ONLY" pops
const IGNORED_GAP := 1.2                         # seconds between "VERIFYING" reminders
const MAX_PACKET := 6.0                          # seconds: a loop never reporting its end can't hold it
const COL_VERIFY := Color(0.55, 0.85, 1.0)

var phase := Phase.LISTENING
var _loop: ProgramLoopRunner                    # the loop being received
var _repeats_seen: Array = []                    # its repeats that landed
var _held := 0.0                                 # its damage, released if the checksum passes
var _last_hit := 0.0
var _started := 0.0
var _verify_left := 0.0
var _seen: Array = []                            # recent loops that hit it (never a packet twice)
const SEEN_KEEP := 12


## The packet so far (for a HUD readout): repeats counted, repeats wanted.
func progress() -> Vector2i:
	return Vector2i(_repeats_seen.size(), packets)


func modify_incoming(info: HitInfo) -> void:
	super(info)
	var runner := _runner_of(info.cast)
	if not info.absorbed:
		_mark_seen(runner)                              # in flight as the port closes: not a packet
		return                                          # the port is open: hits land as usual
	match phase:
		Phase.VERIFYING:
			_mark_seen(runner)
			pop("VERIFYING...", Color(COL_VERIFY, 0.8), IGNORED_GAP)
			return                                      # taking nothing in
		Phase.LISTENING:
			if runner == null:
				pop("LOCKED // LOOPS ONLY", Color(COL_REJECT, 0.85), LOCKED_GAP)
				return
			if runner in _seen:
				return                                  # already under way when it was busy
			_begin(runner)
		Phase.RECEIVING:
			if runner != _loop:
				_mark_seen(runner)
	# RECEIVING: only this packet's loop counts
	if runner != _loop:
		return
	_held += info.damage
	_last_hit = _now()
	var cast := info.cast
	if cast.extra.get("loop_repeat", false) and not cast.extra.get("forked", false) \
			and not (cast in _repeats_seen):
		_repeats_seen.append(cast)
		var n := _repeats_seen.size()
		say("LOOP %d/%d" % [n, packets], COL_SHORT if n <= packets else COL_REJECT, 0.85)


func _mark_seen(runner: ProgramLoopRunner) -> void:
	if runner == null or runner in _seen:
		return
	_seen.append(runner)
	if _seen.size() > SEEN_KEEP:
		_seen.pop_front()


func _begin(runner: ProgramLoopRunner) -> void:
	_mark_seen(runner)
	phase = Phase.RECEIVING
	_loop = runner
	_repeats_seen.clear()
	_held = 0.0
	_started = _now()
	_last_hit = _now()


func _closed_process(delta: float) -> void:
	match phase:
		Phase.RECEIVING:
			var looping := _loop != null and is_instance_valid(_loop) and not _loop.finished
			if _now() - _started > MAX_PACKET:
				looping = false
			if looping:
				_last_hit = _now()                      # still repeating: the packet isn't in yet
			elif _now() - _last_hit > tail_time:
				_verify()
		Phase.VERIFYING:
			_verify_left -= delta
			if _verify_left <= 0.0:
				_resolve()


func _verify() -> void:
	phase = Phase.VERIFYING
	_verify_left = verify_time
	_loop = null
	say("PACKET RECEIVED // VERIFYING...", COL_VERIFY, 1.0)


## The packet was checked: open the port, or say how far off it was. Then listen again.
func _resolve() -> void:
	var count := _repeats_seen.size()
	var held := _held
	_repeats_seen.clear()
	_held = 0.0
	phase = Phase.LISTENING
	burst_resolved.emit(count, packets)
	if count == packets:
		open_port("CHECKSUM OK // PORT OPEN", held)    # the packet lands, all at once
	elif count < packets:
		fail("%d/%d LOOPS" % [count, packets], COL_SHORT)
	else:
		fail("%d/%d REJECTED" % [count, packets])


## The port closed again: start listening from scratch.
func _on_closed() -> void:
	phase = Phase.LISTENING
	_loop = null
	_repeats_seen.clear()
	_held = 0.0


## The loop a hit's cast belongs to (the cast that started it or one of its repeats), or null.
func _runner_of(cast: SkillCast) -> ProgramLoopRunner:
	if cast == null:
		return null
	return cast.extra.get(ProgramSupport.LOOP_KEY) as ProgramLoopRunner
