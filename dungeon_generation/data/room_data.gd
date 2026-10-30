@tool
class_name RoomData
extends RefCounted

var rect: Rect2i
var connections: Array = []  # other RoomData this room connects to
var room_type: String = "generic"  # "start", "end", "branch", "generic" etc.

func _init(p_rect: Rect2i, p_type: String = "generic"):
	rect = p_rect
	room_type = p_type

func center() -> Vector2i:
	return Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)

func add_connection(other: RoomData) -> void:
	if not connections.has(other):
		connections.append(other)
