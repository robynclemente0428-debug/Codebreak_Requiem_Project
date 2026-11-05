class_name DungeonPopulator
extends Node

## Anything with waves in a dungeon (a WardBeacon) joins this group, has wave_event_done() and
## emits wave_event_finished when its waves are over (wave_event_label() names it, optional).
## The area only counts as cleared once every one of them is done, as well as every enemy.
const WAVE_EVENTS := "wave_events"

@export var director: DungeonDirector
@export var enemies_root: Node3D
@export var loot_root: Node3D
## Scene dropped for every item. Defaults to the standard pickup, so a new dungeon works
## without setting it (an empty slot used to crash the first item drop).
@export var loot_pickup_scene: PackedScene = preload("res://scenes/loot/loot_pickup.tscn")
@export var loot_level_window: int = 20   # items older than level - window stop dropping

@export_group("Corridor enemies")
## Small groups wandering the corridors: one group per this many corridor floor tiles.
## 0 = corridors stay empty.
@export var corridor_tiles_per_group: int = 30
@export var corridor_group_min: int = 1
@export var corridor_group_max: int = 3
## No corridor groups this close (in tiles) to the start or a portal room.
@export var corridor_safe_distance: int = 6
## Rarity weights for corridor enemies (weaker than rooms by default).
@export var corridor_rarity_weights: Dictionary = {"normal": 75, "magic": 20, "rare": 5}

@export_group("Props")
## Breakable loot props scattered along room walls. First one is the common pick.
@export var prop_scenes: Array[PackedScene] = [
	preload("res://scenes/props/loot_barrel.tscn"),
	preload("res://scenes/props/supply_cache.tscn"),
]
## Chance a prop is the second scene (the supply cache) instead of the first.
@export_range(0.0, 1.0, 0.01) var rare_prop_chance: float = 0.25
@export var props_per_room_min: int = 2
@export var props_per_room_max: int = 5
## Chance each prop brings 1-2 neighbours along the same wall (barrels come in piles).
@export_range(0.0, 1.0, 0.01) var prop_cluster_chance: float = 0.45
## Props along corridors: one per this many corridor floor cells (0 = none in corridors).
@export var corridor_cells_per_prop: int = 18

@export_group("Chests")
## Opened with the interact key, pays out more than any barrel (see LootChest). Empty = the
## default chest. Not preloaded: the chest's script refers back to this class, and a preload
## here made the two load each other in a loop.
@export var chest_scene: PackedScene
const DEFAULT_CHEST := "res://scenes/props/loot_chest.tscn"
@export var chests_enabled: bool = true
## Chests per dungeon: chests_min at level 1, rising to chests_max by level 10.
@export var chests_min: int = 1
@export var chests_max: int = 3

@export_group("Ward beacon")
## This district's ward beacon (an id from QuestItems, e.g. "beacon_spillway"): placed in the
## room farthest from the start, for the WARD BEACONS quests. Empty = no beacon here.
@export var ward_beacon_id: String = ""

var _beacon_cell := Vector2i(-99999, -99999)   # props keep clear of the ward beacon
var _salvage_cell := Vector2i(-99999, -99999)  # ...and of the salvage cache
var _loot_cache: Array[ItemDefinition] = []
var _loot_cache_level := -1

const SPAWN_LIFT := Vector3.UP * 0.1
const DROP_CHANCE := {"normal": 0.10, "magic": 0.35, "rare": 1.0, "champion": 1.0}
const CREDIT_DROP := {
    "normal": [1, 4],
    "magic": [4, 10],
    "rare": [12, 30],
    "champion": [30, 60]
}
var _level := 1
## Set by dungeon.gd: the instance record. Enemies killed on an earlier visit are not spawned
## again. null = don't track (e.g. a test scene).
var instance: DungeonInstance
var _enemy_index := 0                   # every spawn attempt gets the next number, in a fixed order
var _is_floor: Callable      # (Vector3i) -> bool   supplied by dungeon.gd
## What this dungeon's fights favour (DungeonThreats ids): the instance's rolled threats.
## Set it before populate() to override (a test scene).
var threats: PackedStringArray = []
var _threat_rng := RandomNumberGenerator.new()
var _told_waves_left := false   # the "not cleared yet: waves left" toast, once per visit
var _to_world: Callable      # (Vector2i) -> Vector3  supplied by dungeon.gd

func populate(level: int, skip_rooms: Array, is_floor: Callable, to_world: Callable) -> void:
	_level = level
	_is_floor = is_floor
	_to_world = to_world

	var dungeon_theme := director.dungeon_theme
	if dungeon_theme.enemy_pool.is_empty():
		push_warning("Theme has no enemy_pool, no enemies spawned")
		return

	var rng := director.rng                       # seeded: same seed, same layout and rarities
	if threats.is_empty():
		if instance != null:
			threats = instance.threats
		else:                                     # no instance record (a test scene): roll here
			var area := owner if owner != null else get_parent()
			threats = DungeonThreats.roll_for(area.scene_file_path, rng.seed) if area != null else PackedStringArray()
	_threat_rng.seed = rng.seed + 7177            # its own stream, so the layout rolls stay the same
	var swarm := DungeonThreats.SWARM_COUNT if "swarm" in threats else 1
	var used: Dictionary = {}
	var spawned := 0
	for room: RoomData in director.rooms:
		if room in skip_rooms:
			continue
		var is_branch := room.room_type == "branch"
		var target := rng.randi_range(
			dungeon_theme.enemies_per_room_min, dungeon_theme.enemies_per_room_max)
		if is_branch:
			target = maxi(1, target / 2)
		target *= swarm
		var weights: Dictionary = dungeon_theme.branch_rarity_weights if is_branch \
			else dungeon_theme.room_rarity_weights

		var placed := 0
		var attempts := 0
		while placed < target and attempts < target * 10:
			attempts += 1
			var cell := Vector2i(
				rng.randi_range(room.rect.position.x, room.rect.end.x - 1),
				rng.randi_range(room.rect.position.y, room.rect.end.y - 1))
			if used.has(cell) or not _is_floor.call(Vector3i(cell.x, 0, cell.y)):
				continue
			used[cell] = true
			var rarity := _roll_rarity(weights, rng)
			var def := EnemyDefinition.pick(dungeon_theme.enemy_pool, rarity, rng)
			if def == null:
				continue
			_spawn_threat(def, rarity, cell)
			placed += 1
			spawned += 1

		if is_branch:                             # dead ends hold a guaranteed rare item
			_drop_item(_to_world.call(room.center()), "rare")
	spawned += _populate_corridors(rng, used)
	print("[Populator] spawned %d enemies" % spawned)


## A few small groups in the corridors, away from where players arrive. Same seeded rng as the
## rooms, so a dungeon instance always has the same corridor enemies (and dead ones stay dead).
func _populate_corridors(rng: RandomNumberGenerator, used: Dictionary) -> int:
	if corridor_tiles_per_group <= 0:
		return 0
	var pool := director.dungeon_theme.enemy_pool
	var in_room := {}
	var safe: Array[Rect2i] = []
	for room: RoomData in director.rooms:
		if room.room_type == "start" or room.room_type == "portal":
			safe.append(room.rect.grow(corridor_safe_distance))
		for x in range(room.rect.position.x, room.rect.end.x):
			for y in range(room.rect.position.y, room.rect.end.y):
				in_room[Vector2i(x, y)] = true
	var cells: Array[Vector2i] = []
	for x in director.grid_width:
		for y in director.grid_height:
			var c := Vector2i(x, y)
			if in_room.has(c) or used.has(c) or not _is_floor.call(Vector3i(x, 0, y)):
				continue
			if safe.any(func(r: Rect2i) -> bool: return r.has_point(c)):
				continue
			cells.append(c)
	var groups := cells.size() / corridor_tiles_per_group
	var spawned := 0
	for g in groups:
		if cells.is_empty():
			break
		var anchor: Vector2i = cells[rng.randi() % cells.size()]
		var size := rng.randi_range(corridor_group_min, corridor_group_max)
		if "swarm" in threats:
			size *= DungeonThreats.SWARM_COUNT
		# One kind per group, and only ones that can roll normal (elites don't come in packs)
		var def := EnemyDefinition.pick(pool, "normal", rng)
		if def == null:
			break
		for i in size:
			# members stand on free floor next to the anchor
			var spot := anchor
			for attempt in 8:
				var c := anchor + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
				if not used.has(c) and _is_floor.call(Vector3i(c.x, 0, c.y)):
					spot = c
					break
			if used.has(spot):
				continue
			used[spot] = true
			_spawn_threat(def, _roll_rarity(corridor_rarity_weights, rng), spot)
			spawned += 1
	return spawned

func _eligible_loot() -> Array[ItemDefinition]:
	if _loot_cache_level == _level:
		return _loot_cache
	var theme := director.dungeon_theme
	var out: Array[ItemDefinition] = []
	if theme.auto_loot:
		out.append_array(ItemCatalog.for_level(_level, loot_level_window,
				theme.loot_include_gems, theme.loot_folders))
	for def in theme.loot_pool:                      # hand-placed extras
		if def not in out and def.item_level <= _level and def.item_level >= _level - loot_level_window:
			out.append(def)
	var rank := Ranks.of_player(get_tree())         # gems above the player's rank don't drop
	out.assign(out.filter(func(d: ItemDefinition) -> bool: return not ShopNPC._locked(d, rank)))
	_loot_cache = out
	_loot_cache_level = _level
	print("[Populator] loot pool at level %d: %d items" % [_level, out.size()])
	return out

## Returns the enemy, or null if it was killed on an earlier visit of this instance.
func _spawn_enemy(def: EnemyDefinition, rarity: String, cell: Vector2i,
		forced_mods: Variant = null, add_to_random: bool = false) -> Node3D:
	var enemy := EnemySpawner.spawn_enemy(
		def, rarity, enemies_root, _to_world.call(cell) + SPAWN_LIFT, _level,
		forced_mods, add_to_random)
	if not _track(enemy):
		return null                         # killed on an earlier visit of this instance
	var numbers : DamageNumbers = get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers:
		numbers.track(enemy.health)
	print("[Populator] %s (%s)" % [enemy.display_name, rarity])   # remove once verified
	enemy.set_meta(&"enemy_id", def.id)      # the minimap marks the ones a quest asks for
	enemy.set_meta(&"rarity", rarity)
	enemy.set_meta(&"base_name", def.display_name)   # without the rolled modifiers' words
	enemy.set_meta(&"act_boss", def.act_boss)
	enemy.health.died.connect(_on_enemy_died.bind(enemy, rarity, def.id))
	return enemy

## A rolled enemy with this dungeon's threat traits on top of its random modifiers.
func _spawn_threat(def: EnemyDefinition, rarity: String, cell: Vector2i) -> Node3D:
	return _spawn_enemy(def, rarity, cell, DungeonThreats.roll_traits(threats, rarity, _threat_rng), true)

## Returns false (and removes the enemy) if it was killed on an earlier visit.
## The enemy is still created first, so the random numbers stay in step and every later
## enemy gets the same position, rarity and modifiers as before.
func _track(enemy: Node3D) -> bool:
	var index := _enemy_index
	_enemy_index += 1
	if instance == null:
		return true
	if instance.killed.has(index):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
		return false
	var inst := instance
	enemy.health.died.connect(func() -> void:
		inst.killed[index] = true
		_check_cleared(inst))
	return true


## Wave events in this area (WAVE_EVENTS) whose waves aren't over yet.
func _pending_wave_events() -> Array:
	var area := get_parent()
	return get_tree().get_nodes_in_group(WAVE_EVENTS).filter(func(n: Node) -> bool:
		return area != null and area.is_ancestor_of(n) and n.has_method("wave_event_done") \
				and not n.wave_event_done())


## An act boss died: the first kill of each widens every knob (ScriptBudget.STEPS_PER_ACT_BOSS).
func _on_act_boss_died(enemy_id: String, boss_name: String) -> void:
	var player := get_tree().get_first_node_in_group("players")
	var qm := player.get("quests") as QuestManager if player != null else null
	var first := qm != null and not ScriptBudget.is_boss_killed(qm, enemy_id)
	GameEvents.report(ScriptBudget.BOSS_DEED, enemy_id)
	if first:
		var n := ScriptBudget.STEPS_PER_ACT_BOSS
		QuestItems.toast(get_tree(), "%s DEFEATED  +%d KNOB STEP%s" % [boss_name.to_upper(), n, "" if n == 1 else "S"],
				Color(0.80, 0.50, 1.0))


## The last enemy of the instance died, and every wave event here (a ward beacon) is done:
## the area is cleared. Reports clear_area (a deed, so the first clear of each area gives every
## skill ScriptBudget.POINTS_PER_CLEAR more points). Runs again when a wave event finishes.
## _enemy_index is how many enemies populate() and spawn_marked() made, dead or alive.
func _check_cleared(inst: DungeonInstance) -> void:
	if inst.cleared or inst.killed.size() < _enemy_index:
		return
	var pending := _pending_wave_events()
	if not pending.is_empty():
		if not _told_waves_left:
			_told_waves_left = true
			var names: Array[String] = []
			for n in pending:
				names.append(n.wave_event_label() if n.has_method("wave_event_label") else "a wave event")
			QuestItems.toast(get_tree(), "AREA NOT CLEARED YET\nStill to go: %s." % ", ".join(names),
					Color(1.0, 0.82, 0.30))
		return
	inst.cleared = true
	var area_id := _area_id()
	if area_id == "":
		return
	var player := get_tree().get_first_node_in_group("players")
	var qm := player.get("quests") as QuestManager if player != null else null
	var first := qm != null and not ScriptBudget.is_cleared(qm, area_id)
	GameEvents.report(ScriptBudget.CLEAR_DEED, area_id)
	var area := owner if owner != null else get_parent()
	var w := Waypoints.for_scene(area.scene_file_path) if area != null else null
	var area_name := w.display_name if w != null else area_id.capitalize()
	var reward := ""
	if first:
		var pts := ScriptBudget.POINTS_PER_CLEAR
		reward = "+%s SCRIPT POINT%s ON EVERY SKILL" % [
				str(int(pts)) if is_equal_approx(pts, roundf(pts)) else "%.1f" % pts, "" if pts <= 1.0 else "S"]
	elif qm != null:
		reward = "ALREADY CLEARED BEFORE: NO NEW POINT"
	AreaClearedBanner.announce(get_tree(), area_name, reward)


## The area scene's file name, e.g. "act_1_coolant_vaults".
func _area_id() -> String:
	var area := owner if owner != null else get_parent()
	return area.scene_file_path.get_file().get_basename() if area != null else ""


func _on_enemy_died(enemy: Node3D, rarity: String, enemy_id: String) -> void:
	# Quest events
	GameEvents.report("kill", enemy_id)
	GameEvents.report("kill_rarity", rarity)      # for "kill 3 rare enemies" / "kill a champion"
	# Where it died, for "the Raider in the Coolant Vaults": "corrupted_raider@act_1_coolant_vaults"
	GameEvents.report("kill_at", "%s@%s" % [enemy_id, _area_id()])
	if enemy.get_meta(&"act_boss", false):
		_on_act_boss_died(enemy_id, str(enemy.get_meta(&"base_name", enemy_id)))

	# Award credits when the enemy dies
	_award_credits(rarity, enemy.global_position)
	# Roll for an item drop
	if randf() <= DROP_CHANCE.get(rarity, 0.1):
		_drop_item(enemy.global_position, rarity)

func _award_credits(rarity: String, at: Vector3) -> void:
	var player := get_tree().get_first_node_in_group("players")
	if player == null or player.get("currency") == null:
		return
	var span: Array = CREDIT_DROP.get(rarity, [1, 3])
	var amount := randi_range(span[0], span[1])
	player.currency.add(amount)
	# floating "+N CR" where the enemy fell
	get_tree().call_group("damage_numbers", "pop_credits", at + Vector3.UP * 1.4, amount)


## Drops one item of this rarity at a world position, using this dungeon's loot rules.
## Props (barrels, caches) call this.
func drop_item_at(pos: Vector3, rarity: String) -> void:
	_drop_item(pos, rarity)


## Scatters breakable props along the walls of each room. Uses the seeded rng after the
## enemies, so the same instance gets the same props; opened ones come back already open.
func place_props(is_floor: Callable, to_world: Callable) -> void:
	if prop_scenes.is_empty() or props_per_room_max <= 0:
		return
	var root := get_parent()
	var holder := root.get_node_or_null("Props") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "Props"
		root.add_child(holder)
	var rng := director.rng
	var counter := [0, 0]                         # [next prop index, placed]
	var in_room := {}
	for room: RoomData in director.rooms:
		for x in range(room.rect.position.x, room.rect.end.x):
			for y in range(room.rect.position.y, room.rect.end.y):
				in_room[Vector2i(x, y)] = true
	var taken := {}
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			taken[_beacon_cell + Vector2i(dx, dy)] = true
			taken[_salvage_cell + Vector2i(dx, dy)] = true
	# Keep the cells around every enemy free: a barrel right beside an enemy cuts its spot out of
	# the navmesh (props are baked into it), and an enemy standing off the navmesh can't path.
	if enemies_root != null and director.grid_map != null:
		var gm := director.grid_map
		for e in enemies_root.get_children():
			if e is Node3D:
				var m := gm.local_to_map(gm.to_local((e as Node3D).global_position))
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						taken[Vector2i(m.x + dx, m.z + dy)] = true
	for room: RoomData in director.rooms:
		if room.room_type == "start" or room.room_type == "portal":
			continue
		var spots: Array[Vector2i] = []
		for x in range(room.rect.position.x, room.rect.end.x):
			for y in range(room.rect.position.y, room.rect.end.y):
				var c := Vector2i(x, y)
				if is_floor.call(Vector3i(x, 0, y)) and _against_wall(c, is_floor):
					spots.append(c)
		var want := rng.randi_range(props_per_room_min, props_per_room_max)
		_scatter(spots, want, holder, to_world, rng, counter, taken)
	# corridors: floor outside every room
	if corridor_cells_per_prop > 0:
		var corridor: Array[Vector2i] = []
		for x in director.grid_width:
			for y in director.grid_height:
				var c := Vector2i(x, y)
				if not in_room.has(c) and is_floor.call(Vector3i(x, 0, y)) \
						and _against_wall(c, is_floor) and _leaves_gap(c, is_floor):
					corridor.append(c)
		_scatter(corridor, corridor.size() / corridor_cells_per_prop, holder, to_world, rng, counter, taken)
	var placed: int = counter[1]
	var chests := _place_chests(holder, to_world, rng, counter, taken, is_floor)
	print("[Populator] placed %d props, %d chests" % [placed, chests])


## A few chests, one per room at most, back against a wall and facing into the room.
## Placed after the other props with the same rng, so an instance always gets the same ones.
func _place_chests(holder: Node3D, to_world: Callable, rng: RandomNumberGenerator,
		counter: Array, taken: Dictionary, is_floor: Callable) -> int:
	if not chests_enabled or chests_max <= 0:
		return 0
	if chest_scene == null:
		chest_scene = load(DEFAULT_CHEST)
	var t := clampf((_level - 1) / 9.0, 0.0, 1.0)
	var want := roundi(lerpf(chests_min, chests_max, t))
	var rooms: Array = []
	for room: RoomData in director.rooms:
		if room.room_type != "start" and room.room_type != "portal":
			rooms.append(room)
	# Only walls on the far side from the camera: a chest against a near wall hides behind it
	var gm := director.grid_map
	var away := Vector3(0.0, 0.0, -1.0)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		away = Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()
	var made := 0
	while made < want and not rooms.is_empty():
		var room: RoomData = rooms.pop_at(rng.randi() % rooms.size())
		var spots: Array = []                     # [cell, wall direction]
		for x in range(room.rect.position.x, room.rect.end.x):
			for y in range(room.rect.position.y, room.rect.end.y):
				var c := Vector2i(x, y)
				if taken.has(c) or not is_floor.call(Vector3i(x, 0, y)):
					continue
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if (gm.global_basis * Vector3(d.x, 0.0, d.y)).dot(away) < 0.1:
						continue                      # a near wall
					var wall: Vector2i = c + d
					var front: Vector2i = c - d
					var front2: Vector2i = c - d * 2
					# Wall behind, two clear cells in front (room to stand and open it)
					if not is_floor.call(Vector3i(wall.x, 0, wall.y)) \
							and is_floor.call(Vector3i(front.x, 0, front.y)) and not taken.has(front) \
							and is_floor.call(Vector3i(front2.x, 0, front2.y)):
						spots.append([c, d])
						break
		if spots.is_empty():
			continue
		var pick: Array = spots[rng.randi() % spots.size()]
		var cell: Vector2i = pick[0]
		var wall_dir: Vector2i = pick[1]
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				taken[cell + Vector2i(dx, dy)] = true
		var chest := _place_prop(cell, holder, to_world, rng, counter, chest_scene)
		# Face into the room, nudged back towards the wall
		var into := (gm.global_basis * Vector3(-wall_dir.x, 0.0, -wall_dir.y)).normalized()
		chest.global_rotation = Vector3(0.0, atan2(into.x, into.z), 0.0)
		chest.global_position -= into * gm.cell_size.x * 0.2
		made += 1
	return made


## Places `want` props on random free spots, each maybe with 1-2 neighbours (a pile).
func _scatter(spots: Array[Vector2i], want: int, holder: Node3D, to_world: Callable,
		rng: RandomNumberGenerator, counter: Array, taken: Dictionary) -> void:
	var made := 0
	while made < want and not spots.is_empty():
		var cell: Vector2i = spots.pop_at(rng.randi() % spots.size())
		if taken.has(cell):
			continue
		var pile: Array[Vector2i] = [cell]
		if rng.randf() < prop_cluster_chance:
			var extra := rng.randi_range(1, 2)
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = cell + d
				if pile.size() > extra:
					break
				if spots.has(n) and not taken.has(n):
					pile.append(n)
					spots.erase(n)
		for c in pile:
			taken[c] = true
			_place_prop(c, holder, to_world, rng, counter)
			made += 1


## Places one prop: `scene`, or a barrel / supply cache picked from prop_scenes. Returns it.
func _place_prop(cell: Vector2i, holder: Node3D, to_world: Callable,
		rng: RandomNumberGenerator, counter: Array, scene: PackedScene = null) -> LootProp:
	if scene == null:
		scene = prop_scenes[0]
		if prop_scenes.size() > 1 and rng.randf() < rare_prop_chance:
			scene = prop_scenes[1]
	var index: int = counter[0]
	var prop := scene.instantiate() as LootProp
	prop.index = index
	holder.add_child(prop)
	prop.global_position = to_world.call(cell)
	prop.rotation.y = rng.randf() * TAU
	if instance != null:
		if instance.opened.has(index):
			prop.set_already_open()
		else:
			var inst := instance
			prop.opened.connect(func(_p) -> void: inst.opened[index] = true)
	counter[0] = index + 1
	counter[1] += 1
	return prop


## Corridors: only where the corridor is wider than one tile, so a prop never blocks the way.
## (Walls on both sides of the cell = a 1-wide corridor = no prop.)
func _leaves_gap(c: Vector2i, is_floor: Callable) -> bool:
	for d in [Vector2i.LEFT, Vector2i.UP]:
		var a: Vector2i = c + d
		var b: Vector2i = c - d
		if not is_floor.call(Vector3i(a.x, 0, a.y)) and not is_floor.call(Vector3i(b.x, 0, b.y)):
			return false
	return true


## True if a floor cell has a non-floor cell next to it (so props hug the walls).
func _against_wall(c: Vector2i, is_floor: Callable) -> bool:
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n: Vector2i = c + d
		if not is_floor.call(Vector3i(n.x, 0, n.y)):
			return true
	return false

func _drop_item(pos: Vector3, rarity: String) -> void:
	var pool := _eligible_loot()
	if pool.is_empty():
		return
	var def: ItemDefinition = pool[randi() % pool.size()]
	var is_gem := def.skill_gem != null or def.support_gem != null

	# Gems ignore the enemy's rarity; everything else behaves as before
	var item_rarity := "normal"
	if not is_gem:
		item_rarity = "rare" if rarity == "champion" else rarity

	var item := ItemGenerator.generate_item(def, _level, item_rarity)
	var pickup := loot_pickup_scene.instantiate() as LootPickup
	pickup.item = item
	_place_pickup.call_deferred(pickup, pos + Vector3(0, 0.5, 0))

func _place_pickup(pickup: LootPickup, world_pos: Vector3) -> void:
	loot_root.add_child(pickup)
	pickup.global_position = world_pos        # world space, whatever the Loot node's transform is

func _roll_rarity(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for w in weights.values():
		total += int(w)
	var roll := rng.randi_range(0, total - 1)
	for r in weights.keys():
		roll -= int(weights[r])
		if roll < 0:
			return r
	return "normal"

func spawn_marked(entries: Array, level: int, is_floor: Callable, to_world: Callable) -> void:
	_level = level
	_is_floor = is_floor
	_to_world = to_world
	for e in entries:
		var def: EnemyDefinition = e["definition"]
		if def == null:
			continue
		var cell: Vector2i = e["cell"]
		if not is_floor.call(Vector3i(cell.x, 0, cell.y)):
			push_warning("EnemyMarker at %s is not on floor, skipped" % [cell])
			continue
		# The marker's own modifiers: exactly these (replace_random), or these on top of the rolled ones
		var mods: Array = e.get("modifiers", []).duplicate()
		var replace: bool = e.get("replace_random", true)
		if e.get("threat_traits", true):
			# The dungeon's traits on top (they are the dungeon's, not random modifiers, so they
			# apply even with replace_random). No Swarm: one placed enemy can't be doubled.
			var no_swarm := PackedStringArray(Array(threats).filter(func(t) -> bool: return t != "swarm"))
			for extra in DungeonThreats.roll_traits(no_swarm, e["rarity"], _threat_rng):
				if not mods.has(extra):
					mods.append(extra)
		var enemy := _spawn_enemy(def, e["rarity"], cell, mods, not replace)
		var key: String = e.get("key", "")
		if key != "" and not QuestItems.owned(get_tree(), key):
			if enemy != null:
				enemy.set_meta(&"carries_key", key)     # the minimap rings it while a quest wants the key
				enemy.health.died.connect(func() -> void:
					_drop_key.call_deferred(key, enemy.global_position))
			else:
				# Killed on an earlier visit but the key was left behind: it's still lying there
				_drop_key.call_deferred(key, to_world.call(cell))


func _drop_key(key: String, at: Vector3) -> void:
	if not QuestItems.owned(get_tree(), key):
		QuestKeyPickup.spawn(loot_root, at, key)


## A convoy stop's salvage cache (SalvageCache), once per stop: in an ordinary room off the
## way, picked from the stop's id so it's in the same place on a rejoin. Not once recovered.
func place_salvage(scene_path: String, is_floor: Callable, to_world: Callable) -> void:
	var w := Waypoints.for_scene(scene_path)
	if w == null or not Waypoints.is_convoy_stop(w):
		return
	var player := get_tree().get_first_node_in_group("players")
	var qm := player.get("quests") as QuestManager if player != null else null
	if qm != null and qm.deed_count(SalvageCache.DEED, w.id) > 0:
		return
	var rooms: Array[RoomData] = []
	for room: RoomData in director.rooms:
		if not (room.room_type in ["start", "portal", "boss", "custom"]):   # custom: arenas
			rooms.append(room)
	if rooms.is_empty():
		return
	var room := rooms[absi(hash(w.id)) % rooms.size()]
	var c := room.center()
	for r in range(0, 6):                         # nearest floor cell, rings outwards
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var t := c + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == r and t != _beacon_cell and is_floor.call(Vector3i(t.x, 0, t.y)):
					_salvage_cell = t
					SalvageCache.spawn(get_parent(), to_world.call(t), w.id)
					return
	push_warning("No floor for the salvage cache of %s" % w.id)


## The district's ward beacon, in the room farthest from where the player arrives (so it's
## worth the walk), at the free floor cell nearest that room's middle.
func place_ward_beacon(is_floor: Callable, to_world: Callable) -> void:
	if ward_beacon_id == "":
		return
	var start := director.layout.spawn_cell if director.layout != null else Vector2i.ZERO
	var best: RoomData = null
	for room: RoomData in director.rooms:
		if room.room_type in ["start", "portal", "boss"]:
			continue
		if best == null or Vector2(room.center() - start).length() > Vector2(best.center() - start).length():
			best = room
	if best == null:
		push_warning("No room for the ward beacon %s" % ward_beacon_id)
		return
	var c := best.center()
	var cell := c
	var found := false
	for r in range(0, 6):                         # nearest floor cell, rings outwards
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var t := c + Vector2i(dx, dy)
				if not found and maxi(absi(dx), absi(dy)) == r and is_floor.call(Vector3i(t.x, 0, t.y)):
					cell = t
					found = true
		if found:
			break
	if not found:
		push_warning("No floor for the ward beacon %s" % ward_beacon_id)
		return
	_beacon_cell = cell
	var beacon := WardBeacon.spawn(get_parent(), to_world.call(cell), ward_beacon_id)
	beacon.wave_event_finished.connect(func() -> void:
		if instance != null:
			_check_cleared(instance))
