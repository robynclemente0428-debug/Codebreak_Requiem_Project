@tool
class_name CorridorCarver
extends RefCounted

static func carve(grid: GridData, path: Array, width: int) -> void:
	var half := width / 2
	for point in path:
		for dx in range(-half, width - half):
			for dy in range(-half, width - half):
				var pos = point + Vector2i(dx, dy)
				if grid.in_safe_bounds(pos):
					grid.set_tile(pos, GridData.Tile.FLOOR)
