extends Node
## Builds the Act II convoy camp prototype (scenes/map/town/act_2_convoy.tscn) and saves it.
## Open build_convoy_camp.tscn and press F6 (Run Current Scene), or from the project folder:
##   godot --headless --path . res://tools/convoy/build_convoy_camp.tscn
## Re-running overwrites the scene. To change the deck, move the RoomMarkers in the saved scene
## and press Generate preview on its DungeonDirector instead (then save), like the Act I town.
##
## The barge points along +X (ConvoyMotion.heading): main deck in the middle, the bow platform
## with the portal in front, and a cargo pod off to one side on a narrow bridge over the void.

const OUT := "res://scenes/map/town/act_2_convoy.tscn"
const THEME := "res://dungeon_generation/rendering/mesh_library/resources/convoy_deck.tres"
## The town's tile set with convoy_deck_plate.png on the floor tiles, saved for the convoy theme.
const TOWN_TILES := "res://dungeon_generation/rendering/mesh_library/hardfault_town_meshes.tres"
const DECK_TILES := "res://dungeon_generation/rendering/mesh_library/convoy_deck_meshes.tres"
const DECK_PLATE := "res://assets/textures/convoy/convoy_deck_plate.png"
const BACKDROP := "res://assets/shaders/convoy/act2_convoy_void.tres"
const VENDOR := "res://scenes/loot/shop_npc/general_vendor.tscn"
const VENDOR_MODEL := "res://scenes/loot/shop_npc/rogue_vendor.tscn"
const PORTAL_TO := "res://scenes/map/town/act_1_town.tscn"

# name, position (metres, 2 m cells), room size in cells
# The deck is kept narrow so the void shows on both sides wherever you stand.
const ROOMS := [
	["MainDeck", Vector3(40, 0, 30), Vector2i(24, 4)],
	["Bow", Vector3(70, 0, 30), Vector2i(5, 4)],
	["CargoPod", Vector3(44, 0, 12), Vector2i(5, 4)],
]


func _ready() -> void:
	_build.call_deferred()


func _build() -> void:
	_make_deck_tiles()
	var root := Node3D.new()
	root.name = "Act2Convoy"
	root.set_script(load("res://scenes/map/town/town_area.gd"))
	root.set("backdrop", load(BACKDROP))
	root.set("null_decals", 0)                     # the convoy is clean: the Null is behind us
	get_tree().root.add_child(root)

	var director := DungeonDirector.new()
	director.name = "DungeonDirector"
	director.grid_width = 60
	director.grid_height = 40
	director.min_room_size = 0
	director.max_room_size = 0
	director.room_interval = 0
	director.room_min_gap = 0
	director.num_branch_rooms = 0
	director.use_random_seed = false
	director.loop_connections = 0
	director.straight_corridors = true
	var theme: DungeonTheme = load(THEME)
	theme.mesh_library = load(DECK_TILES)
	ResourceSaver.save(theme, THEME)
	director.dungeon_theme = theme
	root.add_child(director)

	var nav := NavigationRegion3D.new()
	nav.name = "NavigationRegion3D"
	nav.navigation_mesh = NavigationMesh.new()
	root.add_child(nav)
	var gm := GridMap.new()
	gm.name = "GridMap"
	nav.add_child(gm)

	var layout := Node3D.new()
	layout.name = "Layout"
	root.add_child(layout)
	for r in ROOMS:
		var m := RoomMarker.new()
		m.name = r[0]
		m.room_size = r[2]
		layout.add_child(m)
		m.position = r[1]
	var spawn := SpawnMarker.new()
	spawn.name = "default"
	spawn.create_room = false
	layout.add_child(spawn)
	spawn.position = Vector3(36, 0, 30)
	var portal := PortalMarker.new()
	portal.name = "PortalToHardfault"
	portal.target_area = PORTAL_TO
	portal.target_spawn = &"from_convoy"
	portal.arrival_spawn_id = &"act_2_convoy"
	portal.room_size = Vector2i(3, 3)
	layout.add_child(portal)
	portal.position = Vector3(72, 0, 30)
	portal.rotation.y = -PI * 0.5                  # arrivals step out towards the deck

	director.grid_map = gm
	director.layout_root = layout
	if not director.generate_from_layout():
		push_error("Convoy: layout failed")
		get_tree().quit(1)
		return

	var motion := ConvoyMotion.new()
	motion.name = "ConvoyMotion"
	root.add_child(motion)
	var dressing := ConvoyDressing.new()
	dressing.name = "ConvoyDressing"
	root.add_child(dressing)

	# A placeholder quartermaster on the deck, so the camp has someone in it
	var vendor := (load(VENDOR) as PackedScene).instantiate()
	vendor.name = "Quartermaster"
	root.add_child(vendor)
	vendor.position = Vector3(45, 1.1, 29)
	vendor.set("npc_id", "quartermaster")
	vendor.set("npc_name", "Quartermaster")
	vendor.set("info_title", "Convoy Supplies")
	vendor.set("model_scene", load(VENDOR_MODEL))
	vendor.set("dialogue", null)                  # straight to the shop

	# Save only what this tool made. The town and the dressing build the rest when they load
	# (the backdrop quad, engines, dust), so those must not be saved into the scene too.
	for n in [director, nav, gm, layout, motion, dressing, vendor]:
		n.owner = root
	for m in layout.get_children():
		m.owner = root
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("CONVOY saved %s: %s, %d deck cells" % [OUT, error_string(err), gm.get_used_cells().size()])
	get_tree().quit(0 if err == OK else 1)


## A copy of the town's tiles whose Floor and Room_Floor show the deck plate, one plate per tile.
## Mapped in each tile's own space (triplanar, not world: the town is turned 45 degrees), so it
## lines up with the tiles whatever the floor mesh's own UVs are.
func _make_deck_tiles() -> void:
	var lib := (load(TOWN_TILES) as MeshLibrary).duplicate() as MeshLibrary
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(DECK_PLATE)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.5          # the tile spans -1..1 m: one plate per 2 m tile
	mat.uv1_offset = Vector3.ONE * 0.5         # plate edges on the tile edges
	mat.metallic = 0.4
	mat.roughness = 0.55
	for item_name in ["Floor", "Room_Floor"]:
		var id := lib.find_item_by_name(item_name)
		if id == -1:
			continue
		var mesh := lib.get_item_mesh(id).duplicate() as Mesh
		if mesh is ArrayMesh:
			for i in mesh.get_surface_count():
				(mesh as ArrayMesh).surface_set_material(i, mat)
		elif mesh is PrimitiveMesh:
			(mesh as PrimitiveMesh).material = mat
		lib.set_item_mesh(id, mesh)
	var err := ResourceSaver.save(lib, DECK_TILES)
	print("CONVOY deck tiles: ", error_string(err))
