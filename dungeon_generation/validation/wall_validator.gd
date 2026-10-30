# validation/wall_validator.gd
class_name WallValidator
extends RefCounted

static func find_missing_walls(grid: GridData, grid_map: GridMap) -> Array:
	var missing: Array = []

	for x in grid.width:
		for y in grid.height:
			var pos2 = Vector2i(x, y)
			var t = grid.get_tile(pos2)

			# only check cells that SHOULD be walls (wall tile, adjacent to floor)
			if t == GridData.Tile.WALL and _is_adjacent_to_floor(grid, pos2):
				var cell3 = Vector3i(x, 0, y)
				var item = grid_map.get_cell_item(cell3)
				if item == GridMap.INVALID_CELL_ITEM:
					missing.append(pos2)

	return missing

static func _is_adjacent_to_floor(grid: GridData, pos: Vector2i) -> bool:
	var dirs = [
		Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
	]
	for d in dirs:
		var n = pos + d
		if grid.in_bounds(n):
			var nt = grid.get_tile(n)
			if nt == GridData.Tile.FLOOR or nt == GridData.Tile.ROOM_FLOOR:
				return true
	return false
