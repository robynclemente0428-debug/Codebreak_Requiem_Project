extends GameArea

signal navigation_ready
## True once the first navmesh bake is done. AreaManager keeps the screen faded out until then.
var navigation_is_ready := false

@onready var director: DungeonDirector = $DungeonDirector
@onready var grid_map: GridMap = $NavigationRegion3D/GridMap
@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var populator: DungeonPopulator = $DungeonPopulator
@export var dungeon_level: int = 1
@export var respawn_spawn_id: StringName = &"default"
@export var portal_scene: PackedScene

const FLOOR_LAYER := 0              # the GridMap layer your painter puts floors on

var _arrival_cells: Dictionary = {}     # arrival_spawn_id -> portal cell (fallback)
var _arrival_points: Dictionary = {}    # arrival_spawn_id -> world point in front of the portal
## This visit's instance record, from WorldState: its level, its seed and its dead enemies.
var instance: DungeonInstance

## Dungeons are dark (GameArea.light_scale), lit mostly by the player's own light, their
## skills and the tiles' glowing trims; a scene can still set its own.
const DUNGEON_LIGHT := 0.08
## Times the usual number of Null stains on the floor (TowerFloor: a Null floor is covered in them).
var null_decal_mult := 1.0


func _init() -> void:
	light_scale = DUNGEON_LIGHT


func _ready() -> void:
	instance = WorldState.begin_visit(scene_file_path, dungeon_level)
	dungeon_level = instance.level
	_on_instance()                          # a scene that dresses itself per instance (TowerFloor)
	# The seed must be set BEFORE generating: the director's rng also picks the extra
	# corridors, and the populator keeps using it for who spawns where and their rarity.
	director.use_random_seed = false
	director.fixed_seed = instance.rng_seed
	seed(instance.rng_seed)                 # global randi(), used by enemy modifier rolls
	if not director.generate_from_layout():
		push_error("Dungeon generation failed")
		return
	print("[Dungeon] generated, rooms: %d (instance %d, level %d, %d killed)" % [
		director.rooms.size(), instance.id, instance.level, instance.killed.size()])
	_place_portals()
	populator.instance = instance           # skips enemies killed on an earlier visit
	_spawn_enemies()
	_scatter_null_decals()
	randomize()                             # back to real randomness for loot and combat
	var sleeper := EnemySleep.new()         # far-away enemies stop running until you get near
	sleeper.name = "EnemySleep"
	sleeper.enemies_root = $Enemies
	add_child(sleeper)
	_bind_minimap()
	# kernel.gd: Act V's zones, and every dungeon after MERGE or OVERWRITE (Endings.runs_everywhere).
	# The director looks once the player is here, and leaves if there's nothing for it to run.
	# (KernelDirector._begin)
	var kernel := KernelDirector.new()
	kernel.name = "KernelDirector"
	add_child(kernel)
	await _bake_navigation()


## Called once the instance is known and before anything is generated. TowerFloor sets its level
## and its look here.
func _on_instance() -> void:
	pass


func _exit_tree() -> void:
	WorldState.end_visit(instance)          # starts the closing countdown once nobody is inside

func _bind_minimap() -> void:
	var mm := get_tree().get_first_node_in_group("minimap") as Minimap
	if mm == null:
		push_warning("Dungeon: no Minimap in the scene tree")
		return
	mm.bind_dungeon(director, grid_map, $Enemies, {"explored": instance.explored})

func _spawn_enemies() -> void:
	var skip: Array = []
	for r: RoomData in director.rooms:
		if r.room_type == "start" or r.room_type == "portal" or r.room_type == "boss":
			skip.append(r)
	populator.populate(dungeon_level, skip, _is_floor, _grid_to_world)
	populator.spawn_marked(director.layout.enemies, dungeon_level, _is_floor, _grid_to_world)
	_add_reboot_echoes()
	var echoes := get_node_or_null("NullEchoes") as NullEchoDirector   # Act IV: the Null copies you
	if echoes != null:
		populator.place_echoes(echoes, _is_floor, _grid_to_world)
	populator.place_ward_beacon(_is_floor, _grid_to_world)   # before the props, so none land on it
	populator.place_salvage(scene_file_path, _is_floor, _grid_to_world)   # convoy stops only
	populator.place_queued_crates(scene_file_path, _is_floor, _grid_to_world)   # the Sweep only (YardCrates)
	populator.place_props(_is_floor, _grid_to_world)    # breakable barrels and supply caches

## REBOOT: the Null remembers you, and copies you from Act II (Reboot.early_echoes).
func _add_reboot_echoes() -> void:
	if get_node_or_null("NullEchoes") != null:
		return
	var act := Waypoints.act_of_scene(scene_file_path)
	if act == null or not Reboot.early_echoes(act.act_number):
		return
	var echoes := NullEchoDirector.new()
	echoes.name = "NullEchoes"
	echoes.rebooted = true
	add_child(echoes)


## Null corruption stains on the floor, more of them the deeper the dungeon (see NullDecals).
## Own seed from the instance, so rejoining shows the same stains without touching the
## director's rng (that one decides the layout and enemies).
func _scatter_null_decals() -> void:
	var cells: Array[Vector2i] = []
	for c in grid_map.get_used_cells():
		if c.y == FLOOR_LAYER and _is_floor(c):
			cells.append(Vector2i(c.x, c.z))
	var rooms: Array[Rect2i] = []
	for r: RoomData in director.rooms:
		rooms.append(r.rect)
	NullDecals.scatter(self, cells, _grid_to_world, roundi(NullDecals.count_for_level(dungeon_level, cells.size()) * null_decal_mult),
			instance.rng_seed ^ 0x5EED, director.dungeon_theme.cell_size.x, rooms, dungeon_level)


## Nodes in this group (and their children) are what the navmesh is baked from: the level's
## tiles, plus a NavigationObstacle3D on each breakable prop. Props live outside the
## NavigationRegion3D, so without this the navmesh ran straight through barrels and enemies got
## stuck pushing into them.
const NAV_SOURCE_GROUP := &"navmesh_source"
const REBAKE_DELAY := 0.6       # seconds after a prop breaks before the navmesh opens up there
const NAV_FOOTPRINT := 0.6      # fraction of a prop's collider radius cut out of the navmesh

var _rebake_pending := false
## The level's tiles, read once before the first bake. Every bake reuses it instead of reading
## the whole GridMap again on the main thread (that read is what made entering a dungeon and
## breaking a barrel hitch).
var _tile_geometry: NavigationMeshSourceGeometryData3D


func _bake_navigation() -> void:
	var nm := nav_region.navigation_mesh
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = NAV_SOURCE_GROUP
	# The tiles' collision shapes, not their visual meshes: reading meshes copies them back from
	# the GPU and stalls rendering. Every MeshLibrary tile needs a collision shape for this.
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	grid_map.add_to_group(NAV_SOURCE_GROUP)
	var props := get_node_or_null("Props")
	if props != null:
		for p in props.get_children():
			if p is LootProp:
				_add_nav_obstacle(p as LootProp)
				if not (p as LootProp).opened.is_connected(_on_prop_opened):
					(p as LootProp).opened.connect(_on_prop_opened)
	# The GridMap builds its collision shapes deferred, so there are none to read during
	# _ready(). Wait for them (the screen stays faded out until navigation_is_ready).
	await get_tree().physics_frame
	await get_tree().physics_frame
	# The one read of the level (tiles plus prop footprints), on the main thread.
	var data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_region.navigation_mesh, data, nav_region)
	_tile_geometry = NavigationMeshSourceGeometryData3D.new()   # kept for re-bakes, minus the props
	_tile_geometry.set_vertices(data.get_vertices())
	_tile_geometry.set_indices(data.get_indices())
	_bake_async(data)
	while _baking_async:                      # polling can't miss a signal
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[Dungeon] navmesh ready, polygons: %d" % nav_region.navigation_mesh.get_polygon_count())
	navigation_is_ready = true
	navigation_ready.emit()


## Cuts a prop's footprint (its collider, not its whole model) out of the navmesh when baking.
## Freed with the prop, so the next bake opens the spot again.
func _add_nav_obstacle(p: LootProp) -> void:
	if p.has_node("NavObstacle"):
		return
	var ob := NavigationObstacle3D.new()
	ob.name = "NavObstacle"
	ob.avoidance_enabled = false
	ob.affect_navigation_mesh = true          # baking leaves this footprint out (plus agent radius)
	ob.height = p.collision_height
	# Only the prop's core: the navmesh is shrunk by the agent radius around it anyway, and the
	# full collider plus that margin closed off narrow corridors and doorways. Paths now pass
	# just beside the prop and its round collider slides enemies around it.
	var r := p.collision_radius * NAV_FOOTPRINT
	ob.vertices = PackedVector3Array([Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)])
	p.add_child(ob)
	ob.add_to_group(NAV_SOURCE_GROUP)


## A barrel or cache broke: once it's gone, bake again so paths can use that spot.
## Several breaking close together share one re-bake.
func _on_prop_opened(prop: LootProp) -> void:
	if prop.still_blocks():                  # still standing (a chest, an open cache): nothing to open up
		return
	if _rebake_pending:
		return
	_rebake_pending = true
	await get_tree().create_timer(REBAKE_DELAY, false).timeout
	while nav_region.is_baking() or _baking_async:
		await get_tree().process_frame
	_rebake_pending = false
	if is_inside_tree():
		_rebake()


var _baking_async := false


## Bakes on a worker thread from the cached tiles plus the props still standing, into a copy of
## the navmesh that replaces the old one when it's done (nothing is read on the main thread).
func _rebake() -> void:
	if _tile_geometry == null:
		nav_region.bake_navigation_mesh(true)
		return
	var data := NavigationMeshSourceGeometryData3D.new()
	data.set_vertices(_tile_geometry.get_vertices())
	data.set_indices(_tile_geometry.get_indices())
	var to_region := nav_region.global_transform.affine_inverse()
	var props := get_node_or_null("Props")
	if props != null:
		for p in props.get_children():
			var lp := p as LootProp
			if lp == null or not lp.still_blocks() or lp.is_queued_for_deletion():
				continue
			var ob := lp.get_node_or_null("NavObstacle") as NavigationObstacle3D
			if ob == null:
				continue
			var pts := PackedVector3Array()
			# Flat outline + elevation in the region's space (the map is rotated), like the engine's parse
			var base := to_region * ob.global_position
			for v in ob.vertices:
				var w := to_region * (ob.global_transform * v)
				pts.append(Vector3(w.x, 0.0, w.z))
			data.add_projected_obstruction(pts, base.y, ob.height, false)
	_bake_async(data)


## Bakes `data` on a worker thread into a copy of the navmesh, swapped in when it's done.
func _bake_async(data: NavigationMeshSourceGeometryData3D) -> void:
	var nm := nav_region.navigation_mesh.duplicate() as NavigationMesh
	nm.clear_polygons()
	nm.set_vertices(PackedVector3Array())
	_baking_async = true
	NavigationServer3D.bake_from_source_geometry_data_async(nm, data, _on_rebaked.bind(nm))


func _on_rebaked(nm: NavigationMesh) -> void:
	_baking_async = false
	if is_inside_tree() and nm.get_polygon_count() > 0:
		nav_region.navigation_mesh = nm

func get_spawn_position(spawn_id: StringName = &"default") -> Vector3:
	var layout := director.layout
	if layout == null or layout.spawn_cell == DungeonLayout.NO_CELL:
		push_error("get_spawn_position: dungeon has no valid spawn (generation failed?)")
		return global_position
	if _arrival_points.has(spawn_id):
		return _arrival_points[spawn_id]                       # stepping out of the portal
	if layout.spawns.has(spawn_id):
		return _grid_to_world(layout.spawns[spawn_id])        # exactly where you placed it
	if _arrival_cells.has(spawn_id):
		return _grid_to_world(_nearby_floor(_arrival_cells[spawn_id]))   # no floor in front of it
	return _grid_to_world(layout.spawn_cell)


func _room_nearest(cell: Vector2i) -> RoomData:
	var best: RoomData = null
	var best_d := 1 << 60
	for r: RoomData in director.rooms:
		var d := (r.center() - cell).length_squared()
		if d < best_d:
			best_d = d
			best = r
	return best	

## True only for walkable cells (Floor or Room_Floor), not walls or empty cells.
func _is_floor(cell: Vector3i) -> bool:
	var item := grid_map.get_cell_item(cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return false
	var t := director.dungeon_theme
	var lib := t.mesh_library
	return item == lib.find_item_by_name(t.floor_name) or item == lib.find_item_by_name(t.room_floor_name)
	
## Nearest walkable cell between min_dist and max_dist cells from `center`.
## Used so spawn points and portals never share a cell.
func _nearby_floor(center: Vector2i, min_dist: int = 2, max_dist: int = 5) -> Vector2i:
	# Face the way into the dungeon: toward the nearest other room.
	var toward := Vector2i.DOWN
	var best_d := 1 << 60
	for r: RoomData in director.rooms:
		var off := r.center() - center
		var d := off.length_squared()
		if d > 0 and d < best_d:
			best_d = d
			if absi(off.x) > absi(off.y):
				toward = Vector2i(signi(off.x), 0)
			else:
				toward = Vector2i(0, signi(off.y))

	# Preferred side first, then the sides, then behind the portal.
	var dirs: Array[Vector2i] = [toward, Vector2i(toward.y, toward.x),
			Vector2i(-toward.y, -toward.x), -toward]

	for d in range(min_dist, max_dist + 1):
		for dir in dirs:
			var c: Vector2i = center + dir * d
			if _is_floor(Vector3i(c.x, FLOOR_LAYER, c.y)):
				return c
		for dx in range(-d, d + 1):               # fallback: full ring
			for dz in range(-d, d + 1):
				if maxi(absi(dx), absi(dz)) != d:
					continue
				var c := center + Vector2i(dx, dz)
				if _is_floor(Vector3i(c.x, FLOOR_LAYER, c.y)):
					return c
	push_warning("No floor found near %s, using it as-is" % [center])
	return center

func _place_portal(cell: Vector2i, target: String, spawn: StringName, level: int = 0, yaw := 0.0,
		sealed_by_key := "", open_after_quest := "", routing: Dictionary = {}) -> void:
	var p := portal_scene.instantiate() as Portal
	p.set_routing(routing)
	p.target_area = target
	p.target_spawn = spawn
	p.dungeon_level = level                 # above 0 = this portal leads into another dungeon instance
	p.sealed_by_key = sealed_by_key
	p.open_after_quest = open_after_quest
	add_child(p)
	p.global_position = _grid_to_world(cell)
	p.global_basis = grid_map.global_basis.orthonormalized() * PortalMarker.portal_basis(yaw)


## The floor point `distance` metres in front of a portal, or null if that isn't floor.
func _exit_point(cell: Vector2i, yaw: float, distance: float) -> Variant:
	var c := grid_map.map_to_local(Vector3i(cell.x, FLOOR_LAYER, cell.y))
	var local := c + PortalMarker.exit_offset(yaw, distance)
	var at := grid_map.local_to_map(local)
	if not _is_floor(Vector3i(at.x, FLOOR_LAYER, at.z)):
		return null
	return grid_map.to_global(Vector3(local.x, c.y + director.dungeon_theme.floor_half_thickness, local.z))

func _grid_to_world(grid_pos: Vector2i) -> Vector3:
	var cell := Vector3i(grid_pos.x, FLOOR_LAYER, grid_pos.y)
	assert(_is_floor(cell), "No floor under spawn cell %s" % [grid_pos])
	var c := grid_map.map_to_local(cell)
	return grid_map.to_global(Vector3(c.x, c.y + director.dungeon_theme.floor_half_thickness, c.z))

func _place_portals() -> void:
	for p in director.layout.portals:
		var yaw: float = p.get("yaw", 0.0)
		_place_portal(p.cell, p.target_area, p.target_spawn, int(p.get("dungeon_level", 0)), yaw,
				str(p.get("sealed_by_key", "")), str(p.get("open_after_quest", "")), p)
		if p.arrival_id != &"":
			_arrival_cells[p.arrival_id] = p.cell
			var dist := float(p.get("exit_distance", 1.6))
			var point = _exit_point(p.cell, yaw, dist)
			if point == null:
				point = _exit_point(p.cell, yaw + PI, dist)      # wall in front: step out the back
			if point != null:
				_arrival_points[p.arrival_id] = point
			else:
				push_warning("Portal to %s: no floor %.1f m in front of it, arrivals use the nearest floor" % [p.target_area, float(p.get("exit_distance", 1.6))])
