class_name OverflowLock
extends PortLock
## OVERFLOW (The Overflow, Hex's Stack Crawler): a buffer with no bounds check. It holds
## `buffer_size` hits per write; a write is one cast and everything it does: its loop's repeats
## (ProgramLoopRunner), its projectiles, pierces and splashes. A write that lands more hits than
## the buffer holds overflows it (see PortLock): the port opens for `open_seconds`, the write's
## held damage lands at once, and the buffer SPILLS, a ring of corrupted data that hits everyone
## in `spill_radius` for `spill_damage` of their life after `spill_delay` seconds (barrier and
## guard soak it, like any hit). A write that stops short does nothing: "WRITE 3/5 // HOLDS".
## The answer is volume in one cast: a loop to the cap (a single-target skill's 6th hit is the
## repeat where  when stack_overflow:  fires), or a loop on a skill that fires several projectiles.
## A plain fast attack lands one hit per cast, so it never overflows, however fast it is.
## Surviving the spill is the defensive half: step out of the ring, or script barrier or guard
## (when hit_recently(), when my_life_below()) to stand in it.
##     "WRITE 3/5"                          a write is filling the buffer (now and then)
##     "WRITE 4/5 // BUFFER HOLDS"          it ended short
##     "BUFFER HOLDS // 1 HIT A CAST"       plain one-hit casts (now and then)
##     "BUFFER OVERFLOW // PORT OPEN"       it ran past the end
##     "SPILL"                              the ring reached its edge

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "OVERFLOW"
const HINT := "Its buffer holds 5 hits per cast. Land 6 or more with one cast (a loop to the cap, or several projectiles) and it overflows. Then stand clear of the spill, or shield up."

## Hits one write can land before the buffer overflows (the next one does it).
@export var buffer_size := 5
## Seconds after a write's last hit (and its loop's end) before it counts as finished.
@export var tail_time := 0.5
## Seconds the port stays open after an overflow.
@export var open_seconds := 6.0
@export var spill_radius := 7.0
## Share of each player's maximum life the spill takes (before barrier and guard).
@export_range(0.0, 0.8, 0.05) var spill_damage := 0.25
## Seconds the spill's ring takes to reach its edge: the time to step out.
@export var spill_delay := 1.0

const FILL_GAP := 0.35                           # seconds between "WRITE n/5" pops
const SHORT_GAP := 1.8                           # seconds between "1 HIT A CAST" pops
const MAX_WRITE := 6.0                           # seconds: a loop never reporting its end can't hold one open
const COL_SPILL := Color(1.0, 0.35, 0.3)

## The writes under way: key (HitFacts.loop_id, or the cast_id of a cast without a loop) ->
## {hits, held, last, started, loop (true when the key is a loop)}
var _writes := {}
var _best := 0                                   # the fullest write right now, for the tag


## On its tag: how full the fullest write is.
func tag_state() -> String:
	if is_open():
		return "OPEN"
	return "%d/%d" % [_best, buffer_size] if _best > 0 else ""


func modify_incoming(info: HitInfo) -> void:
	super(info)
	if not info.absorbed:
		return                                       # the port is open: hits land as usual
	var f := info.facts
	if f == null:
		return
	var key := f.loop_id if f.loop_id != "" else f.cast_id   # every repeat of a loop is the same write
	var w: Dictionary = _writes.get(key, {"hits": 0, "held": 0.0, "last": _now(), "started": _now(),
			"loop": f.loop_id != ""})
	w["hits"] = int(w["hits"]) + 1
	w["held"] = float(w["held"]) + info.damage
	w["last"] = _now()
	_writes[key] = w
	_best = maxi(_best, int(w["hits"]))
	if int(w["hits"]) > buffer_size:
		_overflow(float(w["held"]))
		return
	if int(w["hits"]) >= 2:                          # one hit a cast is told when it ends (_closed_process)
		pop("WRITE %d/%d" % [w["hits"], buffer_size], COL_SHORT, FILL_GAP)


func _closed_process(_delta: float) -> void:
	_best = 0
	for key: String in _writes.keys():
		var w: Dictionary = _writes[key]
		var looping: bool = w["loop"] and HitFacts.loop_running(key)   # its loop still repeating
		if looping and _now() - float(w["started"]) < MAX_WRITE:
			w["last"] = _now()                         # still repeating: the write isn't done
		if _now() - float(w["last"]) > tail_time:
			_writes.erase(key)
			if int(w["hits"]) >= 2:
				fail("WRITE %d/%d // BUFFER HOLDS" % [w["hits"], buffer_size], COL_SHORT)
			else:                                    # plain attacks: one hit a cast, said now and then
				pop("BUFFER HOLDS // 1 HIT A CAST", Color(COL_REJECT, 0.85), SHORT_GAP)
			continue
		_best = maxi(_best, int(w["hits"]))


func _overflow(held: float) -> void:
	_writes.clear()
	_best = 0
	open_port("BUFFER OVERFLOW // PORT OPEN", held, open_seconds)
	_spill()


func _on_closed() -> void:
	_writes.clear()
	_best = 0


# ---------- THE SPILL ----------
## A flat ring grows from the boss to spill_radius over spill_delay, then everyone inside is hit
## (LockBlast.ring; armour ignored, barrier and guard still soak it).
func _spill() -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	LockBlast.ring(enemy.get_parent(), enemy.global_position, spill_radius, spill_delay, spill_damage,
		COL_SPILL, true, func() -> void: say("SPILL", COL_SPILL, 1.1))
