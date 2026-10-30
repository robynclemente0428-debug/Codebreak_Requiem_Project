class_name DungeonInstance
extends RefCounted
## One running dungeon instance. It is only a small record: the numbers needed to rebuild the
## same dungeon, plus which enemies are already dead. The scene itself is thrown away when you
## leave and rebuilt from this record when you come back (see WorldState).

var id := 0
var scene_path := ""                    # which dungeon scene this instance belongs to
var level := 1
var rng_seed := 0                       # same seed = same corridors, same enemies, same rolls
var created_msec := 0
var occupants := 0                      # players inside right now
var empty_since_msec := 0               # when the last player left (only meaningful at 0 occupants)
var killed: Dictionary = {}             # enemy index -> true, so dead enemies stay dead
var opened: Dictionary = {}             # prop index -> true, so looted barrels stay looted


## Seconds the instance has been empty (0 while anyone is inside).
func seconds_empty() -> float:
	if occupants > 0:
		return 0.0
	return (Time.get_ticks_msec() - empty_since_msec) / 1000.0


## For a gate's list of open dungeons: "closes in 07:42".
func seconds_until_close(timeout_sec: float) -> float:
	if occupants > 0:
		return timeout_sec
	return maxf(timeout_sec - seconds_empty(), 0.0)
