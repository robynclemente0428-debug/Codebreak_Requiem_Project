extends Node
## Autoload: WorldState
## Keeps track of dungeon instances while the game is running.
##
## An instance opens when a player goes through a dungeon portal (a Portal with dungeon_level
## above 0). It stays open while anyone is inside, and closes once it has been EMPTY for
## EMPTY_TIMEOUT_SEC. Going back through the same portal before that rejoins it: same layout,
## same enemies, dead ones stay dead. Quitting the game closes every instance (memory only).

signal instance_created(instance: DungeonInstance)
signal instance_closed(instance: DungeonInstance)

const EMPTY_TIMEOUT_SEC := 600.0        # 10 minutes with nobody inside
const MAX_INSTANCES := 5                # oldest empty instance closes first when this is exceeded
const CHECK_EVERY_SEC := 1.0

## instance_id values for prepare_dungeon():
const REJOIN_OR_NEW := 0                # rejoin the open instance of that dungeon, or open one
const ALWAYS_NEW := -1                  # always a fresh instance

var instances: Dictionary = {}          # id -> DungeonInstance
var _next_id := 1
var _pending: DungeonInstance           # chosen before travelling, picked up by the dungeon scene
var _timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_EVERY_SEC:
		return
	_timer = 0.0
	close_expired()


## Call BEFORE travelling to a dungeon scene (AreaManager.go_to does this for portals).
##   instance_id REJOIN_OR_NEW (0): the open instance of this dungeon at this level, else a new one
##   instance_id ALWAYS_NEW (-1):   a brand new instance
##   instance_id above 0:           that exact instance, if it is still open
func prepare_dungeon(scene_path: String, level: int, instance_id: int = REJOIN_OR_NEW) -> DungeonInstance:
	scene_path = Waypoints.normalize(scene_path)     # uid:// and res:// spellings share instances
	var inst: DungeonInstance = null
	if instance_id > 0:
		inst = instances.get(instance_id)
	elif instance_id == REJOIN_OR_NEW:
		inst = find_open(scene_path, level)
	if inst == null:
		inst = _create(scene_path, level)
	_pending = inst
	return inst


## Co-op, on a client: the host's instance for the trip that's about to happen. Same id and seed
## here, so this machine builds the same dungeon, minus the enemies the host has seen die.
func adopt(id: int, scene_path: String, level: int, rng_seed: int, killed: Array) -> DungeonInstance:
	scene_path = Waypoints.normalize(scene_path)
	var inst: DungeonInstance = instances.get(id)
	if inst == null or inst.scene_path != scene_path or inst.rng_seed != rng_seed:
		inst = DungeonInstance.new()
		inst.id = id
		inst.scene_path = scene_path
		inst.level = level
		inst.rng_seed = rng_seed
		inst.threats = DungeonThreats.roll_for(scene_path, rng_seed)
		inst.created_msec = Time.get_ticks_msec()
		inst.empty_since_msec = inst.created_msec
		instances[id] = inst
		_next_id = maxi(_next_id, id + 1)
	for index in killed:
		inst.killed[int(index)] = true
	_pending = inst
	return inst


## Re-enter an instance you already have (used when respawning after death).
func prepare_rejoin(inst: DungeonInstance) -> void:
	if inst != null and instances.has(inst.id):
		_pending = inst


## The open instance of a dungeon at a level, or null. The newest one when there are several
## (after a Ctrl + click reset, going back in should take you to the fresh one, not the old one).
func find_open(scene_path: String, level: int) -> DungeonInstance:
	scene_path = Waypoints.normalize(scene_path)
	var best: DungeonInstance = null
	for inst: DungeonInstance in instances.values():
		if inst.scene_path == scene_path and inst.level == level and (best == null or inst.id > best.id):
			best = inst
	return best


## Called by the dungeon scene in _ready(). Returns the instance chosen before travelling,
## or makes a fresh one when the dungeon is entered some other way (or run on its own).
func begin_visit(scene_path: String, default_level: int = 1) -> DungeonInstance:
	scene_path = Waypoints.normalize(scene_path)
	var inst := _pending
	_pending = null
	if inst == null:
		inst = _create(scene_path, default_level)
	inst.occupants += 1
	return inst


## Called by the dungeon scene in _exit_tree(). Starts the closing countdown when it is empty.
func end_visit(inst: DungeonInstance) -> void:
	if inst == null:
		return
	inst.occupants = maxi(inst.occupants - 1, 0)
	if inst.occupants == 0:
		inst.empty_since_msec = Time.get_ticks_msec()


## For a gate screen that lists the open dungeons with their remaining time.
func active_instances() -> Array[DungeonInstance]:
	var out: Array[DungeonInstance] = []
	for inst in instances.values():
		out.append(inst)
	return out


func close_expired() -> void:
	for id in instances.keys():
		var inst: DungeonInstance = instances[id]
		if inst.occupants == 0 and inst != _pending and inst.seconds_empty() >= EMPTY_TIMEOUT_SEC:
			_close(inst)


func _create(scene_path: String, level: int) -> DungeonInstance:
	_make_room()
	var inst := DungeonInstance.new()
	inst.id = _next_id
	_next_id += 1
	inst.scene_path = scene_path
	inst.level = level
	# The Recursion: `level` is the floor, and the floor's saved roll is the seed (Tower)
	inst.rng_seed = Tower.run_seed(level) if Tower.is_tower(scene_path) else randi()
	inst.threats = DungeonThreats.roll_for(scene_path, inst.rng_seed)
	inst.created_msec = Time.get_ticks_msec()
	inst.empty_since_msec = inst.created_msec     # a prepared but never entered instance also expires
	instances[inst.id] = inst
	instance_created.emit(inst)
	return inst


func _make_room() -> void:
	while instances.size() >= MAX_INSTANCES:
		var oldest: DungeonInstance = null
		for inst in instances.values():
			if inst.occupants == 0 and (oldest == null or inst.empty_since_msec < oldest.empty_since_msec):
				oldest = inst
		if oldest == null:
			return                                  # every instance is occupied, so allow going over
		_close(oldest)


func _close(inst: DungeonInstance) -> void:
	instances.erase(inst.id)
	instance_closed.emit(inst)
