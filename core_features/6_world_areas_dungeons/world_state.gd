extends Node

signal instance_created(instance: DungeonInstance)
signal instance_closed(instance: DungeonInstance)

const EMPTY_TIMEOUT_SEC := 600.0
const MAX_INSTANCES := 5
const CHECK_EVERY_SEC := 1.0

const REJOIN_OR_NEW := 0
const ALWAYS_NEW := -1

var instances: Dictionary = {}
var _next_id := 1
var _pending: DungeonInstance
var _timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_EVERY_SEC:
		return
	_timer = 0.0
	close_expired()


func prepare_dungeon(scene_path: String, level: int, instance_id: int = REJOIN_OR_NEW) -> DungeonInstance:
	scene_path = Waypoints.normalize(scene_path)
	var inst: DungeonInstance = null
	if instance_id > 0:
		inst = instances.get(instance_id)
	elif instance_id == REJOIN_OR_NEW:
		inst = find_open(scene_path, level)
	if inst == null:
		inst = _create(scene_path, level)
	_pending = inst
	return inst


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


func prepare_rejoin(inst: DungeonInstance) -> void:
	if inst != null and instances.has(inst.id):
		_pending = inst


func find_open(scene_path: String, level: int) -> DungeonInstance:
	scene_path = Waypoints.normalize(scene_path)
	var best: DungeonInstance = null
	for inst: DungeonInstance in instances.values():
		if inst.scene_path == scene_path and inst.level == level and (best == null or inst.id > best.id):
			best = inst
	return best


func begin_visit(scene_path: String, default_level: int = 1) -> DungeonInstance:
	scene_path = Waypoints.normalize(scene_path)
	var inst := _pending
	_pending = null
	if inst == null:
		inst = _create(scene_path, default_level)
	inst.occupants += 1
	return inst


func end_visit(inst: DungeonInstance) -> void:
	if inst == null:
		return
	inst.occupants = maxi(inst.occupants - 1, 0)
	if inst.occupants == 0:
		inst.empty_since_msec = Time.get_ticks_msec()


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
	inst.rng_seed = randi()
	inst.threats = DungeonThreats.roll_for(scene_path, inst.rng_seed)
	inst.created_msec = Time.get_ticks_msec()
	inst.empty_since_msec = inst.created_msec
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
			return
		_close(oldest)


func _close(inst: DungeonInstance) -> void:
	instances.erase(inst.id)
	instance_closed.emit(inst)
