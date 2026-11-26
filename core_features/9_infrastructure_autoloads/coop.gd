extends Node

signal player_cast(player: Node3D, action: StringName)
signal roster_changed
signal hosts_changed
signal session_closed(reason: String)
signal join_failed(reason: String)

const PORT := 24547
const DISCOVERY_PORT := 24548
const GAME_TAG := "codebreak_requiem_coop"
const PROTOCOL := 12
const MAX_PLAYERS := 4
const ANNOUNCE_EVERY := 1.0
const HOST_TIMEOUT := 3.5
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const LOADOUT_KEYS: Array[String] = ["class_id", "equipment", "skills", "script_set", "script_set_names",
		"script_routines", "kernel"]

const SEND_PLAYER_EVERY := 0.05
const SEND_ENEMIES_EVERY := 0.066
const ENEMIES_PER_PACKET := 50
const SNAP_DISTANCE := 5.0
const UNMATCHED_GRACE := 2.5
const MATCH_RADIUS := 1.0
const MAX_DAMAGE := 10000000.0
const NET_ID := &"coop_id"
const NET_ENTRY := &"coop_entry"
const NET_BOOST := &"coop_boost"
const LOOT_ID := &"coop_loot"
const PLAYER_COLOURS: Array[Color] = [Color(0.0, 0.90, 1.0), Color(1.0, 0.82, 0.30),
		Color(0.45, 1.0, 0.55), Color(1.0, 0.50, 0.85)]

enum Hit { NONE, PLAYER, ENEMY }
var hit_source := Hit.NONE
var damage_by := 0
var hit_facts: HitFacts

var active := false
var in_game := false
var picking := false
var notice := ""
var roster: Dictionary = {}
var start_town := ""
var travelling := false
var visiting := false
var _told_visiting := false
var answering := false

var found: Dictionary = {}
var _announcer: PacketPeerUDP
var _listener: PacketPeerUDP
var _announce_timer := 0.0
var _host_id := ""

var _am: AreaManager
var _players: Dictionary = {}
var _player_goal: Dictionary = {}
var _answering: Dictionary = {}
var _enemies: Dictionary = {}
var _enemy_goal: Dictionary = {}
var _enemy_sent: Dictionary = {}
var _unmatched: Array = []
var _next_enemy := 1
var _area_path := ""
var _area_live := false
var _list_done := false
var _waiting: Dictionary = {}
var _adopting: Dictionary = {}
var _last_travel_msec := 0
var _send_player := 0.0
var _send_enemies := 0.0
var _loadout_send_in := 0.0

const LOADOUT_SEND_DELAY := 0.6
const MAX_LOADOUT_BYTES := 262144


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_host_gone)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	get_tree().node_added.connect(_on_node_added)


func is_host() -> bool:
	return active and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


func my_info() -> Dictionary:
	if SaveManager.party.is_empty():
		return {}
	var data := SaveManager.get_data(SaveManager.party[0])
	var loadout := {}
	for key in LOADOUT_KEYS:
		if data.has(key):
			loadout[key] = data[key]
	return {
		"name": str(data.get("name", "Player")).left(24), "class_id": str(data.get("class_id", "")),
		"rank": Ranks.name_of_save(data), "loadout": loadout}


func rank_name(peer: int) -> String:
	var info: Dictionary = roster.get(peer, {})
	var limits = (info.get("loadout", {}) as Dictionary).get("limits", {})
	if limits is Dictionary and limits.has("rank"):
		return Ranks.name_at(int(limits["rank"]))
	return str(info.get("rank", Ranks.LADDER[0]["name"]))


func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	roster = {1: my_info()}
	_host_id = "%d-%d" % [randi(), Time.get_ticks_usec()]
	_announcer = PacketPeerUDP.new()
	_announcer.set_broadcast_enabled(true)
	_announce_timer = 0.0
	roster_changed.emit()
	return OK


func join(address: String, port: int = PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	stop_listening()
	if _announcer != null:
		_announcer.close()
		_announcer = null
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer = null
	active = false
	in_game = false
	travelling = false
	roster.clear()
	_forget_game()


func _forget_game() -> void:
	_am = null
	_players.clear()
	_player_goal.clear()
	_answering.clear()
	answering = false
	_my_loops.clear()
	_waiting.clear()
	_where = {}
	_out_of_step = 0
	_resync_tries = 0
	_resync_path = ""
	_loadout_send_in = 0.0
	visiting = false
	_told_visiting = false
	_forget_area()


func _forget_area() -> void:
	_loot.clear()
	_loot_data.clear()
	_my_hits.clear()
	_events.clear()
	_tags_sent.clear()
	_refs.clear()
	_refs_sent = PackedInt32Array()
	_enemies.clear()
	_enemy_goal.clear()
	_enemy_sent.clear()
	_unmatched.clear()
	_next_enemy = 1
	_area_live = false
	_list_done = false


func _on_connected() -> void:
	active = true
	_register.rpc_id(1, PROTOCOL, my_info())


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	join_failed.emit("Couldn't reach that game.")


func _on_host_gone() -> void:
	_close("The host ended the session.")


func _on_peer_left(id: int) -> void:
	if is_host() and roster.erase(id):
		_waiting.erase(id)
		_refs.erase(id)
		_set_roster.rpc(roster)
		_apply_roster()


func _close(reason: String) -> void:
	var was_in_game := in_game
	if was_in_game:
		SaveManager.save_party()
	leave()
	notice = reason
	session_closed.emit(reason)
	if was_in_game:
		SaveManager.end_session()
		get_tree().paused = false
		get_tree().change_scene_to_file.call_deferred(MAIN_MENU)


@rpc("any_peer", "call_remote", "reliable")
func _register(version: int, info: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var why := ""
	if version != PROTOCOL:
		why = "That game is on a different version."
	elif in_game:
		why = "That game has already started."
	elif roster.size() >= MAX_PLAYERS:
		why = "That game is full."
	elif str(info.get("class_id", "")) == "" or not info.get("loadout") is Dictionary:
		why = "That game couldn't read your character."
	if why != "":
		_refused.rpc_id(id, why)
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer and id in multiplayer.get_peers():
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id))
		return
	roster[id] = {
		"name": str(info.get("name", "Player")).left(24), "class_id": str(info["class_id"]),
		"rank": str(info.get("rank", Ranks.LADDER[0]["name"])).left(16), "loadout": info["loadout"]}
	_set_roster.rpc(roster)
	_apply_roster()


@rpc("authority", "call_remote", "reliable")
func _refused(why: String) -> void:
	leave()
	join_failed.emit(why)


@rpc("authority", "call_remote", "reliable")
func _set_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	_apply_roster()


func _apply_roster() -> void:
	roster_changed.emit()
	if not in_game or _am == null:
		return
	for id: int in _players.keys():
		if not roster.has(id):
			if is_instance_valid(_players[id]):
				_players[id].queue_free()
			_players.erase(id)
			_player_goal.erase(id)
			_answering.erase(id)


func start_game() -> void:
	if is_host() and not in_game:
		_start.rpc(SaveManager.last_town())


@rpc("authority", "call_local", "reliable")
func _start(town: String) -> void:
	start_town = town if ResourceLoader.exists(town) else ""
	in_game = true
	if _announcer != null:
		_announcer.close()
		_announcer = null
	_forget_game()
	SaveManager.start_game()


func start_listening() -> bool:
	stop_listening()
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT, "0.0.0.0") != OK:
		_listener = null
		return false
	return true


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	if not found.is_empty():
		found.clear()
		hosts_changed.emit()


func is_listening() -> bool:
	return _listener != null


func _tick_discovery(delta: float) -> void:
	if _announcer != null:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce_timer = ANNOUNCE_EVERY
			_announce()
	if _listener == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var before := _found_signature()
	while _listener.get_available_packet_count() > 0:
		var bytes := _listener.get_packet()
		var from := _listener.get_packet_ip()
		var info = JSON.parse_string(bytes.get_string_from_utf8())
		if not info is Dictionary or str(info.get("game", "")) != GAME_TAG or found.size() >= 32:
			continue
		var id := str(info.get("id", "")).left(48)
		if from.begins_with("127.") and found.has(id):
			from = found[id].address
		found[id] = {
			"name": str(info.get("name", "Host")).left(24), "class": str(info.get("class", "")).left(24),
			"address": from, "port": int(info.get("port", PORT)), "seen": now,
			"players": int(info.get("players", 1)), "max": int(info.get("max", MAX_PLAYERS)),
			"version": int(info.get("version", 0))}
	for id: String in found.keys():
		if now - found[id].seen > HOST_TIMEOUT:
			found.erase(id)
	if _found_signature() != before:
		hosts_changed.emit()


func _found_signature() -> String:
	var out := ""
	for id: String in found:
		out += "%s|%s|%d;" % [id, found[id].address, found[id].players]
	return out


func _announce() -> void:
	var me: Dictionary = roster.get(1, {})
	var packet := JSON.stringify({
		"game": GAME_TAG, "version": PROTOCOL, "id": _host_id, "port": PORT, "max": MAX_PLAYERS,
		"players": roster.size(), "name": me.get("name", "Host"),
		"class": str(me.get("class_id", "")).capitalize(),
	}).to_utf8_buffer()
	var targets := PackedStringArray(["255.255.255.255", "127.0.0.1"])
	for a in lan_addresses():
		targets.append(a.substr(0, a.rfind(".") + 1) + "255")
	for t in targets:
		_announcer.set_dest_address(t, DISCOVERY_PORT)
		_announcer.put_packet(packet)


func lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


func game_ready(am: AreaManager) -> void:
	if not active or not in_game:
		return
	_am = am
	var mine := am.player
	mine.health.health_changed.connect(func(current: float, _max: float) -> void:
		if active:
			_p_health.rpc(current))
	mine.skill_cast.connect(func(action: StringName) -> void:
		if active:
			_p_cast.rpc(action, mine.global_rotation.y, mine.get_aim_point()))
	mine.equipment.equipment_changed.connect(_loadout_changed)
	mine.skills.changed.connect(_loadout_changed)
	_loadout_changed()
	_set_visiting(start_town if start_town != "" else am.start_area, 1)
	var me := my_id()
	for id: int in roster:
		if id != me:
			_spawn_remote_player(id)
	mine.camera_rig.camera.make_current()


func kernel_changed() -> void:
	if in_game:
		_loadout_changed()


func party_kernel(mine: Node, beyond_act5 := false) -> Dictionary:
	var lines: Array = []
	var merged: Array = []
	if mine != null and is_instance_valid(mine):
		lines.append_array(Array(mine.skills.kernel))
		merged.append_array(KernelScript.null_running(mine.get("quests")))
	if in_game:
		for id: int in _players:
			var p = _players[id]
			if not is_instance_valid(p) or not (p as Player).visible:
				continue
			var loadout: Dictionary = (roster.get(id, {}) as Dictionary).get("loadout", {})
			if beyond_act5 and not bool(loadout.get("kernel_everywhere", false)):
				continue
			lines.append_array(loadout.get("kernel", []))
			merged.append_array(loadout.get("kernel_merged", []))
	var out := {"lines": [], "merged": []}
	for id in lines:
		if KernelScript.LINES.has(str(id)) and not str(id) in out.lines:
			out.lines.append(str(id))
	for id in merged:
		if KernelScript.NULL_LINES.has(str(id)) and not str(id) in out.merged:
			out.merged.append(str(id))
	return out


func party_answers() -> Array:
	var out: Array = []
	if not in_game:
		return out
	for id: int in _players:
		var p = _players[id]
		if not is_instance_valid(p) or not (p as Player).visible:
			continue
		var loadout: Dictionary = (roster.get(id, {}) as Dictionary).get("loadout", {})
		var answers: Array = loadout.get("kernel_answers", [])
		if answers.any(func(a) -> bool: return str(a) != "") or not (loadout.get("kernel", []) as Array).is_empty():
			out.append([peer_name(id), player_colour(id), answers.map(func(a) -> String: return str(a))])
	return out


func who_is_answering() -> String:
	if answering:
		return peer_name(my_id()) if in_game else "you"
	for id: int in _answering:
		if _answering[id] and _players.has(id) and is_instance_valid(_players[id]) and (_players[id] as Player).visible:
			return peer_name(id)
	return ""


func _loadout_changed() -> void:
	_loadout_send_in = LOADOUT_SEND_DELAY


func _live_loadout() -> Dictionary:
	return loadout_of(_am.player)


func loadout_of(mine: Player) -> Dictionary:
	var out := mine.loadout_save()
	out.erase("inventory")
	out["script_routines"] = mine.skills.routines_to_list()
	out["kernel"] = Array(mine.skills.kernel)
	out["kernel_merged"] = KernelScript.null_running(mine.quests)
	out["kernel_everywhere"] = Endings.runs_everywhere(mine.quests)
	out["kernel_answers"] = KernelScript.NULL_LINES.keys().map(func(id: String) -> String:
		return KernelScript.answer_of(mine.quests, id))
	out["limits"] = {"rank": mine.skills.rank(), "points": mine.skills.bonus_points(),
			"steps": mine.skills.bonus_steps()}
	out["class_id"] = String(mine.class_data.id) if mine.class_data != null else ""
	return out


@rpc("any_peer", "call_remote", "reliable")
func _p_loadout(loadout: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id) or var_to_bytes(loadout).size() > MAX_LOADOUT_BYTES:
		return
	var info: Dictionary = roster[id]
	if str(loadout.get("class_id", "")) != str(info.get("class_id", "")):
		return
	if (info.get("loadout", {}) as Dictionary).hash() == loadout.hash() and _players.has(id):
		return
	info["loadout"] = loadout
	if not in_game or _am == null or not is_instance_valid(_am):
		return
	var old := _players.get(id) as Player
	var goal: Dictionary = _player_goal.get(id, {})
	var life := -1.0
	if old != null and is_instance_valid(old):
		life = old.health.current_health
		old.remove_from_group("players")
		old.queue_free()
	_players.erase(id)
	_spawn_remote_player(id)
	var p := _players.get(id) as Player
	if p == null:
		return
	if not goal.is_empty():
		_player_goal[id] = goal
		p.global_position = goal.pos
	if life >= 0.0:
		p.health.apply_remote(minf(life, p.health.current_health), false)


func _spawn_remote_player(id: int) -> void:
	var info: Dictionary = roster[id]
	var data: Dictionary = (info.get("loadout", {}) as Dictionary).duplicate(true)
	data["class_id"] = info.get("class_id", "")
	if not ResourceLoader.exists("res://data/classes/%s.tres" % data["class_id"]):
		push_warning("Coop: player %d has an unknown class '%s'" % [id, data["class_id"]])
		return
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	p.name = "RemotePlayer%d" % id
	p.is_remote = true
	p.coop_data = data
	_am.player.add_sibling(p)
	p.global_position = _am.player.global_position
	var rig: Node3D = p.camera_rig
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.visible = false
	rig.camera.current = false
	for child in ["EnemyHover", "PickupController"]:
		p.get_node(child).process_mode = Node.PROCESS_MODE_DISABLED
	if GameEvents.happened.is_connected(p.quests._on_event):
		GameEvents.happened.disconnect(p.quests._on_event)
	p.health.set_process(false)
	p.health.remote_damage = func(amount: float, ignore_armour: bool) -> void:
		if is_host() and hit_source == Hit.ENEMY:
			_p_hit.rpc_id(id, amount, ignore_armour)
	_players[id] = p
	_player_goal[id] = {"area": 0, "pos": p.global_position, "rot": 0.0, "vel": Vector3.ZERO, "walking": false}
	_add_ring(p, player_colour(id))
	_show_remote(p, false)


func _add_ring(p: Player, colour: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(colour, 0.85)
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.52
	mesh.outer_radius = 0.68
	mesh.rings = 32
	mesh.ring_segments = 4
	mesh.material = mat
	var ring := MeshInstance3D.new()
	ring.name = "CoopRing"
	ring.mesh = mesh
	ring.scale.y = 0.1
	ring.position.y = 0.06
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(ring)


func own_player(tree: SceneTree) -> Node:
	if in_game and _am != null and is_instance_valid(_am) and is_instance_valid(_am.player):
		return _am.player
	return tree.get_first_node_in_group("players") if tree != null else null


func player_colour(id: int) -> Color:
	var ids := roster.keys()
	ids.sort()
	return PLAYER_COLOURS[maxi(ids.find(id), 0) % PLAYER_COLOURS.size()]


func others_here() -> Array:
	var out: Array = []
	if not in_game:
		return out
	for id: int in _players:
		var p = _players[id]
		if is_instance_valid(p) and (p as Player).visible:
			out.append([p, peer_name(id), player_colour(id), bool(_answering.get(id, false))])
	return out


func _show_remote(p: Player, here: bool) -> void:
	p.visible = here
	p.collision_layer = 2 if here else 0
	if here and p.health.current_health > 0.0:
		p.add_to_group("players")
	elif not here:
		p.remove_from_group("players")


func lock_input(on: bool) -> void:
	if _am != null and is_instance_valid(_am.player):
		_am.player.input_locked = on


func request_travel(scene_path: String, spawn_id: StringName, dungeon_level: int, instance_id: int) -> void:
	if is_host():
		_host_travel(scene_path, spawn_id, dungeon_level, instance_id, 1)
	else:
		_ask_travel.rpc_id(1, scene_path, spawn_id, dungeon_level)


@rpc("any_peer", "call_remote", "reliable")
func _ask_travel(scene_path: String, spawn_id: StringName, dungeon_level: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if is_host() and roster.has(from):
		_host_travel(scene_path, spawn_id, dungeon_level, WorldState.REJOIN_OR_NEW, from)


func _host_travel(scene_path: String, spawn_id: StringName, dungeon_level: int, instance_id: int,
		asker: int) -> void:
	if travelling or Time.get_ticks_msec() - _last_travel_msec < 1500:
		return
	var busy := who_is_answering()
	if busy != "":
		var text := "WAITING FOR %s\nThey're answering the Null's pull request." % busy.to_upper()
		if asker == my_id():
			QuestItems.toast(get_tree(), text, Color(1.0, 0.82, 0.30))
		elif asker in multiplayer.get_peers():
			_travel_held.rpc_id(asker, text)
		return
	if not scene_path.begins_with("res://") and not scene_path.begins_with("uid://"):
		return
	if not ResourceLoader.exists(scene_path):
		return
	_last_travel_msec = Time.get_ticks_msec()
	var inst_id := 0
	var rng_seed := 0
	var killed: Array = []
	if dungeon_level > 0:
		var inst := WorldState.prepare_dungeon(scene_path, dungeon_level, instance_id)
		inst_id = inst.id
		rng_seed = inst.rng_seed
		killed = inst.killed.keys()
	_travel.rpc(scene_path, spawn_id, clampi(dungeon_level, 0, 999), inst_id, rng_seed, killed, asker)


@rpc("authority", "call_remote", "reliable")
func _travel_held(text: String) -> void:
	if text.length() < 200:
		QuestItems.toast(get_tree(), text, Color(1.0, 0.82, 0.30))


@rpc("authority", "call_local", "reliable")
func _travel(scene_path: String, spawn_id: StringName, dungeon_level: int, inst_id: int,
		rng_seed: int, killed: Array, asker: int) -> void:
	_where = {"path": scene_path, "spawn": spawn_id, "level": dungeon_level, "inst": inst_id, "seed": rng_seed}
	_out_of_step = 0
	note("travel to %s (spawn %s, level %d, instance %d)" % [scene_path.get_file(), spawn_id, dungeon_level, inst_id])
	if _am == null or not is_instance_valid(_am):
		note("  ...before the game finished loading here: the area check will catch up")
		return
	_last_travel_msec = Time.get_ticks_msec()
	while _am.is_busy():
		await get_tree().process_frame
		if _am == null or not is_instance_valid(_am):
			return
	if dungeon_level > 0:
		if is_host():
			WorldState.prepare_dungeon(scene_path, dungeon_level, inst_id)
		else:
			WorldState.adopt(inst_id, scene_path, dungeon_level, rng_seed, killed)
	_set_visiting(scene_path, asker)
	travelling = true
	await _am.travel_now(scene_path, spawn_id)
	travelling = false


func _set_visiting(dest: String, asker: int) -> void:
	var was := visiting
	visiting = not _within_reach(dest, asker)
	if visiting != was:
		note("%s in %s" % ["VISITING (nothing unlocks)" if visiting else "no longer visiting", dest.get_file()])
	if not visiting:
		_told_visiting = false


func _within_reach(dest: String, asker: int) -> bool:
	var to := Waypoints.normalize(dest)
	var w := Waypoints.for_scene(to)
	if w != null and Waypoints.is_discovered(w):
		return true
	if to == Waypoints.normalize(SaveManager.last_town()):
		return true
	if _am != null and is_instance_valid(_am) and to == Waypoints.normalize(_am.start_area):
		return true
	if visiting:
		return false
	if asker == my_id():
		return true
	if w != null and Waypoints.is_convoy_stop(w) and Waypoints.route_open(w):
		return true
	var area: Node = _am.current_area if _am != null and is_instance_valid(_am) else null
	if area != null and is_instance_valid(area):
		for n in area.find_children("*", "Portal", true, false):
			var portal := n as Portal
			if portal != null and portal.visible and not portal.is_sealed() \
					and Waypoints.normalize(portal.target_area) == to:
				return true
	return false


func stop_cleared(id: String) -> void:
	if in_game and id != "":
		_stop_cleared.rpc(id)


@rpc("any_peer", "call_remote", "reliable")
func _stop_cleared(id: String) -> void:
	if not in_game or visiting or id.length() > 64 or not roster.has(multiplayer.get_remote_sender_id()):
		return
	GameEvents.report(Waypoints.FINISH_DEED, id)
	for w in Waypoints.clear_stop(id):
		QuestItems.toast(get_tree(), "ROUTE UNLOCKED: %s" % w.display_name.to_upper(), Color(0.25, 1.0, 0.55))


const RESYNC_AFTER := 3
const RESYNC_TRIES := 3
var _where: Dictionary = {}
var _out_of_step := 0
var _resync_tries := 0
var _resync_path := ""
var _send_where := 0.0


@rpc("authority", "call_remote", "unreliable_ordered")
func _h_where(scene_path: String, spawn_id: StringName, dungeon_level: int, inst_id: int, rng_seed: int) -> void:
	if not in_game or _am == null or not is_instance_valid(_am):
		return
	if _am.is_busy() or travelling:
		_out_of_step = 0
		return
	var here := Waypoints.normalize(_am.current_scene_path()) if _am.current_area != null else ""
	if here == Waypoints.normalize(scene_path):
		_out_of_step = 0
		return
	_out_of_step += 1
	if _out_of_step < RESYNC_AFTER:
		return
	_out_of_step = 0
	if _resync_path != scene_path:
		_resync_path = scene_path
		_resync_tries = 0
	_resync_tries += 1
	if _resync_tries > RESYNC_TRIES:
		if _resync_tries == RESYNC_TRIES + 1:
			note("GIVING UP on %s: it doesn't load here" % scene_path)
			QuestItems.toast(get_tree(), "CAN'T LOAD THE HOST'S AREA\nBoth players need the same version of the game.",
					Color(1.0, 0.4, 0.4))
		return
	note("out of step: here '%s', the party is in '%s' -> going there (try %d)" % [here.get_file(), scene_path.get_file(), _resync_tries])
	if not ResourceLoader.exists(scene_path):
		note("  ...that scene doesn't exist in this build")
		return
	_where = {"path": scene_path, "spawn": spawn_id, "level": dungeon_level, "inst": inst_id, "seed": rng_seed}
	if dungeon_level > 0:
		WorldState.adopt(inst_id, scene_path, dungeon_level, rng_seed, [])
	_set_visiting(scene_path, 0)
	travelling = true
	await _am.travel_now(scene_path, spawn_id)
	travelling = false


func note(text: String) -> void:
	var line := "%s [%s] %s" % [Time.get_time_string_from_system(), "host" if is_host() else "guest", text]
	print("[Coop] ", line)
	var f := FileAccess.open("user://coop_log.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://coop_log.txt") else FileAccess.WRITE)
	if f != null:
		if f.get_length() > 400000:
			f.resize(0)
		f.seek_end()
		f.store_line(line)
		f.close()


func area_changing() -> void:
	if active:
		_forget_area()


func area_loaded(scene_path: String) -> void:
	if not active or not in_game:
		return
	_area_path = scene_path
	_area_live = true
	note("area loaded: %s" % scene_path.get_file())
	if visiting and not _told_visiting:
		_told_visiting = true
		QuestItems.toast(get_tree(), "VISITING\nThis area is ahead of your own progress: nothing here unlocks for you.",
				Color(1.0, 0.82, 0.30))
	if is_host() and Waypoints.normalize(str(_where.get("path", ""))) != Waypoints.normalize(scene_path):
		_where = {"path": scene_path, "spawn": &"default", "level": 0, "inst": 0, "seed": 0}
	if is_host():
		for id: int in _waiting.keys():
			if _waiting[id] == scene_path:
				_send_enemy_list(id)
	else:
		_e_ready.rpc_id(1, scene_path)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _p_state(area: int, pos: Vector3, rot: float, vel: Vector3, walking: bool, shielded: bool,
		answering_now: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id):
		_answering[id] = answering_now
	if _player_goal.has(id) and pos.is_finite() and vel.is_finite() and is_finite(rot):
		_player_goal[id] = {"area": area, "pos": pos, "rot": rot, "vel": vel.limit_length(60.0), "walking": walking}
		var p := _players.get(id) as Player
		if p != null and is_instance_valid(p):
			p.health.remote_shielded = shielded


@rpc("any_peer", "call_remote", "reliable")
func _p_health(current: float) -> void:
	var p := _players.get(multiplayer.get_remote_sender_id()) as Player
	if p == null or not is_instance_valid(p) or not is_finite(current):
		return
	if p.health.current_health <= 0.0 and current > 0.0:
		p.revive()
		if not p.visible:
			p.remove_from_group("players")
	p.health.apply_remote(current)


@rpc("any_peer", "call_remote", "reliable")
func _p_cast(action: StringName, facing: float, aim_point: Vector3) -> void:
	var p := _players.get(multiplayer.get_remote_sender_id()) as Player
	if p != null and is_instance_valid(p) and p.visible and action in SkillComponent.ACTIONS \
			and is_finite(facing) and aim_point.is_finite():
		p.remote_cast(action, facing, aim_point)
		player_cast.emit(p, action)


@rpc("authority", "call_remote", "reliable")
func _p_hit(amount: float, ignore_armour: bool) -> void:
	if _am != null and is_instance_valid(_am.player) and amount > 0.0 and amount < MAX_DAMAGE:
		_am.player.health.take_damage(amount, ignore_armour)


func enemy_spawned(enemy: Node3D, def: EnemyDefinition, rarity: String, level: int, mods: Array) -> void:
	if not active or not in_game or not enemy is EnemyBase:
		return
	var e := enemy as EnemyBase
	if is_host():
		var id := _next_enemy
		_next_enemy += 1
		var mod_ids: Array = []
		for m in mods:
			mod_ids.append(m.id)
		e.set_meta(NET_ID, id)
		e.set_meta(NET_ENTRY, {
			"id": id, "def": def.resource_path, "def_id": def.id, "rarity": rarity, "level": level,
			"mods": mod_ids, "spawn": e.global_position})
		_enemies[id] = e
		e.health.health_changed.connect(func(current: float, _max: float) -> void:
			if active:
				_e_health.rpc(id, current, damage_by))
		e.ai.attack_requested.connect(func(_target: Node3D) -> void:
			if active:
				_e_attack.rpc(id))
		if _area_live:
			_announce_enemy.call_deferred(id)
		return
	e.ai.halt()
	e.is_remote = true
	_switch_off_logic(e)
	e.health.set_process(false)
	e.health.remote_damage = func(amount: float, ignore_armour: bool) -> void:
		if hit_source == Hit.PLAYER and e.has_meta(NET_ID):
			_hit_seq += 1
			_sent_seq = _hit_seq
			_sent_for = int(e.get_meta(NET_ID))
			var facts := hit_facts.to_dict() if hit_facts != null else {}
			if hit_facts != null and hit_facts.loop_id != "":
				_my_loops[hit_facts.loop_id] = true
			_e_hit.rpc_id(1, _sent_for, amount, ignore_armour, _hit_seq, facts)
	if not _adopting.is_empty():
		_enemies[int(_adopting.id)] = e
		e.set_meta(NET_ID, int(_adopting.id))
	else:
		_unmatched.append({"enemy": e, "def": def.id, "pos": e.global_position, "at": Time.get_ticks_msec()})


const COPY_KEEPS: Array[String] = ["enemy_silhouette.gd", "glitch_death.gd", "glitch_burst.gd", "lock_blast.gd"]
const ENEMY_LOGIC := "res://systems/enemies/"


func _is_enemy_logic(n: Node) -> bool:
	var s := n.get_script() as Script
	if s == null or (n is EnemyTrait and (n as EnemyTrait).coop_aware()):
		return false
	var path := s.resource_path
	return path.begins_with(ENEMY_LOGIC) and not path.get_file() in COPY_KEEPS


func _switch_off_logic(e: EnemyBase) -> void:
	for n in e.find_children("*", "", true, false):
		if _is_enemy_logic(n):
			n.process_mode = Node.PROCESS_MODE_DISABLED


func _on_node_added(n: Node) -> void:
	if not in_game or is_host() or not _is_enemy_logic(n):
		return
	var p := n.get_parent()
	while p != null and not p is EnemyBase:
		p = p.get_parent()
	if p != null and (p as EnemyBase).is_remote:
		n.process_mode = Node.PROCESS_MODE_DISABLED


func _entry_of(e: EnemyBase) -> Dictionary:
	var entry: Dictionary = (e.get_meta(NET_ENTRY) as Dictionary).duplicate()
	var area := _am.current_area if _am != null else null
	entry["parent"] = str(area.get_path_to(e.get_parent())) if area != null and area.is_ancestor_of(e) else ""
	entry["pos"] = e.global_position
	entry["rot"] = e.global_rotation.y
	entry["hp"] = e.health.current_health
	entry["area"] = _area_path
	entry["boost"] = e.get_meta(NET_BOOST, [])
	return entry


func _announce_enemy(id: int) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e != null and is_instance_valid(e) and e.is_inside_tree() and e.health.current_health > 0.0:
		_e_spawned.rpc(_entry_of(e))


@rpc("any_peer", "call_remote", "reliable")
func _e_ready(scene_path: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	_waiting[id] = scene_path
	if _area_live and scene_path == _area_path:
		_send_enemy_list(id)


func _send_enemy_list(peer: int) -> void:
	_waiting.erase(peer)
	_tags_sent.clear()
	var entries: Array = []
	for id: int in _enemies.keys():
		var e = _enemies[id]
		if not is_instance_valid(e) or not (e as Node).is_inside_tree() or e.health.current_health <= 0.0:
			_enemies.erase(id)
			continue
		entries.append(_entry_of(e))
	_e_list.rpc_id(peer, _area_path, entries)
	for id: int in _loot_data.keys():
		if not is_instance_valid(_loot.get(id)):
			_loot_data.erase(id)
			_loot.erase(id)
	_l_list.rpc_id(peer, _area_path, _loot_data.values())


@rpc("authority", "call_remote", "reliable")
func _e_list(scene_path: String, entries: Array) -> void:
	if scene_path != _area_path or not _area_live:
		return
	for entry in entries:
		if entry is Dictionary:
			_adopt_or_spawn(entry)
	for u in _unmatched:
		if is_instance_valid(u.enemy):
			u.enemy.queue_free()
	_unmatched.clear()
	_list_done = true


@rpc("authority", "call_remote", "reliable")
func _e_spawned(entry: Dictionary) -> void:
	if _list_done and str(entry.get("area", "")) == _area_path:
		_adopt_or_spawn(entry)


func _adopt_or_spawn(entry: Dictionary) -> void:
	var id := int(entry.get("id", 0))
	var spawn: Vector3 = entry.get("spawn", Vector3.ZERO)
	var pos: Vector3 = entry.get("pos", spawn)
	if id <= 0 or _enemies.has(id) or not pos.is_finite():
		return
	var best := -1
	var best_d := MATCH_RADIUS
	for i in _unmatched.size():
		var u: Dictionary = _unmatched[i]
		if not is_instance_valid(u.enemy) or u.def != str(entry.get("def_id", "")):
			continue
		var d: float = (u.pos as Vector3).distance_to(spawn)
		if d < best_d:
			best_d = d
			best = i
	var e: EnemyBase = null
	if best >= 0:
		e = _unmatched[best].enemy
		_unmatched.remove_at(best)
		e.set_meta(NET_ID, id)
		_enemies[id] = e
	else:
		e = _spawn_from(entry)
		var boosts = entry.get("boost", [])
		if e != null and boosts is Array and boosts.size() <= 8:
			for b in boosts:
				if b is Array and b.size() == 6:
					EnemySpawner.empower(e, float(b[0]), float(b[1]), float(b[2]), str(b[3]), float(b[4]), float(b[5]))
	if e == null:
		return
	if e.global_position.distance_to(pos) > 0.1:
		e.global_position = pos
		e.global_rotation.y = float(entry.get("rot", 0.0))
	var hp := float(entry.get("hp", -1.0))
	if hp >= 0.0 and not is_equal_approx(hp, e.health.current_health):
		e.health.apply_remote(hp, false)


func _spawn_from(entry: Dictionary) -> EnemyBase:
	var path := str(entry.get("def", ""))
	if _am == null or _am.current_area == null or not path.begins_with("res://") or not ResourceLoader.exists(path):
		return null
	var def := load(path) as EnemyDefinition
	if def == null:
		return null
	var mods: Array = []
	for mod_id in entry.get("mods", []):
		for m in ModifierRegistry.all_modifiers:
			if m.id == str(mod_id):
				mods.append(m)
				break
	var area := _am.current_area
	var parent := area.get_node_or_null(str(entry.get("parent", ""))) if str(entry.get("parent", "")) != "" else null
	if parent == null:
		parent = area.get_node_or_null("Enemies")
	if parent == null:
		parent = area
	_adopting = entry
	var e := EnemySpawner.spawn_enemy(def, str(entry.get("rarity", "normal")), parent,
			entry.get("pos", Vector3.ZERO), clampi(int(entry.get("level", 1)), 1, 999), mods) as EnemyBase
	_adopting = {}
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if e != null and numbers != null:
		numbers.track(e.health)
	return e


@rpc("any_peer", "call_remote", "reliable")
func _e_hit(id: int, amount: float, ignore_armour: bool, seq: int, facts: Dictionary) -> void:
	var e := _enemies.get(id) as EnemyBase
	var from := multiplayer.get_remote_sender_id()
	if not is_host() or e == null or not is_instance_valid(e) or not (amount > 0.0 and amount < MAX_DAMAGE) \
			or not roster.has(from) or var_to_bytes(facts).size() > 4096:
		return
	var info := HitInfo.new()
	info.target = e
	info.position = e.global_position
	info.damage = amount
	if not facts.is_empty():
		info.facts = HitFacts.from_dict(facts, _players.get(from))
		if info.facts.loop_id != "":
			HitFacts.remote_loop(info.facts.loop_id, true)
	var was_alive := e.health.current_health > 0.0
	var traits: Array = e.traits.filter(func(t) -> bool: return is_instance_valid(t))
	hit_source = Hit.ENEMY
	damage_by = from
	for t: EnemyTrait in traits:
		t.modify_incoming(info)
	damage_by = 0
	hit_source = Hit.NONE
	if info.cancelled:
		return
	if info.absorbed:
		if was_alive:
			info.landed = true
			_after_hit(traits, info)
		return
	damage_by = from
	info.dealt = e.health.take_damage(info.damage, ignore_armour)
	damage_by = 0
	if info.dealt <= 0.0:
		return
	info.landed = true
	info.killed = e.health.current_health <= 0.0
	_after_hit(traits, info)
	_e_landed.rpc_id(from, seq, info.dealt, was_alive and info.killed)


func _after_hit(traits: Array, info: HitInfo) -> void:
	hit_source = Hit.ENEMY
	for t: EnemyTrait in traits:
		if is_instance_valid(t):
			t.after_hit(info)
	hit_source = Hit.NONE


var _my_loops: Dictionary = {}
var _loops_check := 0.0


func _check_my_loops(delta: float) -> void:
	_loops_check -= delta
	if _loops_check > 0.0 or _my_loops.is_empty():
		return
	_loops_check = 0.1
	for id: String in _my_loops.keys():
		if not HitFacts.loop_running(id):
			_my_loops.erase(id)
			_loop_done.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _loop_done(id: String) -> void:
	if is_host() and roster.has(multiplayer.get_remote_sender_id()) and id.length() <= 48:
		HitFacts.remote_loop(id, false)


const REFS_EVERY := 0.5
var _refs: Dictionary = {}
var _refs_sent := PackedInt32Array()
var _refs_in := 0.0


func _check_my_refs(delta: float) -> void:
	_refs_in -= delta
	if _refs_in > 0.0 or _am == null or not is_instance_valid(_am):
		return
	_refs_in = REFS_EVERY
	var held := PackedInt32Array()
	for id: int in _enemies.keys():
		var e = _enemies[id]
		if not is_instance_valid(e) or SkillBehavior.is_dead(e):
			continue
		for t in (e as EnemyBase).traits:
			if t is PagedLock and PagedLock.holds(_am.player, e):
				held.append(id)
				break
	if held != _refs_sent:
		_refs_sent = held
		_p_refs.rpc_id(1, held)


@rpc("any_peer", "call_remote", "reliable")
func _p_refs(ids: PackedInt32Array) -> void:
	var from := multiplayer.get_remote_sender_id()
	if is_host() and roster.has(from) and ids.size() <= 64:
		_refs[from] = ids


func referenced_elsewhere(enemy: Node) -> bool:
	if not in_game or not is_host() or not enemy.has_meta(NET_ID):
		return false
	var id := int(enemy.get_meta(NET_ID))
	for peer: int in _refs:
		if id in (_refs[peer] as PackedInt32Array):
			return true
	return false


func damage_by_other() -> bool:
	return in_game and damage_by != 0 and damage_by != my_id()


signal player_info(peer: int, info: Dictionary)
signal trade_message(peer: int, what: String, args: Array)


func ask_info(peer: int) -> void:
	if in_game and peer != my_id() and roster.has(peer):
		_info_ask.rpc_id(peer)


@rpc("any_peer", "call_remote", "reliable")
func _info_ask() -> void:
	var from := multiplayer.get_remote_sender_id()
	if in_game and roster.has(from) and _am != null and is_instance_valid(_am) and is_instance_valid(_am.player):
		_info_reply.rpc_id(from, my_sheet())


@rpc("any_peer", "call_remote", "reliable")
func _info_reply(info: Dictionary) -> void:
	var from := multiplayer.get_remote_sender_id()
	if roster.has(from) and var_to_bytes(info).size() < 16384:
		player_info.emit(from, info)


func my_sheet() -> Dictionary:
	var p := _am.player
	var data := SaveManager.get_data(SaveManager.party[0]) if not SaveManager.party.is_empty() else {}
	var stats := {}
	for s in StatTypes.Stat.values():
		stats[int(s)] = p.stats.get_stat(s)
	var qm: QuestManager = p.get("quests")
	return {"name": str(data.get("name", "Player")).left(24), "class_id": str(data.get("class_id", "")),
			"rank": Ranks.current(qm), "grade": Ranks.grade(qm),
			"life": p.health.current_health, "stats": stats}


func trade_send(peer: int, what: String, args: Array = []) -> void:
	if in_game and peer != my_id() and roster.has(peer):
		_trade_msg.rpc_id(peer, what, args)


@rpc("any_peer", "call_remote", "reliable")
func _trade_msg(what: String, args: Array) -> void:
	var from := multiplayer.get_remote_sender_id()
	if in_game and roster.has(from) and what.length() <= 16 and var_to_bytes(args).size() < 65536:
		trade_message.emit(from, what, args)


func player_node(peer: int) -> Node3D:
	if peer == my_id():
		return own_player(get_tree()) as Node3D
	var p = _players.get(peer)
	return p as Node3D if is_instance_valid(p) else null


var _my_hits: Dictionary = {}
var _hit_seq := 0
var _sent_seq := 0
var _sent_for := 0
const HIT_KEEP_MSEC := 8000


func my_hit(target: Node, cast: SkillCast, info: HitInfo) -> void:
	if not in_game or is_host() or not target.has_meta(NET_ID):
		return
	var seq := _sent_seq
	_sent_seq = 0
	if seq == 0 or _sent_for != int(target.get_meta(NET_ID)):
		return
	var now := Time.get_ticks_msec()
	if _my_hits.size() > 128:
		for s: int in _my_hits.keys():
			if now - int(_my_hits[s][3]) > HIT_KEEP_MSEC or not is_instance_valid(_my_hits[s][1]):
				_my_hits.erase(s)
	_my_hits[seq] = [cast, target, info, now]


@rpc("authority", "call_remote", "reliable")
func _e_landed(seq: int, dealt: float, killed: bool) -> void:
	var rec = _my_hits.get(seq)
	_my_hits.erase(seq)
	if not rec is Array or not is_finite(dealt):
		return
	var cast := rec[0] as SkillCast
	var info := rec[2] as HitInfo
	if cast == null or info == null or not cast.is_valid():
		return
	info.dealt = clampf(dealt, 0.0, MAX_DAMAGE)
	var behavior := cast.behavior if cast.behavior != null else cast.skill.get_behavior()
	if behavior != null:
		behavior.landing_rewards(cast, info)
	if not killed or not is_instance_valid(rec[1]):
		return
	info.killed = true
	for s in cast.skill.support_behaviors:
		s.on_kill(cast, rec[1], info)


func show_impact(caster: Node, pos: Vector3, radius: float, colour: Color, accent: Color) -> void:
	if in_game and _area_live and caster is Player and not (caster as Player).is_remote:
		_fx_impact.rpc(_area_path, pos, radius, colour, accent)


@rpc("any_peer", "call_remote", "reliable")
func _fx_impact(scene_path: String, pos: Vector3, radius: float, colour: Color, accent: Color) -> void:
	if not _area_live or scene_path != _area_path or _am == null or not is_instance_valid(_am) \
			or not pos.is_finite() or not is_finite(radius) or not roster.has(multiplayer.get_remote_sender_id()):
		return
	ImpactEffect.spawn(_am.player.get_parent(), pos, clampf(radius, 0.1, 40.0), colour, accent)


const TAGS_EVERY := 0.25
var _tags_sent: Dictionary = {}
var _tags_in := 0.0


func _send_tags(delta: float) -> void:
	_tags_in -= delta
	if _tags_in > 0.0 or multiplayer.get_peers().is_empty():
		return
	_tags_in = TAGS_EVERY
	for id: int in _enemies.keys():
		var e = _enemies[id]
		if not is_instance_valid(e) or (e as EnemyBase).traits.is_empty():
			continue
		for t in (e as EnemyBase).traits:
			if not is_instance_valid(t) or (t as EnemyTrait).coop_aware():
				continue
			var tag := (t as EnemyTrait).tag_state()
			var key := (t as Object).get_instance_id()
			if _tags_sent.get(key, null) != tag:
				_tags_sent[key] = tag
				enemy_send(e, "trait_tag", [(t as EnemyTrait).coop_key(), tag])


func show_ring(at: Vector3, radius: float, seconds: float, col: Color) -> void:
	if in_game and is_host() and _area_live:
		_fx_ring.rpc(_area_path, at, radius, seconds, col)


func show_orb(from: Vector3, to: Vector3, speed: float, col: Color) -> void:
	if in_game and is_host() and _area_live:
		_fx_orb.rpc(_area_path, from, to, speed, col)


@rpc("authority", "call_remote", "reliable")
func _fx_ring(scene_path: String, at: Vector3, radius: float, seconds: float, col: Color) -> void:
	if _area_live and scene_path == _area_path and _am != null and is_instance_valid(_am) \
			and at.is_finite() and is_finite(radius) and is_finite(seconds):
		LockBlast.ring(_am.player.get_parent(), at, clampf(radius, 0.5, 40.0), clampf(seconds, 0.05, 10.0), 0.0, col)


@rpc("authority", "call_remote", "reliable")
func _fx_orb(scene_path: String, from: Vector3, to: Vector3, speed: float, col: Color) -> void:
	if not (_area_live and scene_path == _area_path and _am != null and is_instance_valid(_am)) \
			or not from.is_finite() or not to.is_finite() or not is_finite(speed):
		return
	var parent := _am.player.get_parent()
	var node := LockBlast.make_orb(col, 0.3)
	parent.add_child(node)
	LockBlast.orb(parent, node, from, to, clampf(speed, 0.5, 60.0), 1.0, 0.0)


var _loot: Dictionary = {}
var _loot_data: Dictionary = {}
var _next_loot := 1
var _opening_prop := false


func rolls_loot() -> bool:
	return not in_game or is_host()


func loot_dropped(pickup: LootPickup) -> void:
	if not in_game or not is_host() or pickup.item == null:
		return
	var id := _next_loot
	_next_loot += 1
	pickup.set_meta(LOOT_ID, id)
	_loot[id] = pickup
	_loot_data[id] = {"id": id, "item": pickup.item.to_dict(), "pos": pickup.global_position}
	if _area_live:
		_l_drop.rpc(_area_path, _loot_data[id])


@rpc("authority", "call_remote", "reliable")
func _l_drop(scene_path: String, entry: Dictionary) -> void:
	if _area_live and scene_path == _area_path:
		_make_loot(entry)


@rpc("authority", "call_remote", "reliable")
func _l_list(scene_path: String, entries: Array) -> void:
	if not _area_live or scene_path != _area_path:
		return
	for entry in entries:
		if entry is Dictionary:
			_make_loot(entry)


func _populator() -> DungeonPopulator:
	var area: Node = _am.current_area if _am != null and is_instance_valid(_am) else null
	if area == null or not is_instance_valid(area):
		return null
	for n in area.find_children("*", "DungeonPopulator", true, false):
		return n as DungeonPopulator
	return null


func _make_loot(entry: Dictionary) -> void:
	var id := int(entry.get("id", 0))
	var pos = entry.get("pos")
	var populator := _populator()
	if id <= 0 or _loot.has(id) or not pos is Vector3 or not (pos as Vector3).is_finite() \
			or not entry.get("item") is Dictionary or populator == null:
		return
	var item := ItemInstance.from_dict(entry["item"])
	if item == null:
		return
	var pickup := populator.place_item(item, pos)
	pickup.set_meta(LOOT_ID, id)
	_loot[id] = pickup


func loot_take(pickup: LootPickup) -> void:
	var id := int(pickup.get_meta(LOOT_ID, 0))
	if is_host():
		_host_take(id, 1)
	else:
		_l_ask.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _l_ask(id: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if is_host() and roster.has(from):
		_host_take(id, from)


func _host_take(id: int, peer: int) -> void:
	if _loot_data.has(id):
		_loot_data.erase(id)
		_l_taken.rpc(id, peer)


@rpc("authority", "call_local", "reliable")
func _l_taken(id: int, peer: int) -> void:
	var pickup = _loot.get(id)
	_loot.erase(id)
	if not is_instance_valid(pickup):
		return
	if peer != my_id() or _am == null or not is_instance_valid(_am):
		(pickup as LootPickup).queue_free()
		return
	var item: ItemInstance = (pickup as LootPickup).item
	var at: Vector3 = (pickup as LootPickup).global_position
	if not (pickup as LootPickup).give_to(_am.player.inventory):
		(pickup as LootPickup).queue_free()
		if is_host():
			_put_back(item.to_dict(), at)
		else:
			_l_return.rpc_id(1, item.to_dict(), at)


@rpc("any_peer", "call_remote", "reliable")
func _l_return(item: Dictionary, pos: Vector3) -> void:
	if is_host() and roster.has(multiplayer.get_remote_sender_id()) and pos.is_finite() \
			and var_to_bytes(item).size() < 8192:
		_put_back(item, pos)


func _put_back(item: Dictionary, pos: Vector3) -> void:
	var populator := _populator()
	var inst := ItemInstance.from_dict(item)
	if populator != null and inst != null:
		loot_dropped(populator.place_item(inst, pos))


func prop_opened(index: int) -> void:
	if in_game and _area_live and not _opening_prop:
		_prop_open.rpc(_area_path, index)


@rpc("any_peer", "call_remote", "reliable")
func _prop_open(scene_path: String, index: int) -> void:
	var populator := _populator()
	if not _area_live or scene_path != _area_path or populator == null \
			or not roster.has(multiplayer.get_remote_sender_id()):
		return
	_opening_prop = true
	populator.open_prop(index)
	_opening_prop = false


var _events: Dictionary = {}


func event_register(key: String, node: Node) -> void:
	if in_game:
		_events[key] = node


func event_send(key: String, what: String, args: Array, peer: int = 0) -> void:
	if not in_game:
		return
	if not is_host():
		_event_msg.rpc_id(1, key, what, args)
	elif peer == 0:
		_event_msg.rpc(key, what, args)
	elif peer != 1 and peer in multiplayer.get_peers():
		_event_msg.rpc_id(peer, key, what, args)


@rpc("any_peer", "call_remote", "reliable")
func _event_msg(key: String, what: String, args: Array) -> void:
	var from := multiplayer.get_remote_sender_id()
	if is_host() != (from != 1) or not roster.has(from) or what.length() > 32 or args.size() > 8:
		return
	var node = _events.get(key)
	if is_instance_valid(node) and (node as Node).has_method("coop_message"):
		node.coop_message(what, args, from)


func enemy_send(enemy: Node3D, what: String, args: Array, peer: int = 0) -> void:
	lock_send(enemy, what, args, peer)


func lock_send(enemy: Node3D, what: String, args: Array, peer: int = 0) -> void:
	if not in_game or enemy == null or not enemy.has_meta(NET_ID):
		return
	var id := int(enemy.get_meta(NET_ID))
	if not is_host():
		_lock_msg.rpc_id(1, id, what, args)
	elif peer == 0:
		_lock_msg.rpc(id, what, args)
	elif peer != 1 and peer in multiplayer.get_peers():
		_lock_msg.rpc_id(peer, id, what, args)


@rpc("any_peer", "call_remote", "reliable")
func _lock_msg(id: int, what: String, args: Array) -> void:
	var from := multiplayer.get_remote_sender_id()
	if is_host() != (from != 1) or not roster.has(from):
		return
	var e := _enemies.get(id) as EnemyBase
	if e == null or not is_instance_valid(e) or what.length() > 32 or args.size() > 8:
		return
	for n in e.find_children("*", "", true, false):
		if n.has_method("coop_message"):
			n.coop_message(what, args, from)


func player_peer(p: Node) -> int:
	for id: int in _players:
		if _players[id] == p:
			return id
	return my_id()


func peer_name(id: int) -> String:
	return str((roster.get(id, {}) as Dictionary).get("name", "Player"))


@rpc("authority", "call_remote", "reliable")
func _e_health(id: int, current: float, by: int) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e != null and is_instance_valid(e):
		damage_by = by
		e.health.apply_remote(current)
		damage_by = 0
		if current <= 0.0:
			_enemy_goal.erase(id)


@rpc("authority", "call_remote", "unreliable_ordered")
func _e_state(ids: PackedInt32Array, positions: PackedVector3Array, rotations: PackedFloat32Array,
		states: PackedByteArray) -> void:
	if positions.size() != ids.size() or rotations.size() != ids.size() or states.size() != ids.size():
		return
	for i in ids.size():
		var e := _enemies.get(ids[i]) as EnemyBase
		if e == null or not is_instance_valid(e):
			continue
		_enemy_goal[ids[i]] = {"pos": positions[i], "rot": rotations[i]}
		e.ai.state = clampi(states[i], 0, AIComponent.State.size() - 1) as AIComponent.State


@rpc("authority", "call_remote", "reliable")
func _e_attack(id: int) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e == null or not is_instance_valid(e) or e.model == null:
		return
	var cooldown := 1.0 / maxf(e.stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 0.1)
	SoundManager.play_skill("attack", e, e.model.play_attack(cooldown))


func enemy_cast(enemy: Node3D, index: int, gem_id: String) -> void:
	if is_host() and in_game and enemy.has_meta(NET_ID):
		_e_cast.rpc(int(enemy.get_meta(NET_ID)), index, gem_id, enemy.global_rotation.y)


@rpc("authority", "call_remote", "reliable")
func _e_cast(id: int, index: int, gem_id: String, facing: float) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e == null or not is_instance_valid(e) or not e.is_inside_tree() or not is_finite(facing) \
			or gem_id.length() > 64:
		return
	var caster := e.get_node_or_null("EnemySkills") as EnemySkills
	if caster != null:
		_enemy_goal[id] = {"pos": _enemy_goal.get(id, {}).get("pos", e.global_position), "rot": facing}
		caster.remote_cast(index, gem_id, facing)


func _process(delta: float) -> void:
	_tick_discovery(delta)
	if in_game and _loadout_send_in > 0.0 and _am != null and is_instance_valid(_am):
		_loadout_send_in -= delta
		if _loadout_send_in <= 0.0 and is_instance_valid(_am.player):
			var loadout := _live_loadout()
			if roster.has(my_id()):
				roster[my_id()]["loadout"] = loadout
			_p_loadout.rpc(loadout)
	if in_game and not is_host():
		_check_my_loops(delta)
		_check_my_refs(delta)
	if is_host() and in_game and _area_live:
		_send_tags(delta)
	if not in_game or _list_done == false or _unmatched.is_empty():
		return
	var now := Time.get_ticks_msec()
	for i in range(_unmatched.size() - 1, -1, -1):
		var u: Dictionary = _unmatched[i]
		if not is_instance_valid(u.enemy):
			_unmatched.remove_at(i)
		elif now - int(u.at) > UNMATCHED_GRACE * 1000.0:
			u.enemy.queue_free()
			_unmatched.remove_at(i)


func _physics_process(delta: float) -> void:
	if not in_game or _am == null or not is_instance_valid(_am):
		return
	var ease_in := 1.0 - exp(-delta * 15.0)
	var here := _area_path.hash() if _area_live else -1

	for id: int in _player_goal:
		var p := _players.get(id) as Player
		if p == null or not is_instance_valid(p) or not p.is_inside_tree():
			continue
		var goal: Dictionary = _player_goal[id]
		var same_area: bool = goal.area == here and goal.area != 0
		if same_area != p.visible:
			_show_remote(p, same_area)
			p.global_position = goal.pos
		if not same_area or p.health.current_health <= 0.0:
			continue
		if p.global_position.distance_to(goal.pos) > SNAP_DISTANCE:
			p.global_position = goal.pos
		else:
			p.global_position = p.global_position.lerp(goal.pos, ease_in)
		p.global_rotation.y = lerp_angle(p.global_rotation.y, goal.rot, ease_in)
		p.velocity = goal.vel
		if p.walking != goal.walking:
			p.walking = goal.walking
			p.walking_changed.emit(p.walking)

	for id: int in _enemy_goal.keys():
		var e := _enemies.get(id) as EnemyBase
		if e == null or not is_instance_valid(e) or not e.is_inside_tree() or e.health.current_health <= 0.0:
			_enemy_goal.erase(id)
			continue
		var goal: Dictionary = _enemy_goal[id]
		var gap: Vector3 = goal.pos - e.global_position
		if gap.length() > SNAP_DISTANCE:
			e.global_position = goal.pos
		else:
			e.velocity = gap * 12.0
			e.move_and_slide()
		e.global_rotation.y = lerp_angle(e.global_rotation.y, goal.rot, ease_in)
		if gap.length() < 0.03 and absf(angle_difference(e.global_rotation.y, goal.rot)) < 0.02:
			_enemy_goal.erase(id)

	_send_player -= delta
	if _send_player <= 0.0:
		_send_player = SEND_PLAYER_EVERY
		var mine := _am.player
		if is_instance_valid(mine):
			_p_state.rpc(here, mine.global_position, mine.global_rotation.y, mine.velocity, mine.walking,
					mine.health.is_shielded(), answering)
	if not is_host() or not _area_live:
		return
	_send_where -= delta
	if _send_where <= 0.0 and not _where.is_empty() and not travelling and not _am.is_busy():
		_send_where = 1.0
		_h_where.rpc(str(_where.path), StringName(_where.spawn), int(_where.level), int(_where.inst), int(_where.seed))
	_send_enemies -= delta
	if _send_enemies > 0.0:
		return
	_send_enemies = SEND_ENEMIES_EVERY
	var ids := PackedInt32Array()
	var positions := PackedVector3Array()
	var rotations := PackedFloat32Array()
	var states := PackedByteArray()
	for id: int in _enemies.keys():
		var e = _enemies[id]
		if not is_instance_valid(e) or e.health.current_health <= 0.0:
			_enemies.erase(id)
			_enemy_sent.erase(id)
			continue
		if not (e as Node).is_inside_tree():
			continue
		if e.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		var now: Array = [e.global_position, e.global_rotation.y, int(e.ai.state)]
		var last: Array = _enemy_sent.get(id, [])
		if not last.is_empty() and (last[0] as Vector3).distance_to(now[0]) < 0.02 \
				and absf(float(last[1]) - float(now[1])) < 0.01 and last[2] == now[2]:
			continue
		_enemy_sent[id] = now
		ids.append(id)
		positions.append(now[0])
		rotations.append(now[1])
		states.append(now[2])
	for start in range(0, ids.size(), ENEMIES_PER_PACKET):
		var end := mini(start + ENEMIES_PER_PACKET, ids.size())
		_e_state.rpc(ids.slice(start, end), positions.slice(start, end), rotations.slice(start, end),
				states.slice(start, end))
