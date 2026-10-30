extends Control
## The settings scene opened from the main menu. Shows the SettingsPanel over the menu
## background and goes back to the main menu when it is closed.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const BACKGROUNDS := ["res://scenes/ui/reusables/background.tscn",
	"res://scenes/ui/reusables/circuit_background.tscn"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for path in BACKGROUNDS:
		if ResourceLoader.exists(path):
			add_child((load(path) as PackedScene).instantiate())
	var panel := SettingsPanel.new()
	add_child(panel)
	panel.closed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU))
	panel.open()
