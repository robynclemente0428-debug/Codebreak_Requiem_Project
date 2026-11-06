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
@export var links: Array[String] = []
## Short line shown when hovered, e.g. "Glitchling Queen".
@export var note: String = ""
## What fights here favour (DungeonThreats ids: "swarm", "firewalled", "reflector"): these
## are in every instance. The dungeon spawns accordingly, and its portals list them so
## players can swap scripts first.
@export var threats: Array[String] = []
## How many MORE threats each new instance rolls at random (from the ones not listed above),
## min to max. (0, 0) = always exactly `threats`.
@export var random_threats := Vector2i.ZERO
## Convoy routes only (WaypointAct.convoy_route): the stop whose exit opens this one on the
## convoy's route terminal. Empty = open from the start.
@export var route_after: String = ""
## Convoy routes only: a QuestItems id the player must have recovered too before the route
## terminal opens this stop (Checkpoint Approach waits for "iff_patched"). Empty = none.
@export var route_needs_key: String = ""
## Convoy routes only: quests that must be turned in before the route terminal opens this stop
## (Act III's quarantine levels: the Sweep waits for The Mimic and the Strategist exam).
@export var route_needs_quests: Array[String] = []
## Shown on the route map while route_needs_key or route_needs_quests is missing.
@export var route_needs_text: String = ""
