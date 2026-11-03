class_name RouteTerminal
extends Interactable
## The convoy's route terminal. Act II's dungeons are stops on the convoy's route, not places
## on the waypoint map: use the terminal (walk up and press the interact key, or click it from
## anywhere on deck) to open the route map (WaypointPanel.open_route), then click a stop to be
## dropped at its entrance. Both of a stop's portals lead back to the convoy; reaching its exit
## opens the next stop (Waypoints.clear_stop).

## The name on its plate and hover tag (NpcNameplates, NpcInfoPanel read npc_name).
@export var npc_name: String = "Route Terminal"
## The act whose stops it lists. Empty = the act of the area it stands in (Waypoints).
@export var route_act: WaypointAct


func _ready() -> void:
	super._ready()
	face_player = false                           # a console doesn't turn round


func interact(_player: Node3D) -> void:
	var panel := get_tree().get_first_node_in_group("waypoint_panel") as WaypointPanel
	if panel == null:
		return
	var act := route_act
	if act == null:
		var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
		act = Waypoints.act_of_scene(am.current_scene_path()) if am != null else null
	if act == null:
		push_warning("RouteTerminal: no route act for this area")
		return
	panel.open_route(act)
