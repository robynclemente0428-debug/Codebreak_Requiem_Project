extends Node

const SAVE_DIR := 'user://saves/'
const MAX_SLOTS := 10
const MAX_PLAYERS := 4
const SAVE_VERSION := 1
const GAME_SCENE := "res://scenes/map/main.tscn"
const LAST_TOWN_KEY := 'last_town'

var players_needed: int = 1
var party: Array[int] = []
var creating_slot: int = -1
var _loaded: Dictionary = {}
var _quit_dialog: ConfirmationDialog

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	
	get_tree().auto_accept_quit = false
	
	_quit_dialog = ConfirmationDialog.new()
	CyberDialog.style(_quit_dialog)
	_quit_dialog.theme = load("res://scenes/ui/theme/cyber_theme.tres")
	_quit_dialog.title = "Quit Game"
	_quit_dialog.dialog_text = "Save and quit?"
	_quit_dialog.ok_button_text = "Save & Quit"
	_quit_dialog.cancel_button_text = "Cancel"
	_quit_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_quit_dialog.confirmed.connect(_on_quit_confirmed)
	add_child(_quit_dialog)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()

func request_quit() -> void:
	if _quit_dialog.visible:
		return
	if party.is_empty():
		quit_game()
		return
	_quit_dialog.popup_centered()

func _on_quit_confirmed() -> void:
	quit_game()


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
	await get_tree().process_frame
	await get_tree().process_frame
	var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
	if am != null and am.current_area != null and is_instance_valid(am.current_area):
		am.current_area.free()
		am.current_area = null
	get_tree().quit()


func _path(slot: int) -> String:
	return SAVE_DIR + 'slot_%d.json' % slot


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_path(slot))


func create_character(slot: int, char_name: String, class_data: ClassData) -> bool:
	var inventory: Array = []
	if class_data.starting_weapon:
		inventory.append(class_data.starting_weapon.id)
	if class_data.starting_skill_gem:
		inventory.append(class_data.starting_skill_gem.id)
	inventory.append_array(["field_health_stim", "field_mana_stim"])

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
	return save_slot(slot, data)


func save_slot(slot: int, data: Dictionary) -> bool:
	var tmp := _path(slot) + '.tmp'
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error('Could not write save: %s' % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, '\t'))
	f.close()
	if DirAccess.rename_absolute(tmp, _path(slot)) != OK:
		push_error('Could not finalize save for slot %d' % slot)
		return false
	return true


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


func _migrate(data: Dictionary) -> Dictionary:
	return data


func delete_slot(slot: int) -> void:
	if slot in party:
		return
	if slot_exists(slot):
		DirAccess.remove_absolute(_path(slot))


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
	if has_a and DirAccess.rename_absolute(_path(a), tmp) != OK:
		push_error('Could not move slot %d' % a)
		return false
	if has_b and DirAccess.rename_absolute(_path(b), _path(a)) != OK:
		push_error('Could not move slot %d' % b)
		if has_a:
			DirAccess.rename_absolute(tmp, _path(a))
		return false
	if has_a and DirAccess.rename_absolute(tmp, _path(b)) != OK:
		push_error('Could not finish moving slot %d (it is in %s)' % [a, tmp])
		return false
	return true


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


func party_seat_of(slot: int) -> int:
	return party.find(slot)


func get_data(slot: int) -> Dictionary:
	return _loaded.get(slot, {})


func last_town() -> String:
	if party.is_empty():
		return ""
	var path := str(get_data(party[0]).get(LAST_TOWN_KEY, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return ""
	return path


func start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


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
