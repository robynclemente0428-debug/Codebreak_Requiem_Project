extends Node
## Autoload: SaveManager
## Reads/writes character slot files and tracks which character(s) are being played.
## Offline only. Networking can be layered on later without changing the save format.

const SAVE_DIR := 'user://saves/'
const MAX_SLOTS := 10         # one per card on the Character Select screen
const MAX_PLAYERS := 4        # most characters that can be seated at once (1 for now)
const SAVE_VERSION := 1
const GAME_SCENE := "res://scenes/map/main.tscn"
## Save key holding the scene path of the last town visited (written by TownArea).
const LAST_TOWN_KEY := 'last_town'

# ---- session state: runtime only, never written to disk ----
var players_needed: int = 1         # 1 = single player
var party: Array[int] = []          # slot index per seat, in seat order
var creating_slot: int = -1         # empty slot being filled by Class Select
var _loaded: Dictionary = {}        # slot -> save Dictionary for this party
var _quit_dialog: ConfirmationDialog

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	
	# Stop Godot from quitting on its own when the window's X is pressed
	get_tree().auto_accept_quit = false
	
	_quit_dialog = ConfirmationDialog.new()
	CyberDialog.style(_quit_dialog)
	_quit_dialog.theme = load("res://scenes/ui/theme/cyber_theme.tres")
	_quit_dialog.title = "Quit Game"
	_quit_dialog.dialog_text = "Save and quit?"
	_quit_dialog.ok_button_text = "Save & Quit"
	_quit_dialog.cancel_button_text = "Cancel"
	_quit_dialog.process_mode = Node.PROCESS_MODE_ALWAYS   # still clickable while the game is paused
	_quit_dialog.confirmed.connect(_on_quit_confirmed)
	add_child(_quit_dialog)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()

## Call this from any "Quit Game" button too, so every exit path behaves the same.
func request_quit() -> void:
	if _quit_dialog.visible:
		return                      # ignore a second click on X while the prompt is open
	if party.is_empty():
		quit_game()                 # not in a session (e.g. main menu): nothing to save
		return
	_quit_dialog.popup_centered()

func _on_quit_confirmed() -> void:
	quit_game()


## Saves (when a character is loaded) and closes the game. Every exit path goes through here.
## Tearing down a big area (a dungeon's GridMap, collision, navmesh, enemies, lights) takes the
## engine a moment, and the window used to sit frozen on screen while it happened. So the
## window is hidden and the sound muted first, the area is freed while nobody can see it,
## and only then does the game quit.
var _quitting := false

func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	if not party.is_empty():
		save_party()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	get_window().hide()
	get_tree().paused = true
	await get_tree().process_frame               # let the OS actually take the window away
	await get_tree().process_frame
	var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
	if am != null and am.current_area != null and is_instance_valid(am.current_area):
		am.current_area.free()                   # the slow part, now off screen
		am.current_area = null
	get_tree().quit()


func _path(slot: int) -> String:
	return SAVE_DIR + 'slot_%d.json' % slot


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_path(slot))


# ---------- CREATE ----------
func create_character(slot: int, char_name: String, class_data: ClassData) -> bool:
	# Starting gear goes into the backpack; the player equips and sockets it themselves.
	var inventory: Array = []
	if class_data.starting_weapon:
		inventory.append(class_data.starting_weapon.id)
	if class_data.starting_skill_gem:
		inventory.append(class_data.starting_skill_gem.id)
	inventory.append_array(["field_health_stim", "field_mana_stim"])   # one of each to start

	var data := {
		'version': SAVE_VERSION,
		'name': char_name.strip_edges(),
		'class_id': String(class_data.id),
		'level': 1,
		'xp': 0,
		'attributes': class_data.get_attributes(),
		'equipment': {},
		'skills': [],
		'inventory': inventory,
		'playtime_seconds': 0,
		'created_at': int(Time.get_unix_time_from_system()),
	}
	return save_slot(slot, data)


# ---------- WRITE ----------
func save_slot(slot: int, data: Dictionary) -> bool:
	var tmp := _path(slot) + '.tmp'
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error('Could not write save: %s' % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, '\t'))
	f.close()
	# Write to a temp file first so a crash mid-save can't corrupt the real one
	if DirAccess.rename_absolute(tmp, _path(slot)) != OK:
		push_error('Could not finalize save for slot %d' % slot)
		return false
	return true


# ---------- READ ----------
func load_slot(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning('Slot %d is corrupted' % slot)
		return {}
	return _migrate(parsed)


## Add a step here when SAVE_VERSION goes up. Old fields from the first slot guide
## (stats, position, current_scene) are simply ignored, so no migration is needed yet.
func _migrate(data: Dictionary) -> Dictionary:
	# if data.get('version', 0) < 2:
	#     data['new_field'] = 0
	#     data['version'] = 2
	return data


# ---------- DELETE ----------
## A character that is currently seated in the party can't be deleted.
func delete_slot(slot: int) -> void:
	if slot in party:
		return
	if slot_exists(slot):
		DirAccess.remove_absolute(_path(slot))


# ---------- SESSION / PARTY ----------
## Call once before opening Character Select (e.g. from the main menu's Play button).
## Do NOT call it inside Character Select's _ready(): that scene reloads after every
## character creation and would wipe the party.
func begin_session(count: int = 1) -> void:
	players_needed = clampi(count, 1, MAX_PLAYERS)
	party.clear()
	_loaded.clear()
	creating_slot = -1


func add_to_party(slot: int) -> bool:
	if slot in party or party.size() >= players_needed:
		return false
	var data := load_slot(slot)
	if data.is_empty():
		return false
	party.append(slot)
	_loaded[slot] = data
	return true


func remove_last_from_party() -> void:
	if party.is_empty():
		return
	_loaded.erase(party.pop_back())


func party_full() -> bool:
	return party.size() == players_needed


## 0-based seat this slot holds in the party, or -1 if it isn't seated.
func party_seat_of(slot: int) -> int:
	return party.find(slot)


## Returns the live Dictionary for a slot. Edits to it are what get saved.
## Returns {} for slot -1, which the player script treats as 'no save, use defaults'.
func get_data(slot: int) -> Dictionary:
	return _loaded.get(slot, {})


## The town the party should start in: the host's (seat 0's) last visited town.
## Returns "" when there is none yet or the scene no longer exists, so the caller uses its default.
func last_town() -> String:
	if party.is_empty():
		return ""
	var path := str(get_data(party[0]).get(LAST_TOWN_KEY, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return ""
	return path


func start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


## Saves every character in the party. Each player node writes its current state
## into its slot dictionary first, then the dictionaries are written to disk.
func save_party() -> void:
	for node in get_tree().get_nodes_in_group('players'):
		if node.has_method('write_save'):
			node.write_save()
	for slot in party:
		save_slot(slot, _loaded[slot])


func end_session() -> void:
	party.clear()
	_loaded.clear()
	creating_slot = -1
