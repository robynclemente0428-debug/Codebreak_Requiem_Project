class_name OverflowLock
extends PortLock
## OVERFLOW (The Overflow, Hex's Stack Crawler): its buffer holds against anyone at healthy life.
## Only a player whose life is at or below `life_threshold` gets through (see PortLock): while
## any player is that low, its port is open and it glows. Fighting at full life does nothing.
## The answer is a script that keeps you alive down there: a when my_life_below() rule with
## leech, barrier or guard, and damage for the window.
##     "BUFFER HOLDS // LIFE 82% > 50%"     a hit from a player above the line (now and then)
##     "BUFFER OVERFLOW // PORT OPEN"       a player dropped to the line
##     "BUFFER STABLE // PORT CLOSED"       nobody is that low any more

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "OVERFLOW"
const HINT := "Hits only land while you are at half life or lower. Script leech, barrier or guard to survive down there."

## Share of max life a player must be at (or under) for their hits to land.
@export_range(0.1, 0.9, 0.05) var life_threshold := 0.5

const HOLD_GAP := 1.5                            # seconds between "BUFFER HOLDS" pops

var _was_open := false


func is_open() -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		var hp := p.get("health") as HealthComponent
		if hp != null and hp.current_health > 0.0 and life_ratio(hp) <= life_threshold:
			return true
	return false


## Open for as long as someone stays low: the banner's bar stays full.
func open_fraction() -> float:
	return 1.0 if is_open() else 0.0


func modify_incoming(info: HitInfo) -> void:
	var caster: Node = info.cast.caster if info.cast != null and info.cast.is_valid() else null
	var hp := _owner_health(caster)
	if hp != null and life_ratio(hp) <= life_threshold:
		return                                        # low enough: the hit overflows the buffer
	info.absorbed = true
	if hp != null:
		pop("BUFFER HOLDS // LIFE %d%% > %d%%" % [roundi(life_ratio(hp) * 100.0), roundi(life_threshold * 100.0)],
			COL_SHORT, HOLD_GAP)
	else:
		pop("BUFFER HOLDS", COL_SHORT, HOLD_GAP)


func _process(_delta: float) -> void:
	if not is_instance_valid(enemy):
		return
	var open := is_open()
	if open and not _was_open:
		say("BUFFER OVERFLOW // PORT OPEN", COL_OPEN, 1.25)
		SoundManager.play_ui(SOUND_OPEN, -2.0)
	elif not open and _was_open:
		say("BUFFER STABLE // PORT CLOSED", Color(COL_OPEN, 0.7), 0.8)
	_was_open = open
	_set_glow((0.75 + 0.25 * sin(Time.get_ticks_msec() / 160.0)) if open else 0.0)


static func life_ratio(hp: HealthComponent) -> float:
	if hp.stats == null:
		return 1.0
	return hp.current_health / maxf(hp.stats.get_stat(StatTypes.Stat.MAX_HEALTH), 1.0)


## The health of the player behind a hit: the caster, or the player that owns a hologram.
func _owner_health(caster: Node) -> HealthComponent:
	if caster != null and caster.is_in_group("players"):
		return caster.get("health") as HealthComponent
	var p := get_tree().get_first_node_in_group("players")
	return p.get("health") as HealthComponent if p != null else null
