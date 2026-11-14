class_name TownArea
extends GameArea
## A town or hideout (one per act). Arriving heals you and saves the game, and any change you
## make while in town (gear, skills, backpack) is saved a moment later.
##
## Saving uses the normal SaveManager.save_party(), which writes everything the player owns
## (equipment, skills with supports and programs, backpack, credits, quests).
##
## AreaManager calls on_player_arrived(player) once the player has been placed.
##
## Towns built with a DungeonDirector (tiles painted with Generate preview) can use the same
## layout markers as dungeons:
##   SpawnMarker   spawn_id = where players asking for that id appear (exact cell)
##   PortalMarker  becomes a real portal (portal_scene) with its target_area / target_spawn /
##                 dungeon_level, and players asking for its arrival_spawn_id land beside it
## A spawn id is looked up in that order, then in SpawnPoints/<id> (hand-placed Marker3Ds),
## then falls back to "default".

## The act this town is the hub of ("I" Hardfault, "II" the convoy). Quests tagged for another
## act (QuestDefinition metadata/act) can't be started here: see QuestManager.can_start.
@export var act := "I"
@export var autosave_delay_sec: float = 1.0     # wait this long after the last change
@export var heal_on_arrival: bool = true
## Spawned at every PortalMarker in the layout. Its root must use portal.gd.
@export var portal_scene: PackedScene = preload("res://scenes/map/map_management/portal.tscn")
## Null stains on the town's floor (see NullDecals). The town held, so only a few. 0 = none.
@export var null_decals: int = 8

const FLOOR_LAYER := 0

var _director: DungeonDirector
var _layout: DungeonLayout
var _arrival_cells: Dictionary = {}     # arrival_spawn_id -> portal cell (fallback)
var _arrival_points: Dictionary = {}    # arrival_spawn_id -> world point in front of the portal

var _player: Player
var _dirty := false
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = autosave_delay_sec
	_timer.timeout.connect(_save_now)
	add_child(_timer)
	_read_layout()
	_scatter_null_decals()
	_bind_minimap.call_deferred()            # once the NPCs below us are ready too


# ---------- MINIMAP ----------
## Towns aren't generated, so the director has no GridData: build one from the painted floor
## tiles, then show the whole town (no fog) with its NPCs marked.
func _bind_minimap() -> void:
	if _layout == null:
		return                                   # hand-built town without a tile grid: no map
	var mm := get_tree().get_first_node_in_group("minimap") as Minimap
	if mm == null:
		return
	if _director.grid == null:
		var g := GridData.new(_director.grid_width, _director.grid_height)
		for cell in _director.grid_map.get_used_cells():
			if cell.y == FLOOR_LAYER and _is_floor(Vector2i(cell.x, cell.z)):
				g.set_tile(Vector2i(cell.x, cell.z), GridData.Tile.FLOOR)
		_director.grid = g
	var npcs: Array = find_children("*", "DialogueNPC", true, false)
	var terminals: Array = find_children("*", "RouteTerminal", true, false)
	# The convoy's machines the Null go for in a breach (DeckSystem)
	var systems: Array = find_children("*", "Area3D", true, false).filter(
			func(n: Node) -> bool: return n.has_method("is_offline") and "map_glyph" in n)
	mm.bind_dungeon(_director, _director.grid_map, null,
			{"town": true, "npcs": npcs, "terminals": terminals, "systems": systems})


## Seeded by the scene's name, so the stains are in the same places every visit.
func _scatter_null_decals() -> void:
	if _layout == null or null_decals <= 0:
		return
	var cells: Array[Vector2i] = []
	for c in _director.grid_map.get_used_cells():
		if c.y == FLOOR_LAYER and _is_floor(Vector2i(c.x, c.z)):
			cells.append(Vector2i(c.x, c.z))
	NullDecals.scatter(self, cells, _cell_to_world, null_decals, hash(name),
			_director.dungeon_theme.cell_size.x)


# ---------- LAYOUT MARKERS ----------
## Reads the markers of an already painted layout. Nothing is generated: the tiles were baked
## into the GridMap in the editor.
func _read_layout() -> void:
	for child in get_children():
		if child is DungeonDirector:
			_director = child
			break
	if _director == null or _director.layout_root == null or _director.grid_map == null:
		return
	if _director.grid_map.get_used_cells().is_empty():
		push_warning("%s: the GridMap is empty. Press Generate preview on the DungeonDirector and save." % name)
		return
	_layout = DungeonLayoutReader.read(_director.layout_root, _director.grid_map,
			_director.grid_width, _director.grid_height)
	_director.layout = _layout
	var gm := _director.grid_map
	for p in _layout.portals:
		var yaw: float = p.get("yaw", 0.0)
		if p.arrival_id != &"":
			_arrival_cells[p.arrival_id] = p.cell
			var c := gm.map_to_local(Vector3i(p.cell.x, FLOOR_LAYER, p.cell.y))
			for side in [0.0, PI]:                            # front first; wall there: the back
				var local := c + PortalMarker.exit_offset(yaw + side, float(p.get("exit_distance", 1.6)))
				var at := gm.local_to_map(local)
				if _is_floor(Vector2i(at.x, at.z)):
					_arrival_points[p.arrival_id] = gm.to_global(Vector3(local.x,
							c.y + _director.dungeon_theme.floor_half_thickness, local.z))
					break
		if portal_scene == null:
			continue
		var portal := portal_scene.instantiate() as Portal
		portal.target_area = p.target_area
		portal.target_spawn = p.target_spawn
		portal.dungeon_level = int(p.get("dungeon_level", 0))
		portal.sealed_by_key = str(p.get("sealed_by_key", ""))       # the dock: sealed until it's held
		portal.open_after_quest = str(p.get("open_after_quest", ""))
		portal.set_routing(p)
		add_child(portal)
		portal.global_position = _cell_to_world(p.cell)
		portal.global_basis = gm.global_basis.orthonormalized() * PortalMarker.portal_basis(yaw)


func get_spawn_position(spawn_id: StringName = DEFAULT_SPAWN) -> Vector3:
	if _layout != null:
		if _arrival_points.has(spawn_id):
			return _arrival_points[spawn_id]                  # stepping out of the portal
		if _layout.spawns.has(spawn_id):
			return _cell_to_world(_layout.spawns[spawn_id])
		if _arrival_cells.has(spawn_id):
			return _cell_to_world(_floor_near(_arrival_cells[spawn_id]))
	if get_node_or_null("SpawnPoints/" + String(spawn_id)) != null:
		return super(spawn_id)
	if _layout != null and _layout.spawn_cell != DungeonLayout.NO_CELL:
		# "default" if the layout has one, otherwise its first SpawnMarker
		if spawn_id != DEFAULT_SPAWN or not _layout.spawns.has(DEFAULT_SPAWN):
			push_warning("%s has no spawn '%s', using %s" % [name, spawn_id,
					"'default'" if _layout.spawns.has(DEFAULT_SPAWN) else "its first SpawnMarker"])
		return _cell_to_world(_layout.spawn_cell)
	return super(spawn_id)


func _is_floor(cell: Vector2i) -> bool:
	var item := _director.grid_map.get_cell_item(Vector3i(cell.x, FLOOR_LAYER, cell.y))
	if item == GridMap.INVALID_CELL_ITEM:
		return false
	var t := _director.dungeon_theme
	var lib := t.mesh_library
	return item == lib.find_item_by_name(t.floor_name) or item == lib.find_item_by_name(t.room_floor_name)


## Top of the floor tile at `cell`, in world space.
func _cell_to_world(cell: Vector2i) -> Vector3:
	var gm := _director.grid_map
	var c := gm.map_to_local(Vector3i(cell.x, FLOOR_LAYER, cell.y))
	return gm.to_global(Vector3(c.x, c.y + _director.dungeon_theme.floor_half_thickness, c.z))


## A floor cell 2..5 cells from `center`, so arrivals don't land inside the portal's trigger.
func _floor_near(center: Vector2i) -> Vector2i:
	for d in range(2, 6):
		for dir in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
			if _is_floor(center + dir * d):
				return center + dir * d
	return center


func on_player_arrived(player: Node3D) -> void:
	_player = player as Player
	if _player == null:
		return
	if heal_on_arrival:
		_player.health.heal(_player.stats.get_stat(StatTypes.Stat.MAX_HEALTH))
		_player.mana.initialize()                 # refill mana too
		# and every stim's charges: in Act III only to half once a Yard Sweep took the med stores
		var refill := YardCrates.stim_refill(_player.quests) if act == "III" else 1.0
		get_tree().call_group("stim_hud", "refill_all", refill)
		if refill < 1.0:
			QuestItems.toast(get_tree(), "THE MED STORES ARE GONE\nStims refill to half here.%s" % (
				" C-0's deletion queue in the Sweep still holds them." if YardCrates.is_queued(_player.quests, "CargoE") else ""),
				YardCrates.COL)
	_connect_once(_player.inventory.changed)
	_connect_once(_player.equipment.equipment_changed)
	_connect_once(_player.skills.changed)
	_remember_town()
	# Quest event: arriving in this town ("enter_area", "act_2_convoy"): THE ROAD OUT
	GameEvents.report("enter_area", scene_file_path.get_file().get_basename())
	_save_now()


## Records this town in every seated character's save, so logging back in starts here.
func _remember_town() -> void:
	if scene_file_path.is_empty() or Coop.visiting:   # co-op: a visitor logs back in to their own town
		return
	for slot in SaveManager.party:
		SaveManager.get_data(slot)[SaveManager.LAST_TOWN_KEY] = scene_file_path


func _connect_once(sig: Signal) -> void:
	if not sig.is_connected(_mark_dirty):
		sig.connect(_mark_dirty)


func _mark_dirty() -> void:
	if not is_inside_tree():
		return
	_dirty = true
	_timer.start()                                # restarts, so a burst of changes saves once


func _save_now() -> void:
	if _player == null or not is_instance_valid(_player) or SaveManager.party.is_empty():
		return
	SaveManager.save_party()
	_dirty = false


func _exit_tree() -> void:
	if _dirty:
		_save_now()                               # leaving town through a portal
	# The player outlives the town, so stop listening to it
	if _player != null and is_instance_valid(_player):
		for sig in [_player.inventory.changed, _player.equipment.equipment_changed, _player.skills.changed]:
			if sig.is_connected(_mark_dirty):
				sig.disconnect(_mark_dirty)
