extends Control

@onready var play_btn: Button = $VBoxContainer/ButtonCenter/ButtonBox/PlayButton
@onready var settings_btn: Button = $VBoxContainer/ButtonCenter/ButtonBox/SettingsButton
@onready var credits_btn: Button = $VBoxContainer/ButtonCenter/ButtonBox/CreditsButton
@onready var exit_btn: Button = $VBoxContainer/ButtonCenter/ButtonBox/ExitButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	play_btn.pressed.connect(_on_play)
	settings_btn.pressed.connect(_on_settings)
	credits_btn.pressed.connect(_on_credits)
	exit_btn.pressed.connect(_on_exit)
	
	# Co-op: a LOBBY button under PLAY (a copy of it, so it looks and behaves the same)
	Coop.leave()                                    # back from a session: make sure it's closed
	if Coop.picking:
		SaveManager.end_session()                   # backed out of the lobby: the character is unseated
	Coop.picking = false
	var lobby_btn := play_btn.duplicate(0) as Button    # 0: without PLAY's own signal connections
	lobby_btn.name = "LobbyButton"
	lobby_btn.text = "Lobby"
	play_btn.add_sibling(lobby_btn)
	lobby_btn.pressed.connect(_on_lobby)
	if Coop.notice != "":                           # why the last session ended
		var note := Label.new()
		note.text = Coop.notice
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 24)
		note.add_theme_color_override("font_color", Color(1.0, 0.78, 0.4))
		exit_btn.add_sibling(note)
		Coop.notice = ""

	for b in [play_btn, lobby_btn, settings_btn, credits_btn, exit_btn]:
		b.pivot_offset = b.size / 2.0
		b.mouse_entered.connect(_hover.bind(b, true))
		b.mouse_exited.connect(_hover.bind(b, false))
		b.focus_entered.connect(_hover.bind(b, true))
		b.focus_exited.connect(_hover.bind(b, false))
	print("window: ", get_window().size, "  layout space: ", get_viewport().get_visible_rect().size)

func _hover(btn: Button, entered: bool) -> void:
	var t := create_tween()
	t.tween_property(btn, "scale", Vector2.ONE * (1.05 if entered else 1.0), 0.12)

func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/character_slots/character_select.tscn")


## Co-op: pick your character first (the same Character Select), then on to the lobby.
func _on_lobby() -> void:
	SaveManager.begin_session(1)
	Coop.picking = true
	get_tree().change_scene_to_file("res://scenes/ui/character_slots/character_select.tscn")

func _on_settings() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/settings/settings.tscn")

func _on_credits() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/credits/credits.tscn")

func _on_exit() -> void:
	await get_tree().create_timer(0.3).timeout      # let the exit click play before closing
	SaveManager.quit_game()
