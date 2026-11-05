class_name BroodLock
extends PortLock
## BROOD LINK: the boss is shielded by the brood it summons (its Summoner, see PortLock). While
## any of a wave is alive, or before its first wave, every hit on the boss is absorbed. Kill the
## whole wave and the link is cut: the port opens until the next wave arrives (or for
## `open_time`, whichever ends first), then the new brood links it again.
## Hitting the Queen while her Glitchlings live does nothing: the answer is to clear the swarm,
## an area skill or a script that hits everyone round you (enemies_nearby()), then the Queen.
##     "BROOD LINK // 3 ALIVE"      a hit while the brood shields her (now and then)
##     "BROOD CUT // PORT OPEN"     the last of the wave died
##     "BROOD LINKED"               a new wave arrived and closed the port

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "BROOD LINK"
const HINT := "Her brood shields her. Kill every Glitchling of the wave, then hit her while the port is open."

const LINK_GAP := 1.2                            # seconds between "BROOD LINK" pops

var _summoner: Summoner
var _brood: Array = []
var _waves := 0


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	for n in enemy.find_children("*", "", true, false):
		if n is Summoner:
			_summoner = n
			break
	if _summoner == null:
		push_warning("BroodLock on %s: no Summoner in its model, the port never opens" % enemy.name)
		return
	open_time = maxf(_summoner.interval, 1.0)        # the window lasts till the next wave at most
	_summoner.summoned.connect(_on_summoned)


## Brood members still alive.
func alive() -> int:
	var n := 0
	for e in _brood:
		if is_instance_valid(e) and not SkillBehavior.is_dead(e):
			n += 1
	return n


func modify_incoming(info: HitInfo) -> void:
	super(info)
	if not info.absorbed:
		return
	var left := alive()
	var text := "BROOD LINK // BROOD INCOMING" if _waves == 0 else "BROOD LINK // %d ALIVE" % left
	pop(text, Color(COL_REJECT, 0.85), LINK_GAP)


func _on_summoned(wave: Array) -> void:
	if wave.is_empty():
		return
	_waves += 1
	_brood.assign(_brood.filter(func(e) -> bool: return is_instance_valid(e) and not SkillBehavior.is_dead(e)))
	_brood.append_array(wave)
	if is_open():
		close_port("BROOD LINKED")


func _closed_process(_delta: float) -> void:
	if _waves > 0 and not _brood.is_empty() and alive() == 0:
		_brood.clear()
		open_port("BROOD CUT // PORT OPEN")
