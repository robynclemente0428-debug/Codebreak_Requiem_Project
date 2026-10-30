class_name Portal
extends Area3D
## A gate/portal/door trigger. Build it as a scene: Area3D (this script) +
## CollisionShape3D (box) + any visual mesh. Place it in an area and set the
## two exports below.

## Scene to load (must have a GameArea root).
@export_file("*.tscn") var target_area: String
## Which spawn marker/id to arrive at in that scene.
@export var target_spawn: StringName = &"default"
## Above 0, this portal leads into a dungeon instance of that level (see WorldState).
## Leave it at 0 for portals into towns and hand-built areas.
@export var dungeon_level: int = 0
## 0 = rejoin this dungeon's open instance (or open one), -1 = always a fresh instance,
## above 0 = that exact instance (for a gate screen that lists open dungeons).
@export var instance_id: int = 0


func _ready() -> void:
	# The player is on physics layer 3 (value 4), see player.tscn.
	collision_layer = 5
	collision_mask = 3
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body is Player:
		return
	var manager := get_tree().get_first_node_in_group("area_manager") as AreaManager
	if manager == null:
		push_error("Portal: no AreaManager found in the scene")
		return
	# Deferred: we are inside a physics callback, and the manager is about to
	# free the area that contains this very Area3D.
	manager.go_to.call_deferred(target_area, target_spawn, dungeon_level, instance_id)
