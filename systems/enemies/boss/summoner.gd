class_name Summoner
extends Node
## Boss trait: calls in minions every `interval` seconds once the boss has noticed a player.
## Used by the Glitchling Queen ("spawns small Glitchlings every 10 seconds. Kill the Queen to
## stop them"), but works on any enemy: put this node anywhere inside the enemy's MODEL scene
## and give it the EnemyDefinition to summon.
##
## Summons are created with EnemySpawner like any other enemy, at the dungeon's level, with no
## random modifiers. They are not counted by the populator, so they drop no loot or credits and
## don't count for kill quests (killing a breeder's children forever shouldn't farm anything).

@export var summon: EnemyDefinition
## Modifiers every summon gets (the Root Process's adds come Fragmented). Empty = none.
@export var summon_mods: Array[EnemyModifierDefinition] = []
@export var interval: float = 10.0
@export var first_delay: float = 3.0           # after the boss first notices a player
@export var count: int = 3                     # per wave
@export var max_alive: int = 8                 # waves stop while this many are still alive
@export var radius: float = 3.0                # spawn ring around the boss, metres
@export_enum("normal", "magic", "rare", "champion") var rarity: String = "normal"
## The Queen's death takes her brood with her.
@export var kill_summons_on_death: bool = true

signal summoned(enemies: Array)

var _enemy: EnemyBase
var _alive: Array[Node3D] = []
var _timer := -1.0                             # < 0 = not started (boss hasn't noticed anyone)
var _dead := false


func _ready() -> void:
	var n := get_parent()
	while n != null and not (n is EnemyBase):
		n = n.get_parent()
	_enemy = n as EnemyBase
	if _enemy == null:
		push_warning("Summoner: not inside an enemy, disabled")
		set_process(false)
		return
	if summon == null:
		push_warning("Summoner on %s has no summon definition" % _enemy.name)
		set_process(false)
		return
	_enemy.health.died.connect(_on_boss_died)


func _process(delta: float) -> void:
	if _dead or _enemy.ai == null:
		return
	if _timer < 0.0:
		if _enemy.ai.state != AIComponent.State.IDLE:
			_timer = first_delay                # noticed a player: first wave soon
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval
	_spawn_wave()


func _spawn_wave() -> void:
	# filter() returns an untyped Array, so copy it back into the typed one with assign()
	_alive.assign(_alive.filter(func(e) -> bool:
		return is_instance_valid(e) and e.health.current_health > 0.0))
	var room := maxi(max_alive - _alive.size(), 0)
	var n := mini(count, room)
	if n == 0:
		return
	var parent := _enemy.get_parent()
	var level := _dungeon_level()
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	var wave: Array = []
	var start := randf() * TAU
	for i in n:
		var angle := start + TAU * float(i) / float(n)
		var pos := _enemy.global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
		pos = _on_navmesh(pos)
		var e := EnemySpawner.spawn_enemy(summon, rarity, parent, pos + Vector3.UP * 0.1, level, summon_mods.duplicate())
		if e == null:
			continue
		if numbers:
			numbers.track(e.health)
		_alive.append(e)
		wave.append(e)
	summoned.emit(wave)


func _on_boss_died() -> void:
	_dead = true
	if not kill_summons_on_death:
		return
	for e in _alive:
		if is_instance_valid(e) and e.health.current_health > 0.0:
			e.health.current_health = 0.0
			e.health.died.emit()                # no damage number, they just collapse
	_alive.clear()


## The level of the dungeon the boss is in (summons scale like everything else there).
func _dungeon_level() -> int:
	var n := _enemy.get_parent()
	while n != null:
		var lvl = n.get("dungeon_level")
		if lvl is int and lvl > 0:
			return lvl
		n = n.get_parent()
	return 1


## Pulls a point onto the navmesh so summons never appear inside a wall.
func _on_navmesh(pos: Vector3) -> Vector3:
	var map := _enemy.nav.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return pos
	var p := NavigationServer3D.map_get_closest_point(map, pos)
	return p if p != Vector3.ZERO else pos
