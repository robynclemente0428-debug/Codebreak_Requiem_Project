@tool
class_name GridData
extends RefCounted

enum Tile {
	WALL, 
	FLOOR, 
	ROOM_FLOOR
}

var width: int
var height: int
var cells: Array

func _init(w: int, h: int):
	width = w
	height = h
	cells = []
	for x in w:
		cells.append([])
		for y in h:
			cells[x].append(Tile.WALL)

func get_tile(pos: Vector2i) -> int:
	if not in_bounds(pos):
		return Tile.WALL
	return cells[pos.x][pos.y]

func set_tile(pos: Vector2i, tile: int) -> void:
	if in_bounds(pos):
		cells[pos.x][pos.y] = tile

func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height

func in_safe_bounds(pos: Vector2i, margin: int = 1) -> bool:
	# keeps generation away from the very edge of the map
	return pos.x >= margin and pos.x < width - margin and pos.y >= margin and pos.y < height - margin
