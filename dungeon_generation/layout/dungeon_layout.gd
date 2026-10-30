@tool
class_name DungeonLayout
extends RefCounted

const NO_CELL := Vector2i(-1, -1)

var spawns: Dictionary = {}    # spawn_id -> Vector2i cell
var rooms: Array[RoomData] = []
var spawn_cell: Vector2i = NO_CELL
var portals: Array[Dictionary] = []    # {cell, target_area, target_spawn, arrival_id}
var enemies: Array[Dictionary] = []    # {cell, definition, rarity, clear_room}
