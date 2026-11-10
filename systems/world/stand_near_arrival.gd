class_name StandNearArrival
extends Node
## Put this under an NPC in a generated dungeon (Vesper in Act IV's zones): a fixed spot can end
## up inside a wall once the layout is built, so once the navmesh is baked and the player has
## arrived, this moves its parent beside the portal the player came through: `beside` metres to
## one side of it and `ahead` metres out into the room, on walkable floor (Interactable turns it
## to face them). The portal's facing comes from the player, who arrives in front of it.
## Wherever you come in, she's there: the entrance, or the exit if you came back from the zone
## past it. With no portal near, she stands `distance` metres from the player instead.

## Metres to the side of the portal (its frame is about 2 m wide, so this leaves a gap).
@export var beside := 2.6
## Metres out from the portal into the room.
@export var ahead := 1.0
## Metres from the player when there is no portal near.
@export var distance := 3.0
## A spot counts as floor when the navmesh's closest point is this close to it (metres, flat).
@export var tolerance := 0.6
## Seconds to keep trying before leaving the NPC where it is.
@export var give_up_after := 10.0


func _ready() -> void:
	_place.call_deferred()


func _place() -> void:
	var npc := get_parent() as Node3D
	if npc == null:
		return
	var was_visible := npc.visible
	npc.visible = false                          # not seen in a wall while the zone is building
	var area := npc.get_parent()
	var waited := 0.0
	while waited < give_up_after:
		if not is_inside_tree():
			return
		var player := get_tree().get_first_node_in_group("players") as Node3D
		var ready_nav := area == null or not ("navigation_is_ready" in area) or bool(area.get("navigation_is_ready"))
		var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
		ready_nav = ready_nav and (am == null or am.can_go())   # the trip is over: the player is on their spawn
		var map := npc.get_world_3d().navigation_map
		if player != null and player.is_inside_tree() and ready_nav and map.is_valid() \
				and NavigationServer3D.map_get_iteration_id(map) > 0:
			await get_tree().create_timer(0.3).timeout   # the player has been put on their spawn by now
			if not is_inside_tree() or not is_instance_valid(player):
				return
			var spot = _beside_portal(map, npc.get_parent(), player.global_position)
			if spot == null:
				spot = _floor_near(map, player.global_position)
			if spot != null:
				npc.global_position = spot
			break
		await get_tree().process_frame
		waited += get_process_delta_time()
	npc.visible = was_visible


## A walkable point beside the portal nearest the player (right side first, then left, then a
## little further out), or null when no portal is within reach.
func _beside_portal(map: RID, area: Node, player_at: Vector3) -> Variant:
	if area == null:
		return null
	var portal: Node3D = null
	var best := 8.0                                 # metres: the arrival point is a step from its portal
	for p in area.find_children("*", "Portal", true, false):
		var d := Vector2(p.global_position.x - player_at.x, p.global_position.z - player_at.z).length()
		if d < best:
			best = d
			portal = p
	if portal == null:
		return null
	var forward := Vector3(player_at.x - portal.global_position.x, 0.0, player_at.z - portal.global_position.z)
	if forward.length() < 0.1:
		return null
	forward = forward.normalized()
	var side := forward.cross(Vector3.UP).normalized()
	for out in [ahead, ahead + 1.0]:
		for s in [1.0, -1.0]:
			var want: Vector3 = portal.global_position + side * (beside * s) + forward * out
			var got := NavigationServer3D.map_get_closest_point(map, want)
			if got != Vector3.ZERO and Vector2(got.x - want.x, got.z - want.z).length() <= tolerance:
				return got
	return null


## A walkable point `distance` from `from` (eight directions tried, nearest-to-ahead first),
## or null.
func _floor_near(map: RID, from: Vector3) -> Variant:
	for i in 8:
		var a := TAU * float(i) / 8.0 + PI * 0.25
		var want := from + Vector3(cos(a), 0.0, sin(a)) * distance
		var got := NavigationServer3D.map_get_closest_point(map, want)
		if got != Vector3.ZERO and Vector2(got.x - want.x, got.z - want.z).length() <= tolerance:
			return got
	var near := NavigationServer3D.map_get_closest_point(map, from + Vector3(1.5, 0.0, 0.0))
	return near if near != Vector3.ZERO else null
