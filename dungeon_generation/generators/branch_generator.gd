@tool
class_name BranchGenerator
extends RefCounted

static func generate(grid: GridData, path: Array, rng: RandomNumberGenerator,
		count: int, min_size: int, max_size: int, existing_rooms: Array, min_gap: int = 3) -> Array:
	var rooms: Array = []
	
	for i in count:
		var origin = path[rng.randi() % path.size()]
		var branch_length = rng.randi_range(4, 10)
		var dir = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT][rng.randi() % 4]
		
		var branch_path: Array = []
		var pos = origin
		for step in branch_length:
			var next = pos + dir
			if grid.in_safe_bounds(next):
				pos = next
			branch_path.append(pos)
		
		var w = rng.randi_range(min_size, max_size)
		var h = rng.randi_range(min_size, max_size)
		var rect = Rect2i(pos.x - w / 2, pos.y - h / 2, w, h)
		rect = rect.intersection(Rect2i(1, 1, grid.width - 2, grid.height - 2))
		
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		
		if RoomGenerator.room_overlaps(rect, existing_rooms + rooms, min_gap):
			continue
		
		CorridorCarver.carve(grid, branch_path, 1)
		
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				grid.set_tile(Vector2i(x, y), GridData.Tile.ROOM_FLOOR)
		rooms.append(RoomData.new(rect, "branch"))
			
	return rooms
