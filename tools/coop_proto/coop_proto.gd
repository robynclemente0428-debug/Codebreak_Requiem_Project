extends Node3D
## LAN co-op prototype: the real Player and a real enemy, shared by up to 4 machines.
## Run this scene from the editor (F6). Nothing here reads or writes a save slot.
##
## To try it on one PC: Debug > Customize Run Instances > 2 instances, run this scene, press HOST
## in one window and JOIN in the other: the host shows up in the list. On two PCs on the same
## router it's the same (Windows asks each PC to allow Godot through the firewall once); if the
## list stays empty, type the address the host's screen shows.
##
## Who decides what (host-authoritative):
##   the host       the enemy: its AI, where it is, its health, when it attacks, when it respawns
##   each player    their own character: where it is, its health, the skills it casts
## Every machine builds every body. A body this machine doesn't own is a remote copy:
##   a remote player   Player.is_remote: no input or camera; it follows the owner's position
##   the enemy, on a   its AI is halted; it follows the host's position and state
##   client
## Damage always goes to the owner (HealthComponent.remote_damage), and the owner sends the
## health back to everyone (HealthComponent.apply_remote):
##   a client hits the enemy      -> host applies it     -> everyone sees the new health
##   the enemy hits a client      -> that client applies -> everyone sees the new health
## A skill cast is replayed on the other machines for show (Player.remote_cast): animation,
## projectiles and effects, no damage.
##
## Every message goes through this one node (same path on every machine), so nothing depends on
## the players' or the enemy's node paths matching.
##
## Not here on purpose: quests, loot, towns, saving, the HUD, enemy skills and modifiers.

const PORT := 24545
const MAX_PLAYERS := 4
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_DEF := "res://data/enemies/loop_hound.tres"
const CLASSES: Array[String] = ["gladiator", "paladin", "raider", "rogue", "assassin", "enchanter"]

const ARENA_SIZE := 36.0                 # metres, a square
const SPAWNS: Array[Vector3] = [Vector3(-3, 0, 8), Vector3(3, 0, 8), Vector3(-6, 0, 10), Vector3(6, 0, 10)]
const ENEMY_SPAWN := Vector3(0, 0, -8)
## Extra health on the enemy (3.0 = +300%), so a fight lasts long enough to watch on both screens.
const ENEMY_HEALTH_BONUS := 3.0
const ENEMY_RESPAWN_SEC := 4.0
const PLAYER_RESPAWN_SEC := 3.0
const SEND_EVERY := 0.05                 # seconds between position updates (20 a second)
const SNAP_DISTANCE := 4.0               # a copy further than this from the truth jumps there

## Finding hosts on the same network (same router), with no address to type:
##   a host    broadcasts a small "I'm here" packet on DISCOVERY_PORT every ANNOUNCE_EVERY seconds
##   the JOIN  listens on DISCOVERY_PORT and lists every host it hears; one that goes quiet for
##   screen    HOST_TIMEOUT seconds drops off the list
## Broadcasts stay inside one network: guest Wi-Fi that isolates devices, or a blocked firewall
## prompt, hides hosts, so "join by address" stays as the fallback.
const DISCOVERY_PORT := 24546
const GAME_TAG := "cbr_coop_proto"      # packets from anything else on that port are ignored
const ANNOUNCE_EVERY := 1.0
const HOST_TIMEOUT := 3.5

static var _notice := ""                 # shown on the lobby after coming back from a session

var _lobby: Control
var _class_pick: OptionButton
var _address: LineEdit
var _status: Label
var _choice_box: Control                 # step 1: HOST or JOIN
var _join_box: Control                   # step 2 (JOIN): the hosts on this network
var _host_list: VBoxContainer
var _back_btn: Button
var _hud: Label

var _announcer: PacketPeerUDP            # host: sends the "I'm here" packets
var _listener: PacketPeerUDP             # join screen: hears them
var _announce_timer := 0.0
var _host_id := ""                       # tells one host's packets from another's
var _found: Dictionary = {}              # host id -> {name, address, port, players, max, seen}
var _list_shown := ""                    # what the list shows now (rebuilt only when it changes)
var _connecting := false
var _joined_address := ""

var _in_arena := false
var _class_id := "gladiator"
var _roster: Dictionary = {}             # peer id -> class id (the host's copy is the truth)
var _players: Dictionary = {}            # peer id -> Player
var _player_goal: Dictionary = {}        # peer id -> {pos, rot, vel, walking} for remote copies
var _enemies: Dictionary = {}            # enemy id -> EnemyBase
var _enemy_goal: Dictionary = {}         # enemy id -> {pos, rot} on clients
var _next_enemy := 1
var _send_timer := 0.0
var _hud_timer := 0.0
var _players_root: Node3D
var _enemies_root: Node3D


func _ready() -> void:
	_build_lobby()
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_leave.bind("The host closed the session."))
	multiplayer.peer_disconnected.connect(_on_peer_left)


func _exit_tree() -> void:
	multiplayer.multiplayer_peer = null
	_stop_listening()
	if _announcer != null:
		_announcer.close()


# ---------- LOBBY ----------
const ACCENT := Color("#00E5FF")                # the menus' cyan (CyberDialog, Character Select)
const TEXT_SOFT := Color(0.66, 0.84, 0.9)       # descriptions and hints: calmer than the accent
const TEXT_WARN := Color(1.0, 0.78, 0.4)        # the status line (connecting, couldn't connect)
const PANEL_SIZE := Vector2(900, 640)           # fixed, so the panel doesn't jump between steps

var _searching: Label                           # "Searching..." beside the list's heading


func _build_lobby() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_lobby = Control.new()
	_lobby.theme = load("res://scenes/ui/theme/cyber_theme.tres")
	_lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_lobby)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.035, 0.055)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby.add_child(backdrop)
	var circuit := CircuitBackgroundx.new()         # the same traces as the other menus, fainter
	circuit.opacity = 0.14
	circuit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby.add_child(circuit)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	var panel_box := _box(Color(0.03, 0.085, 0.12, 0.96), Color(ACCENT, 0.75), 2)
	panel_box.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", panel_box)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	# Header
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	box.add_child(head)
	head.add_child(_text("CO-OP LOBBY", 44, ACCENT))
	head.add_child(_text("Play together on the same Wi-Fi or network.   PROTOTYPE", 20, TEXT_SOFT))
	var rule := ColorRect.new()
	rule.color = Color(ACCENT, 0.3)
	rule.custom_minimum_size.y = 2
	box.add_child(rule)

	# Step 1: who you play, then host or join
	var choice := VBoxContainer.new()
	choice.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choice.add_theme_constant_override("separation", 14)
	box.add_child(choice)
	_choice_box = choice
	choice.add_child(_text("YOUR CLASS", 20, TEXT_SOFT))
	_class_pick = OptionButton.new()
	for id in CLASSES:
		_class_pick.add_item(id.capitalize())
	_style_button(_class_pick, 26)
	_class_pick.get_popup().add_theme_font_size_override("font_size", 24)
	choice.add_child(_class_pick)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	choice.add_child(gap)
	choice.add_child(_text("WHAT WOULD YOU LIKE TO DO?", 20, TEXT_SOFT))
	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 20)
	choice.add_child(cards)
	cards.add_child(_card("HOST A GAME",
			"Open a session on this PC. Players on your network will see it in their list.", _on_host))
	cards.add_child(_card("JOIN A GAME",
			"Look for a session that someone on your network is hosting.", _show_join.bind(true)))

	# Step 2 (JOIN): every host heard on this network, and "by address" as the fallback
	var join := VBoxContainer.new()
	join.size_flags_vertical = Control.SIZE_EXPAND_FILL
	join.add_theme_constant_override("separation", 12)
	join.visible = false
	box.add_child(join)
	_join_box = join
	var list_head := HBoxContainer.new()
	join.add_child(list_head)
	var heading := _text("GAMES ON THIS NETWORK", 24, ACCENT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_head.add_child(heading)
	_searching = _text("", 20, TEXT_SOFT)
	_searching.custom_minimum_size.x = 150       # room for the dots, so the text doesn't shift
	list_head.add_child(_searching)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	join.add_child(scroll)
	_host_list = VBoxContainer.new()
	_host_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_host_list)
	join.add_child(_text("Can't see the game? Type the address shown on the host's screen.", 18, TEXT_SOFT))
	var by_address := HBoxContainer.new()
	by_address.add_theme_constant_override("separation", 12)
	join.add_child(by_address)
	_address = LineEdit.new()
	_address.placeholder_text = "e.g. 192.168.1.8"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.add_theme_font_size_override("font_size", 24)
	_address.text_submitted.connect(func(_t: String) -> void: _join_by_address())
	by_address.add_child(_address)
	var address_btn := Button.new()
	address_btn.text = "CONNECT"
	address_btn.custom_minimum_size.x = 180
	_style_button(address_btn, 24)
	address_btn.pressed.connect(_join_by_address)
	by_address.add_child(address_btn)

	# Footer: BACK (on the JOIN step) and what's going on
	var foot := HBoxContainer.new()
	foot.custom_minimum_size.y = 52
	foot.add_theme_constant_override("separation", 20)
	box.add_child(foot)
	_back_btn = Button.new()
	_back_btn.text = "‹  BACK"
	_back_btn.custom_minimum_size.x = 160
	_back_btn.visible = false
	_style_button(_back_btn, 24)
	_back_btn.pressed.connect(_show_join.bind(false))
	foot.add_child(_back_btn)
	_status = _text(_notice, 20, TEXT_WARN)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice = ""
	foot.add_child(_status)

	_hud = _text("", 22, ACCENT)
	_hud.theme = _lobby.theme
	_hud.position = Vector2(16, 40)
	_hud.add_theme_constant_override("outline_size", 6)
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud.visible = false
	layer.add_child(_hud)


func _join_by_address() -> void:
	if _address.text.strip_edges() != "":
		_join(_address.text.strip_edges(), PORT)


func _text(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	return sb


## The menus' button look (Character Select's values), at a readable size.
func _style_button(b: Button, font_size: int) -> void:
	b.add_theme_stylebox_override("normal", _box(Color(0.02, 0.07, 0.1, 0.7), Color(ACCENT, 0.6), 2))
	b.add_theme_stylebox_override("hover", _box(Color(ACCENT, 0.18), ACCENT, 2))
	b.add_theme_stylebox_override("pressed", _box(Color(ACCENT, 0.32), ACCENT, 2))
	b.add_theme_stylebox_override("focus", _box(Color(ACCENT, 0.1), ACCENT, 2))
	b.add_theme_stylebox_override("disabled", _box(Color(0.02, 0.07, 0.1, 0.4), Color(ACCENT, 0.2), 2))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_disabled_color", Color(ACCENT, 0.3))


## A big button with a title and a line saying what it does.
func _card(title: String, about: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 200
	_style_button(b, 24)
	b.pressed.connect(on_press)
	b.add_child(_inside(b, [_text(title, 34, ACCENT), _wrapped(about)], 24))
	return b


func _wrapped(text: String) -> Label:
	var label := _text(text, 20, TEXT_SOFT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Lays `parts` out inside a button (a Button isn't a container), without taking its clicks.
func _inside(_button: Button, parts: Array, margin: int) -> Control:
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	for part: Control in parts:
		col.add_child(part)
	return pad


func _on_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		_status.text = "Could not host on port %d (%s). Is another host already running on this PC?" \
				% [PORT, error_string(err)]
		return
	multiplayer.multiplayer_peer = peer
	_class_id = CLASSES[_class_pick.selected]
	_enter_arena()
	_roster[1] = _class_id
	_apply_roster()
	_host_spawn_enemy()
	_announcer = PacketPeerUDP.new()               # from now on the JOIN screens nearby list us
	_announcer.set_broadcast_enabled(true)
	_host_id = "%d-%d" % [randi(), Time.get_ticks_usec()]


## The JOIN step (true) or back to HOST / JOIN (false). The list only listens while it's showing.
func _show_join(on: bool) -> void:
	if _connecting:
		return
	_choice_box.visible = not on
	_join_box.visible = on
	_back_btn.visible = on
	_status.text = ""
	_stop_listening()
	if on:
		_listener = PacketPeerUDP.new()
		var err := _listener.bind(DISCOVERY_PORT, "0.0.0.0")
		if err != OK:                              # e.g. a second JOIN screen on this same PC
			_listener = null
			_status.text = "Can't search from this window. Type the host's address instead."
		_refresh_host_list()


func _stop_listening() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	_found.clear()
	_list_shown = ""


func _join(address: String, port: int) -> void:
	if _connecting:
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_status.text = "Could not start connecting (%s)." % error_string(err)
		return
	multiplayer.multiplayer_peer = peer
	_class_id = CLASSES[_class_pick.selected]
	_joined_address = address
	_connecting = true
	_status.text = "Connecting to %s ..." % address


func _on_connected() -> void:
	_connecting = false
	_stop_listening()
	_enter_arena()
	_register.rpc_id(1, _class_id)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	_connecting = false
	_status.text = "Could not reach a host at %s." % _joined_address


# ---------- FINDING HOSTS ON THE NETWORK ----------
func _tick_discovery(delta: float) -> void:
	if _announcer != null:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce_timer = ANNOUNCE_EVERY
			_announce()
	if _listener == null:
		_searching.text = ""
		return
	var now := Time.get_ticks_msec() / 1000.0
	_searching.text = "Searching" + ".".repeat(int(now * 2.0) % 4)
	while _listener.get_available_packet_count() > 0:
		var bytes := _listener.get_packet()
		var from := _listener.get_packet_ip()
		var info = JSON.parse_string(bytes.get_string_from_utf8())
		if not info is Dictionary or str(info.get("game", "")) != GAME_TAG:
			continue
		var id := str(info.get("id", ""))
		# A host on this same PC is heard on 127.0.0.1 and on its LAN address: keep the LAN one
		if from.begins_with("127.") and _found.has(id):
			from = _found[id].address
		_found[id] = {
			"name": str(info.get("name", "Host")).left(32), "address": from,
			"class": str(info.get("class", "")).left(24),
			"port": int(info.get("port", PORT)), "players": int(info.get("players", 1)),
			"max": int(info.get("max", MAX_PLAYERS)), "seen": now}
	for id: String in _found.keys():
		if now - _found[id].seen > HOST_TIMEOUT:
			_found.erase(id)
	_refresh_host_list()


## One packet to everyone on the network: the broadcast address, each adapter's own x.y.z.255 (a
## PC with several adapters only sends the plain broadcast out of one), and this PC itself.
func _announce() -> void:
	var name_ := OS.get_environment("COMPUTERNAME")
	if name_ == "":
		name_ = OS.get_environment("HOSTNAME")
	var packet := JSON.stringify({
		"game": GAME_TAG, "id": _host_id, "port": PORT, "max": MAX_PLAYERS, "players": _roster.size(),
		"name": name_ if name_ != "" else "Host", "class": _class_id.capitalize(),
	}).to_utf8_buffer()
	var targets := PackedStringArray(["255.255.255.255", "127.0.0.1"])
	for a in _lan_addresses():
		targets.append(a.substr(0, a.rfind(".") + 1) + "255")
	for t in targets:
		_announcer.set_dest_address(t, DISCOVERY_PORT)
		_announcer.put_packet(packet)


func _refresh_host_list() -> void:
	var ids := _found.keys()
	ids.sort()
	var shown := ""
	for id: String in ids:
		shown += "%s|%s|%d;" % [id, _found[id].address, _found[id].players]
	if shown == "":
		shown = "none"
	if shown == _list_shown:
		return                                     # unchanged: leave the buttons alone
	_list_shown = shown
	for child in _host_list.get_children():
		child.queue_free()
	if ids.is_empty():
		var none := _wrapped("No games found yet.\nAsk the host to choose HOST A GAME. Both PCs need to be on the same Wi-Fi or router."
				if _listener != null else "Searching isn't available in this window.")
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		none.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_host_list.add_child(none)
		return
	for id: String in ids:
		var h: Dictionary = _found[id]
		var full: bool = h.players >= h.max
		var row := Button.new()
		row.custom_minimum_size.y = 84
		row.disabled = full
		_style_button(row, 24)
		row.pressed.connect(_join.bind(h.address, h.port))
		# Left: who is hosting. Right: what a click does.
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var who := VBoxContainer.new()
		who.mouse_filter = Control.MOUSE_FILTER_IGNORE
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.add_theme_constant_override("separation", 0)
		who.add_child(_text("%s's game" % h.name, 26, Color(ACCENT, 0.4) if full else ACCENT))
		var details := PackedStringArray([h.get("class", ""), "%d of %d players" % [h.players, h.max], h.address])
		if details[0] == "":
			details.remove_at(0)
		who.add_child(_text("   ·   ".join(details), 18, TEXT_SOFT))
		line.add_child(who)
		var action := _text("FULL" if full else "JOIN  ›", 24, Color(ACCENT, 0.4) if full else ACCENT)
		action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action.size_flags_vertical = Control.SIZE_EXPAND_FILL
		line.add_child(action)
		row.add_child(_inside(row, [line], 16))
		_host_list.add_child(row)


## Back to the lobby (ESC, or the host went away).
func _leave(why := "") -> void:
	_notice = why
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _in_arena and event.is_action_pressed("ui_cancel"):
		_leave()


# ---------- THE ARENA ----------
func _enter_arena() -> void:
	_in_arena = true
	_lobby.visible = false
	_hud.visible = true

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.8)
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)

	# The floor, with a one-polygon navmesh on it for the enemy
	var half := ARENA_SIZE * 0.5
	var region := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.vertices = PackedVector3Array([
		Vector3(-half, 0, -half), Vector3(-half, 0, half), Vector3(half, 0, half), Vector3(half, 0, -half)])
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = nm
	add_child(region)
	_add_box(Vector3(0, -0.5, 0), Vector3(ARENA_SIZE, 1, ARENA_SIZE), Color(0.1, 0.13, 0.18))
	for side: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var along := Vector3(absf(side.z), 0, absf(side.x))          # the wall runs across its side
		_add_box(side * half + Vector3.UP, along * ARENA_SIZE + Vector3(1, 2, 1) - along, Color(0.16, 0.3, 0.42))

	_players_root = Node3D.new()
	_players_root.name = "Players"
	add_child(_players_root)
	_enemies_root = Node3D.new()
	_enemies_root.name = "Enemies"
	add_child(_enemies_root)


func _add_box(at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()                 # layer 1: what players, enemies and sight lines hit
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box_mesh.material = mat
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)


# ---------- WHO IS HERE ----------
## A client that just connected tells the host which class it plays.
@rpc("any_peer", "call_remote", "reliable")
func _register(class_id: String) -> void:
	if not multiplayer.is_server() or not class_id in CLASSES:
		return
	var id := multiplayer.get_remote_sender_id()
	_roster[id] = class_id
	_set_roster.rpc(_roster)
	_apply_roster()
	for enemy_id: int in _enemies:                 # the fight as it stands now
		var e: EnemyBase = _enemies[enemy_id]
		_spawn_enemy.rpc_id(id, enemy_id, e.global_position, e.health.current_health)


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server() and _roster.erase(id):
		_set_roster.rpc(_roster)
		_apply_roster()


@rpc("authority", "call_remote", "reliable")
func _set_roster(roster: Dictionary) -> void:
	_roster = roster
	_apply_roster()


## Builds a character for everyone in the roster who has none yet, and removes the ones who left.
func _apply_roster() -> void:
	for id: int in _players.keys():
		if not _roster.has(id):
			_players[id].queue_free()
			_players.erase(id)
			_player_goal.erase(id)
	var seats := _roster.keys()
	seats.sort()
	var me := multiplayer.get_unique_id()
	for id: int in seats:
		if not _players.has(id):
			_spawn_player(id, str(_roster[id]), SPAWNS[seats.find(id) % SPAWNS.size()], id != me)
	var mine := _players.get(me) as Player
	if mine != null:
		mine.camera_rig.camera.make_current()      # a copy's camera may have taken over
		_player_health.rpc(mine.health.current_health)   # newcomers learn how hurt we are


func _spawn_player(id: int, class_id: String, at: Vector3, remote: bool) -> void:
	var p := PLAYER_SCENE.instantiate() as Player
	p.name = "P%d" % id
	p.is_remote = remote
	p.coop_data = _character(class_id)
	_players_root.add_child(p)
	p.global_position = at                         # after add_child: the camera rig measures its offset there
	_players[id] = p
	if remote:
		var rig: Node3D = p.camera_rig             # no camera, hover plate or pickups for a copy
		rig.process_mode = Node.PROCESS_MODE_DISABLED
		rig.visible = false
		rig.camera.current = false
		for child in ["EnemyHover", "PickupController"]:
			p.get_node(child).process_mode = Node.PROCESS_MODE_DISABLED
		p.health.set_process(false)                # no regen here: the owner sends the health
		p.health.remote_damage = func(amount: float, ignore_armour: bool) -> void:
			_hit_player.rpc_id(id, amount, ignore_armour)
		_player_goal[id] = {"pos": at, "rot": 0.0, "vel": Vector3.ZERO, "walking": false}
	else:
		p.health.health_changed.connect(func(current: float, _max: float) -> void:
			_player_health.rpc(current))
		p.health.died.connect(_on_own_death.bind(p, at))
		p.skill_cast.connect(func(action: StringName) -> void:
			_player_cast.rpc(action, p.global_rotation.y, p.get_aim_point()))


## A level-1 character of this class with its starting weapon in hand and its starting skill on
## the attack key, in save-file form (Player reads it through coop_data).
static func _character(class_id: String) -> Dictionary:
	var c := load("res://data/classes/%s.tres" % class_id) as ClassData
	var data := {"class_id": class_id, "equipment": {}, "skills": [], "inventory": []}
	if c != null and c.starting_weapon != null:
		data["equipment"]["weapon"] = c.starting_weapon.id
	if c != null and c.starting_skill_gem != null:
		data["skills"] = [{"gem": c.starting_skill_gem.id, "supports": [], "action": "attack"}]
	return data


func _on_own_death(p: Player, at: Vector3) -> void:
	await get_tree().create_timer(PLAYER_RESPAWN_SEC).timeout
	if is_instance_valid(p) and p.health.current_health <= 0.0:
		p.global_position = at
		p.revive()                                 # health_changed tells the others


# ---------- PLAYERS OVER THE NETWORK ----------
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _player_state(pos: Vector3, rot: float, vel: Vector3, walking: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _player_goal.has(id):
		_player_goal[id] = {"pos": pos, "rot": rot, "vel": vel, "walking": walking}


@rpc("any_peer", "call_remote", "reliable")
func _player_health(current: float) -> void:
	var p := _players.get(multiplayer.get_remote_sender_id()) as Player
	if p == null or not p.is_remote:
		return
	if p.health.current_health <= 0.0 and current > 0.0:
		p.revive()                                 # stands the copy back up (its owner respawned)
	p.health.apply_remote(current)


@rpc("any_peer", "call_remote", "reliable")
func _player_cast(action: StringName, facing: float, aim_point: Vector3) -> void:
	var p := _players.get(multiplayer.get_remote_sender_id()) as Player
	if p != null:
		p.remote_cast(action, facing, aim_point)


## Something on another machine hurt this machine's player (the host's enemy).
@rpc("any_peer", "call_remote", "reliable")
func _hit_player(amount: float, ignore_armour: bool) -> void:
	var mine := _players.get(multiplayer.get_unique_id()) as Player
	if mine != null:
		mine.health.take_damage(amount, ignore_armour)


# ---------- THE ENEMY ----------
func _host_spawn_enemy() -> void:
	if not _in_arena or not multiplayer.is_server():
		return
	var id := _next_enemy
	_next_enemy += 1
	_spawn_enemy.rpc(id, ENEMY_SPAWN, -1.0)
	_spawn_enemy(id, ENEMY_SPAWN, -1.0)


## health < 0 = full (a fresh spawn); otherwise what it has left (for someone joining mid-fight).
@rpc("authority", "call_remote", "reliable")
func _spawn_enemy(id: int, at: Vector3, health: float) -> void:
	if not _in_arena or _enemies.has(id):
		return
	var def := load(ENEMY_DEF) as EnemyDefinition
	# No rolled modifiers: every machine must build the same enemy
	var e := EnemySpawner.spawn_enemy(def, "normal", _enemies_root, at, 1, []) as EnemyBase
	EnemySpawner.empower(e, ENEMY_HEALTH_BONUS, 0.0, 0.0, "coop_proto")
	_enemies[id] = e
	e.health.died.connect(func() -> void:
		_enemies.erase(id)
		_enemy_goal.erase(id))
	if multiplayer.is_server():
		e.health.health_changed.connect(func(current: float, _max: float) -> void:
			_enemy_health.rpc(id, current))
		e.ai.attack_requested.connect(func(_target: Node3D) -> void:
			_enemy_attack.rpc(id))
		e.health.died.connect(func() -> void:
			get_tree().create_timer(ENEMY_RESPAWN_SEC).timeout.connect(_host_spawn_enemy))
	else:
		e.ai.halt()                                # the host thinks for it
		e.health.set_process(false)
		e.health.remote_damage = func(amount: float, ignore_armour: bool) -> void:
			_hit_enemy.rpc_id(1, id, amount, ignore_armour)
		_enemy_goal[id] = {"pos": at, "rot": 0.0}
		if health >= 0.0:
			e.health.apply_remote(health)


## A client's skill hit the enemy: the host applies it (and its health goes back to everyone).
@rpc("any_peer", "call_remote", "reliable")
func _hit_enemy(id: int, amount: float, ignore_armour: bool) -> void:
	var e := _enemies.get(id) as EnemyBase
	if multiplayer.is_server() and e != null:
		e.health.take_damage(amount, ignore_armour)


@rpc("authority", "call_remote", "reliable")
func _enemy_health(id: int, current: float) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e != null:
		e.health.apply_remote(current)             # at 0 it dies here too (EnemyBase._on_died)


@rpc("authority", "call_remote", "unreliable_ordered")
func _enemy_state(id: int, pos: Vector3, rot: float, state: int) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e == null:
		return
	_enemy_goal[id] = {"pos": pos, "rot": rot}
	e.ai.state = state as AIComponent.State        # the model animates off the AI's state


## The swing, for show: the host's enemy deals the damage.
@rpc("authority", "call_remote", "reliable")
func _enemy_attack(id: int) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e == null or e.model == null:
		return
	var cooldown := 1.0 / maxf(e.stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 0.1)
	SoundManager.play_skill("attack", e, e.model.play_attack(cooldown))


# ---------- EVERY FRAME ----------
func _physics_process(delta: float) -> void:
	if not _in_arena:
		return
	var ease_in := 1.0 - exp(-delta * 15.0)

	# Remote players ease to where their owner says they are
	for id: int in _player_goal:
		var p := _players.get(id) as Player
		var goal: Dictionary = _player_goal[id]
		if p == null or p.health.current_health <= 0.0:
			continue
		if p.global_position.distance_to(goal.pos) > SNAP_DISTANCE:
			p.global_position = goal.pos
		else:
			p.global_position = p.global_position.lerp(goal.pos, ease_in)
		p.global_rotation.y = lerp_angle(p.global_rotation.y, goal.rot, ease_in)
		p.velocity = goal.vel                      # the model picks its jog direction from this
		if p.walking != goal.walking:
			p.walking = goal.walking
			p.walking_changed.emit(p.walking)

	# On a client the enemy walks to where the host says it is (walks, so its run clip plays)
	for id: int in _enemy_goal:
		var e := _enemies.get(id) as EnemyBase
		var goal: Dictionary = _enemy_goal[id]
		if e == null or e.health.current_health <= 0.0:
			continue
		var gap: Vector3 = goal.pos - e.global_position
		if gap.length() > SNAP_DISTANCE:
			e.global_position = goal.pos
		else:
			e.velocity = gap * 12.0
			e.move_and_slide()
		e.global_rotation.y = lerp_angle(e.global_rotation.y, goal.rot, ease_in)

	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = SEND_EVERY
		var mine := _players.get(multiplayer.get_unique_id()) as Player
		if mine != null:
			_player_state.rpc(mine.global_position, mine.global_rotation.y, mine.velocity, mine.walking)
		if multiplayer.is_server():
			for id: int in _enemies:
				var e: EnemyBase = _enemies[id]
				_enemy_state.rpc(id, e.global_position, e.global_rotation.y, e.ai.state)


func _process(delta: float) -> void:
	_tick_discovery(delta)
	if not _in_arena:
		return
	_hud_timer -= delta
	if _hud_timer > 0.0:
		return
	_hud_timer = 0.2
	var lines: Array[String] = []
	if multiplayer.is_server():
		lines.append("HOSTING on %s  port %d" % [", ".join(_lan_addresses()), PORT])
	else:
		lines.append("JOINED %s" % _joined_address)
	var me := multiplayer.get_unique_id()
	var seats := _players.keys()
	seats.sort()
	for id: int in seats:
		var p: Player = _players[id]
		lines.append("%s %s  %d / %d" % [
			"YOU  " if id == me else "ALLY ", str(_roster.get(id, "")).capitalize(),
			ceili(maxf(p.health.current_health, 0.0)), ceili(p.stats.get_stat(StatTypes.Stat.MAX_HEALTH))])
	for id: int in _enemies:
		var e: EnemyBase = _enemies[id]
		lines.append("%s  %d / %d" % [e.display_name.to_upper(),
			ceili(maxf(e.health.current_health, 0.0)), ceili(e.stats.get_stat(StatTypes.Stat.MAX_HEALTH))])
	if _enemies.is_empty():
		lines.append("(the next enemy is on its way)")
	lines.append("ESC: leave")
	_hud.text = "\n".join(lines)


func _lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out
