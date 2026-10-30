class_name WaypointAct
extends Resource
## The waypoint map of one act: its title and every place on it.

@export var act_number: int = 1
@export var title: String = "ACT I"
@export var subtitle: String = ""
@export var waypoints: Array[Waypoint] = []


func find(id: String) -> Waypoint:
	for w in waypoints:
		if w.id == id:
			return w
	return null


func find_by_scene(scene_path: String) -> Waypoint:
	var p := Waypoints.normalize(scene_path)
	for w in waypoints:
		if Waypoints.normalize(w.scene) == p:
			return w
	return null
