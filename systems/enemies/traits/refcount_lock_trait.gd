class_name RefcountLock
extends PortLock
## REFCOUNT (The Leak, in the Heap): memory that was never freed. It splits into blobs, and its
## refcount is how many are still out there, leaked ones on their way back included. While the
## count is above 0 every hit on the core is absorbed and each blob feeds it.
##   a blob killed on its own                       LEAKED: a new blob soon after
##   three or more killed within `free_window`      FREED: gone for good
## Any skill counts: an area hit, a cleave, a chain, explosions, a scripted loop, or plain speed.
## (With fewer than three left, killing them all inside the window frees them.)
## Refcount 0 opens the port until the next split: when `open_time` runs out, or when another
## `split_every` of its life is gone.
##     "REFCOUNT 4"             a hit while blobs are out (now and then)
##     "LEAKED" / "3 FREED"     what a blob's death did
##     "REFCOUNT 0 // PORT OPEN"

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "REFCOUNT"
const HINT := "Blobs killed one at a time come back. Kill 3 or more within 2 seconds, then hit the core."

const BLOB_PATH := "res://data/enemies/leak_blob.tres"
const COL_FREED := Color(0.45, 1.0, 0.6)
const LOCKED_GAP := 1.2

## Metres: it splits for the first time once a player is this close.
@export var notice_range := 16.0
@export var blobs_per_split := 5
## Share of its life between splits.
@export var split_every := 0.2
## Kills inside the window that free blobs (fewer if fewer are left).
@export var free_hits := 3
## Seconds from a blob's death for the others to die with it. The hint quotes this.
@export var free_window := 2.0
## Seconds before a leaked blob comes back.
@export var leak_delay := 4.0
## Share of its life each living blob feeds it per second.
@export var heal_per_blob := 0.002
@export var spawn_radius := 4.0

var freed_count := 0                             # for the test, and a HUD readout
var leaked_count := 0

var _blobs: Array = []
var _respawns: Array[float] = []                 # seconds left, one per leaked blob
var _batch_kills := 0                            # dead this window, not freed yet
var _batch_left := 0.0                           # seconds left in the window
var _batch_met := false                          # this window has freed blobs
var _settling := false
var _splits := 0
var _next_split_life := 0.0
var _dead := false


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	open_time = 7.0
	_next_split_life = 1.0 - split_every
	var hp := enemy.get("health") as HealthComponent
	if hp != null:
		hp.died.connect(_on_died)


## Blobs alive, and leaked ones due back.
func refcount() -> int:
	return _alive().size() + _respawns.size() + _batch_kills


func modify_incoming(info: HitInfo) -> void:
	super(info)
	if info.absorbed:
		pop("REFCOUNT %d" % refcount(), Color(COL_REJECT, 0.85), LOCKED_GAP)


## A hit landed on the core: a further share of its life gone splits it again.
func after_hit(info: HitInfo) -> void:
	if _dead or info.absorbed or not info.landed or info.killed:
		return
	var life := _life_share()
	if life > _next_split_life:
		return
	while _next_split_life >= life:
		_next_split_life -= split_every
	if is_open():
		close_port("")                               # _on_closed splits it
	else:
		_split()


func _process(delta: float) -> void:
	if _dead or not is_instance_valid(enemy):
		return
	if _batch_left > 0.0:
		_batch_left -= delta
		if _batch_left <= 0.0:
			_close_batch()
	var i := _respawns.size() - 1
	while i >= 0:
		_respawns[i] -= delta
		if _respawns[i] <= 0.0:
			_respawns.remove_at(i)
			_spawn_blob()
		i -= 1
	super(delta)


func _closed_process(delta: float) -> void:
	if _dead:
		return
	if _splits == 0:
		if player_within(notice_range) != null:      # any player in range (co-op: a guest's too)
			_split()
		return
	var alive := _alive().size()
	if alive > 0:
		var hp := enemy.get("health") as HealthComponent
		if hp != null:
			hp.heal(max_health() * heal_per_blob * alive * delta)
	if refcount() == 0:
		open_port("REFCOUNT 0 // PORT OPEN")


## The port's time ran out: a new allocation.
func _on_closed() -> void:
	if not _dead and refcount() == 0:
		_split()


func _split() -> void:
	_splits += 1
	say("ALLOCATING // REFCOUNT %d" % (refcount() + blobs_per_split), COL_REJECT, 1.0)
	for i in blobs_per_split:
		_spawn_blob(TAU * float(i) / float(blobs_per_split))


func _spawn_blob(angle := -1.0) -> void:
	var def := load(BLOB_PATH) as EnemyDefinition
	if def == null or not is_instance_valid(enemy):
		return
	var a := randf() * TAU if angle < 0.0 else angle
	var at := enemy.global_position + Vector3(cos(a), 0.0, sin(a)) * spawn_radius
	var nav := enemy.get("nav") as NavigationAgent3D
	if nav != null and nav.get_navigation_map().is_valid() \
			and NavigationServer3D.map_get_iteration_id(nav.get_navigation_map()) > 0:
		var snapped := NavigationServer3D.map_get_closest_point(nav.get_navigation_map(), at)
		if snapped != Vector3.ZERO:
			at = snapped
	var level: int = enemy.get("level") if enemy.get("level") != null else 1
	var e := EnemySpawner.spawn_enemy(def, "normal", enemy.get_parent(), at + Vector3.UP * 0.1, level, [])
	if e == null:
		return
	if e.get("ai") != null:
		e.ai.aggro_range = 40.0                      # they know where you are
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers != null:
		numbers.track(e.health)
	_blobs.append(e)
	e.health.died.connect(_on_blob_died.bind(e))


## A blob's health ran out. The first kill opens a window of `free_window` seconds, and every kill
## inside it counts together, whatever did it. Settled at the end of the frame, because an area
## hit kills several in the same frame and should only say so once.
func _on_blob_died(_blob: Node3D) -> void:
	if _dead:
		return
	if _batch_left <= 0.0:
		_batch_left = free_window
		_batch_met = false
	_batch_kills += 1
	if not _settling:
		_settling = true
		_settle.call_deferred()


## Enough kills in this window: they're freed, and so is any more inside it.
func _settle() -> void:
	_settling = false
	if _dead or _batch_kills == 0:
		return
	if not _batch_met and _batch_kills < mini(free_hits, refcount()):
		return                                       # not yet: the window may still get there
	_batch_met = true
	freed_count += _batch_kills
	say("%d FREED" % _batch_kills, COL_FREED, 0.95)
	GameEvents.report("blobs_freed", "the_leak", _batch_kills)
	_batch_kills = 0


## The window ran out: whatever wasn't freed leaks back.
func _close_batch() -> void:
	var leaked := _batch_kills
	_batch_kills = 0
	_batch_met = false
	if leaked == 0:
		return
	leaked_count += leaked
	for i in leaked:
		_respawns.append(leak_delay)
	say("LEAKED // %d BACK SOON" % leaked if leaked > 1 else "LEAKED // BACK SOON", COL_SHORT, 0.95)


func _alive() -> Array:
	_blobs.assign(_blobs.filter(func(e) -> bool: return is_instance_valid(e) and not SkillBehavior.is_dead(e)))
	return _blobs


func _life_share() -> float:
	var hp := enemy.get("health") as HealthComponent
	return hp.current_health / maxf(max_health(), 1.0) if hp != null else 1.0


## It dies: everything it allocated goes with it.
func _on_died() -> void:
	_dead = true
	_respawns.clear()
	for e in _alive():
		e.health.current_health = 0.0
		e.health.died.emit()
	_blobs.clear()
