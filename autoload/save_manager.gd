extends Node
## Autoload: SaveManager
## Reads/writes character slot files and tracks which character(s) are being played.
## Offline only. Networking can be layered on later without changing the save format.

const SAVE_DIR := 'user://saves/'
const MAX_SLOTS := 10         # one per card on the Character Select screen
const MAX_PLAYERS := 4        # most characters that can be seated at once (1 for now)
const SAVE_VERSION := 1
const GAME_SCENE := "res://scenes/map/main.tscn"
const AUTOSAVE_SECONDS := 120.0
## Save key holding the scene path of the last town visited (written by TownArea).
const LAST_TOWN_KEY := 'last_town'

# ---- session state: runtime only, never written to disk ----
var players_needed: int = 1         # 1 = single player
var party: Array[int] = []          # slot index per seat, in seat order
var creating_slot: int = -1         # empty slot being filled by Class Select
var _loaded: Dictionary = {}        # slot -> save Dictionary for this party
var _quit_dialog: ConfirmationDialog
var _play_accum := 0.0              # seconds played since the last save_party()
var _autosave_timer: Timer

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
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_SECONDS
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(_autosave)
	add_child(_autosave_timer)

func _autosave() -> void:
	if _quitting or party.is_empty():
		return
	if get_tree().get_first_node_in_group('players') == null:
		return                          # on Character Select, nothing to save yet
	save_party()

func _process(delta: float) -> void:
	if party.is_empty():
		return
	if get_tree().get_first_node_in_group('players') == null:
		return                          # still on Character Select / menus
	_play_accum += delta

func _flush_playtime() -> void:
	var whole := int(_play_accum)
	if whole <= 0:
		return
	_play_accum -= whole
	for slot in party:
		var d: Dictionary = _loaded[slot]
		d['playtime_seconds'] = int(d.get('playtime_seconds', 0)) + whole

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_autosave()

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
	return save_slot(slot, new_character_data(char_name, class_data))


## A new character's save, not written anywhere (create_character writes it; REBOOT builds on it).
func new_character_data(char_name: String, class_data: ClassData) -> Dictionary:
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
		'attributes': class_data.get_attributes(),
		'equipment': {},
		'skills': [],
		'inventory': inventory,
		'playtime_seconds': 0,
		'created_at': int(Time.get_unix_time_from_system()),
	}
	return data


# ---------- WRITE ----------
func save_slot(slot: int, data: Dictionary) -> bool:
	data['saved_at'] = int(Time.get_unix_time_from_system())
	var tmp := _path(slot) + '.tmp'
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error('Could not write save: %s' % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, '\t'))
	f.close()

	# Write to a temp file first so a crash mid-save can't corrupt the real one
	if FileAccess.file_exists(_path(slot)):
		DirAccess.copy_absolute(_path(slot), _path(slot) + '.bak')
	if DirAccess.rename_absolute(tmp, _path(slot)) != OK:
		push_error('Could not finalize save for slot %d' % slot)
		return false
	return true


# ---------- READ ----------
func load_slot(slot: int) -> Dictionary:
	var data := _read_json(_path(slot))
	if data.is_empty():
		data = _read_json(_path(slot) + '.bak')
		if not data.is_empty():
			push_warning('Slot %d was damaged, loaded its backup' % slot)
	return _migrate(data) if not data.is_empty() else {}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


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
	if FileAccess.file_exists(_path(slot) + '.bak'):
		DirAccess.remove_absolute(_path(slot) + '.bak')


# ---------- MOVE ----------
## Swaps two slots' characters (Character Select's MOVE). An empty slot works too: the character
## simply moves there. A seated character (already in the party) can't move. True on success.
func swap_slots(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= MAX_SLOTS or b >= MAX_SLOTS:
		return false
	if a in party or b in party:
		return false
	var has_a := slot_exists(a)
	var has_b := slot_exists(b)
	if not has_a and not has_b:
		return false
	var tmp := SAVE_DIR + 'slot_swap.tmp'
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	# a -> tmp, b -> a, tmp -> b: every step is a rename, so nothing is ever copied half-way
	if has_a and DirAccess.rename_absolute(_path(a), tmp) != OK:
		push_error('Could not move slot %d' % a)
		return false
	if has_b and DirAccess.rename_absolute(_path(b), _path(a)) != OK:
		push_error('Could not move slot %d' % b)
		if has_a:
			DirAccess.rename_absolute(tmp, _path(a))      # put it back
		return false
	if has_a and DirAccess.rename_absolute(tmp, _path(b)) != OK:
		push_error('Could not finish moving slot %d (it is in %s)' % [a, tmp])
		return false
	for s in [a, b]:
		if FileAccess.file_exists(_path(s) + '.bak'):
			DirAccess.remove_absolute(_path(s) + '.bak')  
	return true


# ---------- SESSION / PARTY ----------
## Call once before opening Character Select (e.g. from the main menu's Play button).
## Do NOT call it inside Character Select's _ready(): that scene reloads after every
## character creation and would wipe the party.
func begin_session(count: int = 1) -> void:
	players_needed = clampi(count, 1, MAX_PLAYERS)
	party.clear()
	_loaded.clear()
	creating_slot = -1
	_play_accum = 0.0


func add_to_party(slot: int) -> bool:
	if slot in party or party.size() >= players_needed:
		return false
	var data := load_slot(slot)
	if data.is_empty():
		return false
	_play_accum = 0.0
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
	_flush_playtime()
	for slot in party:
		save_slot(slot, _loaded[slot])


func end_session() -> void:
	party.clear()
	_loaded.clear()
	creating_slot = -1
