class_name WaypointAct
extends Resource
## The waypoint map of one act: its title and every place on it.

@export var act_number: int = 1
@export var title: String = "ACT I"
@export var subtitle: String = ""
@export var waypoints: Array[Waypoint] = []
## A convoy act (Act II): its dungeons are stops reached from the convoy's route terminal
## (RouteTerminal), not from the waypoint map, and their portals lead back to the convoy.
## Stops open in order (Waypoint.route_after) as their exits are reached.
@export var convoy_route := false


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
