extends Control

const CLASS_DIR := "res://data/classes/"
const SlotButtonScene := preload("res://scenes/ui/character_slots/slot_button.tscn")
# Adjust these two paths to wherever your scenes actually are
const CLASS_SELECT_SCENE := "res://scenes/ui/class_select/class_select.tscn"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var slots_box: HBoxContainer = %SlotsBox
@onready var scroll: ScrollContainer = %Scroll
@onready var back_button: TextureButton = %BackButton
@onready var delete_dialog: ConfirmationDialog = %DeleteDialog

var _pending_delete := -1


func _ready() -> void:
	CyberDialog.style(delete_dialog)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	back_button.pressed.connect(_on_back)
	delete_dialog.confirmed.connect(_confirm_delete)
	
	# Return to the slot you just created a character in (or slot 0)
	var focus_index := maxi(SaveManager.creating_slot, 0)
	SaveManager.creating_slot = -1      # consumed
	_build_slots()
	_focus_slot(focus_index)
	_prefetch_class_select()


func _build_slots() -> void:
	for child in slots_box.get_children():
		slots_box.remove_child(child)   # remove now so child indices stay correct
		child.queue_free()

	for i in SaveManager.MAX_SLOTS:
		var card := SlotButtonScene.instantiate()
		slots_box.add_child(card)
		card.setup(i, SaveManager.load_slot(i))
		card.slot_chosen.connect(_on_slot_chosen)
		card.delete_requested.connect(_on_delete_requested)


func _focus_slot(index: int) -> void:
	await get_tree().process_frame      # wait for the layout to settle
	if index < 0 or index >= slots_box.get_child_count():
		return
	var card := slots_box.get_child(index) as Control
	card.grab_focus()
	scroll.ensure_control_visible(card)


func _on_slot_chosen(index: int) -> void:
	if SaveManager.slot_exists(index):
		if SaveManager.add_to_party(index) and SaveManager.party_full():
			SaveManager.start_game()                    # existing character: play
	else:
		SaveManager.creating_slot = index                   #empty slot
		var packed := ResourceLoader.load_threaded_get(CLASS_SELECT_SCENE) as PackedScene
		get_tree().change_scene_to_packed(packed)


func _on_delete_requested(index: int) -> void:
	_pending_delete = index
	var data := SaveManager.load_slot(index)
	delete_dialog.dialog_text = "Delete %s permanently?" % data.get("name", "this character")
	delete_dialog.popup_centered()


func _confirm_delete() -> void:
	var keep := scroll.scroll_horizontal            # remember scroll position
	SaveManager.delete_slot(_pending_delete)
	_build_slots()
	await get_tree().process_frame
	scroll.scroll_horizontal = keep
	_focus_slot(_pending_delete)

func _on_back() -> void:
	SaveManager.end_session()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _prefetch_class_select() -> void:
	# Loads on background threads; nothing blocks
	ResourceLoader.load_threaded_request(CLASS_SELECT_SCENE, "", true)
	for file in DirAccess.get_files_at(CLASS_DIR):
		var clean := file.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			ResourceLoader.load_threaded_request(CLASS_DIR + clean, "", true)
