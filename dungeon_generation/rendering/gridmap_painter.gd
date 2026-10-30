@tool
class_name GridMapPainter
extends RefCounted

var grid_map: GridMap
var floor_item_id: int
var room_floor_item_id: int
var wall_item_id: int

func _init(p_grid_map: GridMap, p_floor_item: int, p_room_floor_item: int, p_wall_item: int):
	grid_map = p_grid_map
	floor_item_id = p_floor_item
	room_floor_item_id = p_room_floor_item
	wall_item_id = p_wall_item

func paint(grid: GridData, wall_height: int = 2) -> void:
	grid_map.clear()
	for x in grid.width:
		for y in grid.height:
			var pos2 = Vector2i(x, y)
			var t = grid.get_tile(pos2)
			var base = Vector3i(x, 0, y)

			if t == GridData.Tile.FLOOR:
				grid_map.set_cell_item(base, floor_item_id)
			elif t == GridData.Tile.ROOM_FLOOR:
				grid_map.set_cell_item(base, room_floor_item_id)
			elif _is_adjacent_to_floor(grid, pos2):
				for h in wall_height:
					grid_map.set_cell_item(Vector3i(x, h, y), wall_item_id)
			# else: leave the cell empty entirely — open air, no mesh instanced

func _is_adjacent_to_floor(grid: GridData, pos: Vector2i) -> bool:
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
