@tool
class_name RoomGenerator
extends RefCounted

static func place_along_path(grid: GridData, path: Array, rng: RandomNumberGenerator,
		min_size: int, max_size: int, interval: int, min_gap: int = 3, existing: Array = []) -> Array:
	var rooms: Array = []
	var i = 0

	while i < path.size():
		var center = path[i]
		var w = rng.randi_range(min_size, max_size)
		var h = rng.randi_range(min_size, max_size)
		var rect = Rect2i(center.x - w / 2, center.y - h / 2, w, h)
		rect = rect.intersection(Rect2i(1, 1, grid.width - 2, grid.height - 2))

		if rect.size.x > 0 and rect.size.y > 0 and not room_overlaps(rect, rooms + existing, min_gap):
			carve_room(grid, rect)
			rooms.append(RoomData.new(rect))

		i += interval + rng.randi_range(-2, 2)

	return rooms

static func room_overlaps(rect: Rect2i, rooms: Array, margin: int) -> bool:
	var padded = Rect2i(rect.position - Vector2i(margin, margin), rect.size + Vector2i(margin * 2, margin * 2))
	for room in rooms:
		if padded.intersects(room.rect):
			return true
	return false

static func carve_room(grid: GridData, rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			grid.set_tile(Vector2i(x, y), GridData.Tile.ROOM_FLOOR)
