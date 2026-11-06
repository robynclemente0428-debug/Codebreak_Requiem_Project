extends Node3D
## Shows Act III's two tile sets side by side, under the game's lighting: the Quarantine Yard's
## (left) and the districts' (right), each a room with a lane through it and 2-high walls.
## No Act III district exists yet, so this is where to look at that one. Run this scene (F6).
## `TILE DETAIL` low shows them as GRAPHICS > TILE DETAIL's simple setting does.

const YARD := "res://dungeon_generation/rendering/mesh_library/act3_yard_meshes.tres"
const DISTRICT := "res://dungeon_generation/rendering/mesh_library/act3_district_meshes.tres"
const FLOOR := 0
const WALL := 1
const ROOM_FLOOR := 2
const WIDE := 11
const DEEP := 9

@export var tile_detail := true


func _ready() -> void:
	RenderingServer.global_shader_parameter_set(&"gfx_detail", 1.0 if tile_detail else 0.0)
	RenderingServer.global_shader_parameter_set(&"player_world_pos", Vector3(0, -100, 0))
	_room(YARD, Vector3(-13, 0, 0))
	_room(DISTRICT, Vector3(13, 0, 0))


## A room of Room_Floor with a lane of Floor through it, walled on all sides.
func _room(path: String, at: Vector3) -> void:
	var grid := GridMap.new()
	grid.mesh_library = load(path)
	grid.cell_size = Vector3(2, 2, 2)
	grid.position = at
	add_child(grid)
	for x in range(-WIDE / 2, WIDE / 2 + 1):
		for z in range(-DEEP / 2, DEEP / 2 + 1):
			var edge: bool = abs(x) == WIDE / 2 or abs(z) == DEEP / 2
			if edge:
				grid.set_cell_item(Vector3i(x, 0, z), WALL)
				grid.set_cell_item(Vector3i(x, 1, z), WALL)
			else:
				grid.set_cell_item(Vector3i(x, 0, z), FLOOR if z == 0 or x == 0 else ROOM_FLOOR)
