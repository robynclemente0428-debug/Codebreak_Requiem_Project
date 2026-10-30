class_name Waypoint
extends Resource
## One place on an act's waypoint map: a town or a dungeon the player can teleport to once
## they have been there. Listed in a WaypointAct (data/waypoints/act_*.tres).

enum Kind { TOWN, DUNGEON, BOSS }

@export var id: String = ""
@export var display_name: String = ""
## The area scene. Use the same spelling (uid:// or res://) your portals use; both are accepted.
@export_file("*.tscn") var scene: String = ""
## Where teleporting puts you in that scene: a SpawnMarker id or SpawnPoints/<id>.
@export var spawn_id: StringName = &"default"
## Above 0 for dungeons: the instance level, the same number its portals use.
@export var dungeon_level: int = 0
@export var kind: Kind = Kind.DUNGEON
## Position on the act map, 0..1 across and down.
@export var map_position: Vector2 = Vector2(0.5, 0.5)
## Ids of the waypoints this one is drawn connected to.
@export var links: PackedStringArray = []
## Short line shown when hovered, e.g. "Glitchling Queen".
@export var note: String = ""
