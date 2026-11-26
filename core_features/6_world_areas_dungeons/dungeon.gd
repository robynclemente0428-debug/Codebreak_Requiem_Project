extends GameArea

signal navigation_ready
var navigation_is_ready := false

@onready var director: DungeonDirector = $DungeonDirector
@onready var grid_map: GridMap = $NavigationRegion3D/GridMap
@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var populator: DungeonPopulator = $DungeonPopulator
@export var dungeon_level: int = 1
@export var respawn_spawn_id: StringName = &"default"
@export var portal_scene: PackedScene

const FLOOR_LAYER := 0

var _arrival_cells: Dictionary = {}
var _arrival_points: Dictionary = {}
var instance: DungeonInstance

const DUNGEON_LIGHT := 0.08


func _init() -> void:
	light_scale = DUNGEON_LIGHT


func _ready() -> void:
	instance = WorldState.begin_visit(scene_file_path, dungeon_level)
	dungeon_level = instance.level
	director.use_random_seed = false
	director.fixed_seed = instance.rng_seed
	seed(instance.rng_seed)
	if not director.generate_from_layout():
		push_error("Dungeon generation failed")
		return
	print("[Dungeon] generated, rooms: %d (instance %d, level %d, %d killed)" % [
		director.rooms.size(), instance.id, instance.level, instance.killed.size()])
	_place_portals()
	populator.instance = instance
	_spawn_enemies()
	_scatter_null_decals()
	randomize()
	var sleeper := EnemySleep.new()
	sleeper.name = "EnemySleep"
	sleeper.enemies_root = $Enemies
	add_child(sleeper)
	_bind_minimap()
	var kernel := KernelDirector.new()
	kernel.name = "KernelDirector"
	add_child(kernel)
	await _bake_navigation()


func _exit_tree() -> void:
	WorldState.end_visit(instance)

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
	var echoes := get_node_or_null("NullEchoes") as NullEchoDirector
	if echoes != null:
		populator.place_echoes(echoes, _is_floor, _grid_to_world)
	populator.place_ward_beacon(_is_floor, _grid_to_world)
	populator.place_salvage(scene_file_path, _is_floor, _grid_to_world)
	populator.place_queued_crates(scene_file_path, _is_floor, _grid_to_world)
	populator.place_props(_is_floor, _grid_to_world)

func _scatter_null_decals() -> void:
	var cells: Array[Vector2i] = []
	for c in grid_map.get_used_cells():
		if c.y == FLOOR_LAYER and _is_floor(c):
			cells.append(Vector2i(c.x, c.z))
	var rooms: Array[Rect2i] = []
	for r: RoomData in director.rooms:
		rooms.append(r.rect)
	NullDecals.scatter(self, cells, _grid_to_world, NullDecals.count_for_level(dungeon_level, cells.size()),
			instance.rng_seed ^ 0x5EED, director.dungeon_theme.cell_size.x, rooms, dungeon_level)


const NAV_SOURCE_GROUP := &"navmesh_source"
const REBAKE_DELAY := 0.6
const NAV_FOOTPRINT := 0.6

var _rebake_pending := false
var _tile_geometry: NavigationMeshSourceGeometryData3D


func _bake_navigation() -> void:
	var nm := nav_region.navigation_mesh
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = NAV_SOURCE_GROUP
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	grid_map.add_to_group(NAV_SOURCE_GROUP)
	var props := get_node_or_null("Props")
	if props != null:
		for p in props.get_children():
			if p is LootProp:
				_add_nav_obstacle(p as LootProp)
				if not (p as LootProp).opened.is_connected(_on_prop_opened):
					(p as LootProp).opened.connect(_on_prop_opened)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_region.navigation_mesh, data, nav_region)
	_tile_geometry = NavigationMeshSourceGeometryData3D.new()
	_tile_geometry.set_vertices(data.get_vertices())
	_tile_geometry.set_indices(data.get_indices())
	_bake_async(data)
	while _baking_async:
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[Dungeon] navmesh ready, polygons: %d" % nav_region.navigation_mesh.get_polygon_count())
	navigation_is_ready = true
	navigation_ready.emit()


func _add_nav_obstacle(p: LootProp) -> void:
	if p.has_node("NavObstacle"):
		return
	var ob := NavigationObstacle3D.new()
	ob.name = "NavObstacle"
	ob.avoidance_enabled = false
	ob.affect_navigation_mesh = true
	ob.height = p.collision_height
	var r := p.collision_radius * NAV_FOOTPRINT
	ob.vertices = PackedVector3Array([Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)])
	p.add_child(ob)
	ob.add_to_group(NAV_SOURCE_GROUP)


func _on_prop_opened(prop: LootProp) -> void:
	if prop.still_blocks():
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
			var base := to_region * ob.global_position
			for v in ob.vertices:
				var w := to_region * (ob.global_transform * v)
				pts.append(Vector3(w.x, 0.0, w.z))
			data.add_projected_obstruction(pts, base.y, ob.height, false)
	_bake_async(data)


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
		return _arrival_points[spawn_id]
	if layout.spawns.has(spawn_id):
		return _grid_to_world(layout.spawns[spawn_id])
	if _arrival_cells.has(spawn_id):
		return _grid_to_world(_nearby_floor(_arrival_cells[spawn_id]))
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

func _is_floor(cell: Vector3i) -> bool:
	var item := grid_map.get_cell_item(cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return false
	var t := director.dungeon_theme
	var lib := t.mesh_library
	return item == lib.find_item_by_name(t.floor_name) or item == lib.find_item_by_name(t.room_floor_name)
	
func _nearby_floor(center: Vector2i, min_dist: int = 2, max_dist: int = 5) -> Vector2i:
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

	var dirs: Array[Vector2i] = [toward, Vector2i(toward.y, toward.x),
			Vector2i(-toward.y, -toward.x), -toward]

	for d in range(min_dist, max_dist + 1):
		for dir in dirs:
			var c: Vector2i = center + dir * d
			if _is_floor(Vector3i(c.x, FLOOR_LAYER, c.y)):
				return c
		for dx in range(-d, d + 1):
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
	p.dungeon_level = level
	p.sealed_by_key = sealed_by_key
	p.open_after_quest = open_after_quest
	add_child(p)
	p.global_position = _grid_to_world(cell)
	p.global_basis = grid_map.global_basis.orthonormalized() * PortalMarker.portal_basis(yaw)


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
				point = _exit_point(p.cell, yaw + PI, dist)
			if point != null:
				_arrival_points[p.arrival_id] = point
			else:
				push_warning("Portal to %s: no floor %.1f m in front of it, arrivals use the nearest floor" % [p.target_area, float(p.get("exit_distance", 1.6))])
