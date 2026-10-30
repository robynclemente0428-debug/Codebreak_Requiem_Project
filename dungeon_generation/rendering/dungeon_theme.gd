@tool
class_name DungeonTheme
extends Resource

@export var mesh_library: MeshLibrary
@export var cell_size: Vector3 = Vector3(2, 2, 2)
@export var wall_height: int = 2
@export var floor_half_thickness: float = 0.1

# Names of the items inside the library (the node names in your source scene)
@export var floor_name: String = "Floor"
@export var room_floor_name: String = "Room_Floor"
@export var wall_name: String = "Wall"

@export_group("Enemies")
@export var enemy_pool: Array[EnemyDefinition] = []
@export var enemies_per_room_min: int = 2
@export var enemies_per_room_max: int = 4
@export var room_rarity_weights: Dictionary = {"normal": 40, "magic": 25, "rare": 20, "champion": 15}
@export var branch_rarity_weights: Dictionary = {"normal": 40, "magic": 25, "rare": 20, "champion": 15}

@export_group("Loot")
@export var loot_pool: Array[ItemDefinition] = []
## Build the loot pool from every item definition in the project, by item level.
@export var auto_loot: bool = true
## Skill and support gems drop too. Off by default.
@export var loot_include_gems: bool = false
## Only items under these folders. Empty = all of them, e.g. ["res://data/items/weapons/"].
@export var loot_folders: PackedStringArray = []
