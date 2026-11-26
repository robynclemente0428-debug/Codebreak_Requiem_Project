@tool
class_name DungeonDirector
extends Node

@export_group("Grid")
@export var grid_width: int = 40
@export var grid_height: int = 40

@export_group("Corridors")
@export var corridor_width: int = 1

@export_group("Rooms")
@export var min_room_size: int = 4
@export var max_room_size: int = 5
@export var room_interval: int = 15
@export var room_min_gap: int = 4

@export_group("Branches")
@export var num_branch_rooms: int = 4

@export_group("Rendering")
@export var grid_map: GridMap
@export var dungeon_theme: DungeonTheme

@export_group("Seeding")
@export var use_random_seed: bool = true
@export var fixed_seed: int = 0

@export_group("Layout")
@export var layout_root: Node3D
@export var loop_connections: int = 1          # extra corridors beyond the minimum
@export var straight_corridors: bool = false   # L-shaped halls instead of wobbly ones
@export var filler_rooms: bool = false         # random rooms along the corridors
## Exactly this many extra rooms, placed at random in the grid and joined into the level
## like your own markers (sizes from Rooms > min/max_room_size, spacing from room_min_gap).
## Fewer are made only if they don't fit; a warning says so. 0 = off.
@export var random_rooms: int = 0
## Keep random rooms within this many cells of the route through your markers (the lines
## joining each marker room to its nearest neighbours). Short side halls instead of long
## treks to the far corners of the grid. 0 = anywhere in the grid (the old behaviour).
@export var random_room_spread: int = 0

@export_tool_button("Generate preview") var preview_btn: Callable = preview_layout
@export_tool_button("Clear preview") var clear_btn: Callable = clear_preview

var layout: DungeonLayout

var grid: GridData
var rooms: Array = []
var rng := RandomNumberGenerator.new()

func generate_map(a: Vector2i, b: Vector2i, max_retries: int = 5) -> bool:
	if use_random_seed:
		rng.randomize()
	else:
		rng.seed = fixed_seed
	
	for attempt in max_retries:
		grid = GridData.new(grid_width, grid_height)
		rooms.clear()
		
		var path = PathGenerator.generate(grid, a, b, rng)
		CorridorCarver.carve(grid, path, corridor_width)
		rooms += RoomGenerator.place_along_path(grid, path, rng, min_room_size, max_room_size, room_interval, room_min_gap)
		rooms += BranchGenerator.generate(grid, path, rng, num_branch_rooms, min_room_size, max_room_size, rooms, room_min_gap)
		
		if ConnectivityChecker.validate(grid, a, b):
			return _paint()

		push_warning("Dungeon generation attempt %d failed connectivity check, retrying..." % (attempt + 1))
	
	push_error("Dungeon generation failed after %d attempts." % max_retries)
	return false

func generate_from_layout(max_retries: int = 5) -> bool:
	if layout_root == null:
		push_error("DungeonDirector: layout_root not assigned")
		return false
	layout = DungeonLayoutReader.read(layout_root, grid_map, grid_width, grid_height)
	print("Layout root: %s, markers found: %d, spawn: %s" % [
	layout_root.get_path(), layout.rooms.size(), layout.spawn_cell])
	if layout.spawn_cell == DungeonLayout.NO_CELL:
		push_error("Layout needs one SpawnMarker")
		return false

	if use_random_seed:
		rng.randomize()
	else:
		rng.seed = fixed_seed

	for attempt in max_retries:
		grid = GridData.new(grid_width, grid_height)
		rooms.clear()
		rooms += layout.rooms
		var extra := _random_rooms(layout.rooms)
		rooms += extra

		# 1. corridors first, 2. extras, 3. every room last so rooms overwrite corridor tiles
		var cells: Array = _connect_rooms(layout.rooms + extra)
		if not cells.is_empty():
			if filler_rooms:
				rooms += RoomGenerator.place_along_path(grid, cells, rng, min_room_size,
						max_room_size, room_interval, room_min_gap, rooms)
			if num_branch_rooms > 0:
				rooms += BranchGenerator.generate(grid, cells, rng, num_branch_rooms,
						min_room_size, max_room_size, rooms, room_min_gap)
		for r: RoomData in rooms:
			RoomGenerator.carve_room(grid, r.rect)

		var targets: Array[Vector2i] = []
		for r: RoomData in rooms:
			targets.append(r.center())
		for s in layout.spawns.values():
			targets.append(s)
		for en in layout.enemies:
			targets.append(en["cell"])
		if ConnectivityChecker.validate_all(grid, layout.spawn_cell, targets):
			return _paint()
		push_warning("Layout attempt %d failed connectivity, retrying..." % (attempt + 1))

	push_error("Layout generation failed after %d attempts" % max_retries)
	return false

## `random_rooms` new rooms that don't touch `existing` (or each other), anywhere in the grid.
func _random_rooms(existing: Array) -> Array:
	var out: Array = []
	if random_rooms <= 0:
		return out
	var lo := maxi(min_room_size, 3)
	var hi := maxi(max_room_size, lo)
	var taken: Array = existing.duplicate()
	var route := _marker_route(existing) if random_room_spread > 0 else []
	var tries := 0
	while out.size() < random_rooms and tries < random_rooms * 60:
		tries += 1
		var size := Vector2i(rng.randi_range(lo, hi), rng.randi_range(lo, hi))
		var pos := Vector2i(rng.randi_range(2, grid_width - size.x - 2),
				rng.randi_range(2, grid_height - size.y - 2))
		if not route.is_empty():
			# a random spot on the route, pushed up to `random_room_spread` cells off it
			var seg: Array = route[rng.randi() % route.size()]
			var on := Vector2(seg[0]).lerp(Vector2(seg[1]), rng.randf())
			var off := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * random_room_spread
			var c := Vector2i((on + off).round()) - size / 2
			pos = Vector2i(clampi(c.x, 2, grid_width - size.x - 2), clampi(c.y, 2, grid_height - size.y - 2))
		var rect := Rect2i(pos, size)
		if RoomGenerator.room_overlaps(rect, taken, maxi(room_min_gap, 2)):
			continue
		var room := RoomData.new(rect, "generic")
		out.append(room)
		taken.append(room)
	if out.size() < random_rooms:
		push_warning("DungeonDirector: only %d of %d random rooms fit (grid %dx%d)"
				% [out.size(), random_rooms, grid_width, grid_height])
	return out


## The route through the marker rooms: a minimum spanning tree over their centres, as
## [from, to] cell pairs. Random rooms gather along it when random_room_spread is set.
func _marker_route(list: Array) -> Array:
	var segs: Array = []
	if list.size() < 2:
		return segs
	var in_tree: Array[int] = [0]
	var pending: Array[int] = []
	for i in range(1, list.size()):
		pending.append(i)
	while not pending.is_empty():
		var best := Vector2i(-1, -1)
		var best_d := 1 << 60
		for i in in_tree:
			for j in pending:
				var d := _room_dist(list[i], list[j])
				if d < best_d:
					best_d = d
					best = Vector2i(i, j)
		segs.append([list[best.x].center(), list[best.y].center()])
		in_tree.append(best.y)
		pending.erase(best.y)
	return segs


# Minimum spanning tree over room centres, so every room joins the network.
func _connect_rooms(list: Array) -> Array:
	var cells: Array = []
	if list.size() < 2:
		return cells
	var in_tree: Array[int] = [0]
	var pending: Array[int] = []
	for i in range(1, list.size()):
		pending.append(i)

	while not pending.is_empty():
		var best := Vector2i(-1, -1)
		var best_d := 1 << 60
		for i in in_tree:
			for j in pending:
				var d := _room_dist(list[i], list[j])
				if d < best_d:
					best_d = d
					best = Vector2i(i, j)
		cells += _link(list[best.x], list[best.y])
		in_tree.append(best.y)
		pending.erase(best.y)

	for k in loop_connections:
		var a := rng.randi() % list.size()
		var b := rng.randi() % list.size()
		if a != b:
			cells += _link(list[a], list[b])
	return cells

func _room_dist(a: RoomData, b: RoomData) -> int:
	var d := a.center() - b.center()
	return absi(d.x) + absi(d.y)

func _link(a: RoomData, b: RoomData) -> Array:
	a.add_connection(b)
	b.add_connection(a)
	if a.rect.grow(1).intersects(b.rect):
		return []                                  # touching or overlapping: already joined
	var path: Array = _l_path(a.center(), b.center()) if straight_corridors \
			else PathGenerator.generate(grid, a.center(), b.center(), rng)
	CorridorCarver.carve(grid, path, corridor_width)
	return path

func _l_path(a: Vector2i, b: Vector2i) -> Array:
	var path: Array = []
	var p := a
	while p.x != b.x:
		p.x += signi(b.x - p.x)
		path.append(p)
	while p.y != b.y:
		p.y += signi(b.y - p.y)
		path.append(p)
	return path

func preview_layout() -> void:
	if generate_from_layout():
		print("Preview: %d rooms" % rooms.size())

func clear_preview() -> void:
	grid_map.clear()
	

func _paint() -> bool:
	grid_map.mesh_library = dungeon_theme.mesh_library
	grid_map.cell_size = dungeon_theme.cell_size

	var lib := dungeon_theme.mesh_library
	var floor_id := lib.find_item_by_name(dungeon_theme.floor_name)
	var room_id := lib.find_item_by_name(dungeon_theme.room_floor_name)
	var wall_id := lib.find_item_by_name(dungeon_theme.wall_name)
	if floor_id == -1 or room_id == -1 or wall_id == -1:
		push_error("Theme library is missing an item named Floor / Room_Floor / Wall")
		return false

	var painter := GridMapPainter.new(grid_map, floor_id, room_id, wall_id)
	painter.paint(grid, dungeon_theme.wall_height)
	return true
