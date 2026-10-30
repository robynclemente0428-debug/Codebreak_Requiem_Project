@tool
class_name SpawnMarker
extends DungeonMarker

@export var spawn_id: StringName = &"default"   # the id other areas ask for, e.g. &"exit"
@export var create_room: bool = true            # off = just a point inside another marker's room

func _marker_color() -> Color: return Color(0.2, 0.9, 0.3, 0.3)
