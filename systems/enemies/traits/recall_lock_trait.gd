class_name RecallLock
extends EnemyTrait
## RECALL (the Core Sentinel): "it remembers every enemy you have faced". It borrows an earlier
## boss's lock for each third of its life:
##   1  BROOD LINK   (the Glitchling Queen)   its Summoner calls in Glitchlings; clear them first
##   2  CHECKSUM     (Loop Hound Alpha)       one cast that loops exactly twice
##   3  DIFF         (The Mimic)              one skill, two WHEN rules, a different one each cast
## The borrowed lock is a real trait on the Sentinel, listed in enemy.traits, so it absorbs hits
## and speaks on the lock banner itself; Recall only swaps them as its life drops.
## A burst that would skip a lock is rolled back: the Sentinel restores itself from backup to
## the middle of the next third, so every lock is met once.
##     "RECALL // CHECKSUM"      a new lock, loaded from an old boss
##     "RESTORED FROM BACKUP"    a burst went past a lock it hadn't used yet

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "RECALL"
const HINT := "It borrows old bosses' locks as it weakens: BROOD LINK, then CHECKSUM, then DIFF. Read the banner and solve each one."

const PHASES := [
	preload("res://systems/enemies/traits/brood_lock_trait.gd"),
	preload("res://systems/enemies/traits/checksum_lock_trait.gd"),
	preload("res://systems/enemies/traits/diff_lock_trait.gd"),
]
const COL_RECALL := Color(0.75, 0.5, 1.0)

var phase := -1
var _current: EnemyTrait
var _summoner: Summoner


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	for n in enemy.find_children("*", "", true, false):
		if n is Summoner:
			_summoner = n
			break
	_enter(0, false)


func _process(_delta: float) -> void:
	if not is_instance_valid(enemy) or SkillBehavior.is_dead(enemy):
		set_process(false)
		return
	var hp := enemy.get("health") as HealthComponent
	var top := max_health()
	if hp == null or top <= 0.0 or phase >= PHASES.size() - 1:
		return
	var due := clampi(int((1.0 - hp.current_health / top) * PHASES.size()), 0, PHASES.size() - 1)
	if due <= phase:
		return
	var next := phase + 1
	if due > next:                                   # a burst ran past a lock: back to the next one
		var keep := top * (1.0 - (float(next) + 0.5) / PHASES.size())
		hp.heal(keep - hp.current_health)
		say("RESTORED FROM BACKUP", COL_RECALL, 1.0)
	_enter(next, true)


func _enter(i: int, announce: bool) -> void:
	if _current != null and is_instance_valid(_current):
		if _current.has_method("_set_glow"):
			_current.call("_set_glow", 0.0)        # a port open as it's swapped out stops glowing
		enemy.traits.erase(_current)
		_current.queue_free()
	if i > 0 and _summoner != null:
		_summoner.set_process(false)             # the brood stops coming once BROOD LINK is done
	phase = i
	var t := Node.new()
	t.set_script(PHASES[i])
	t.name = "Recall_%d" % i
	enemy.add_child(t)
	_current = t as EnemyTrait
	_current.setup(enemy)
	enemy.traits.append(_current)
	if announce:
		var info := LockBannerUI.lock_info(PHASES[i])
		say("RECALL // %s" % info.get("name", "?"), COL_RECALL, 1.3)
