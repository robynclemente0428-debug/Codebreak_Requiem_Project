class_name EnemySleep
extends Node
## Puts a dungeon's far-away enemies to sleep. An enemy no player is near, and that isn't
## fighting anyone, stops running entirely (its AI, physics, animation, skills and traits:
## process_mode DISABLED), so a dungeon of 70-120 enemies only pays for the ones around you.
## It wakes as soon as a player comes within wake_distance, or the moment it's hurt (a long
## shot from off screen), and carries on exactly where it was.
##
## Only enemies marked SLEEP_META sleep (the dungeon's own, from DungeonPopulator). Wave
## enemies (ward beacons, dock defense, hull breaches, exams) and summons are never marked:
## they have to walk to you from far away.
## Dungeon adds one of these over its Enemies node.

const SLEEP_META := &"can_sleep"

## Metres from the nearest player: closer than this and the enemy is awake. Past every
## skill's range and the screen's edge, so you never see or shoot one asleep.
@export var wake_distance := 32.0
## It falls asleep again only past this (a bit further, so one standing at the edge doesn't
## flick on and off).
@export var sleep_distance := 38.0
## Seconds between checks (the sleepers are spread over these, a few per frame).
@export var check_interval := 0.3

var enemies_root: Node
var _timer := 0.0
var _asleep := 0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = check_interval
	if enemies_root == null or not is_instance_valid(enemies_root):
		return
	var players: Array[Vector3] = []
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node3D:
			players.append((p as Node3D).global_position)
	if players.is_empty():
		return
	var wake2 := wake_distance * wake_distance
	var sleep2 := sleep_distance * sleep_distance
	_asleep = 0
	for child in enemies_root.get_children():
		var e := child as Node3D
		if e == null or not e.has_meta(SLEEP_META):
			continue
		var d2 := INF
		for at in players:
			d2 = minf(d2, e.global_position.distance_squared_to(at))
		var sleeping := e.process_mode == Node.PROCESS_MODE_DISABLED
		if sleeping:
			if d2 < wake2:
				wake(e)
			else:
				_asleep += 1
		elif d2 > sleep2 and _idle(e):
			e.process_mode = Node.PROCESS_MODE_DISABLED
			_asleep += 1


## Asleep right now (for a debug readout).
func asleep_count() -> int:
	return _asleep


## Marks an enemy as one that may sleep, and wakes it whenever it's hurt.
static func allow(enemy: Node3D) -> void:
	enemy.set_meta(SLEEP_META, true)
	var hp = enemy.get("health")
	if hp is HealthComponent:
		(hp as HealthComponent).damage_taken.connect(func(_amount: float) -> void:
			if is_instance_valid(enemy):
				wake(enemy))


static func wake(enemy: Node3D) -> void:
	if enemy.process_mode == Node.PROCESS_MODE_DISABLED:
		enemy.process_mode = Node.PROCESS_MODE_INHERIT


## Not chasing or fighting anyone, and not dead: safe to freeze.
func _idle(e: Node3D) -> bool:
	var hp = e.get("health")
	if hp is HealthComponent and (hp as HealthComponent).current_health <= 0.0:
		return false                      # let its death play out
	var ai = e.get("ai")
	if ai == null:
		return true
	return ai.target == null and ai.state == AIComponent.State.IDLE
