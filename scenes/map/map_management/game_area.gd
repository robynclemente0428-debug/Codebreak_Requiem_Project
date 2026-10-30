class_name GameArea
extends Node3D
## Base class for anything the AreaManager can load: hand-built levels AND the
## procedural dungeon.
##
## Hand-built areas: add a Node3D called "SpawnPoints" with Marker3D children.
## Name each marker after a spawn id ("default", "from_dungeon", ...). Put the
## marker on the floor, a little IN FRONT of any portal so the player doesn't
## arrive standing inside the trigger.
##
## Procedural areas: override get_spawn_position() (see dungeon.gd notes).

const DEFAULT_SPAWN := &"default"


## Returns a GLOBAL position (feet level) for the given spawn id.
func get_spawn_position(spawn_id: StringName = DEFAULT_SPAWN) -> Vector3:
	var marker := get_node_or_null("SpawnPoints/" + String(spawn_id)) as Marker3D
	if marker == null:
		push_warning("%s has no spawn '%s', using 'default'" % [name, spawn_id])
		marker = get_node_or_null("SpawnPoints/" + String(DEFAULT_SPAWN)) as Marker3D
	if marker == null:
		push_error("%s needs a SpawnPoints/default Marker3D" % name)
		return global_position
	return marker.global_position
