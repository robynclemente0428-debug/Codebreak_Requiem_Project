extends Node
## Autoload: Coop
## LAN co-op: the session (who is here), and everything the machines tell each other. Every
## message goes through this one node, so it never depends on scene paths matching.
## Off (active = false) in single player: every hook below returns at once.
##
## The way in: main menu LOBBY -> Character Select (your own save slot) -> the lobby screen
## (HOST or JOIN, scenes/ui/lobby) -> the host presses START -> everyone loads main.tscn.
##
## Who decides what (host-authoritative):
##   the host       which area the party is in, and every enemy: its AI, where it is, its health
##   each player    their own character: where it is, its health, the skills it casts, and their
##                  own save, quests, loot, shops and dialogue (nothing of that is shared yet)
##
## The party is always in one area together. A portal or the waypoint map asks the host
## (AreaManager.go_to -> request_travel), and the host sends everyone there with the dungeon
## instance's seed, so every machine builds the same dungeon and the same enemies.
##
## Enemies: every machine spawns them (EnemySpawner calls enemy_spawned). On a client each one is
## a remote copy (AI halted, no skills) until the host's list arrives: the copies the host also
## has are matched by kind and spawn point, the ones it doesn't have are removed, and the ones
## only it has are spawned from the list. After that the host sends positions, health, attacks.
##
## Damage always goes to the owner, and the owner sends the health back to everyone
## (HealthComponent.remote_damage / apply_remote). Only real hits are forwarded (hit_source):
##   a player's skill on a client's copy of an enemy   -> the host applies it
##   an enemy's hit on the host's copy of a player     -> that player's machine applies it
## Anything else that hurts (floor hazards, a lock's punishment) each machine works out for its
## own player only, so nothing lands twice.
##
## Not synced yet: boss locks and their state, enemy projectiles on clients, wave events, loot
## (each player rolls their own), quests, gear changes after the lobby, joining mid-game.

signal roster_changed
signal hosts_changed
## The session is over on this machine (the host left, or we were refused). `reason` may be "".
signal session_closed(reason: String)
signal join_failed(reason: String)

const PORT := 24547
const DISCOVERY_PORT := 24548
const GAME_TAG := "codebreak_requiem_coop"
## Bumped whenever the messages change: a host refuses a player on another number.
const PROTOCOL := 1
const MAX_PLAYERS := 4
const ANNOUNCE_EVERY := 1.0
const HOST_TIMEOUT := 3.5
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
## What of a save file the other machines need to build a copy of this character.
const LOADOUT_KEYS: Array[String] = ["class_id", "equipment", "skills", "script_set", "script_set_names",
		"script_routines", "kernel"]

const SEND_PLAYER_EVERY := 0.05          # 20 a second
const SEND_ENEMIES_EVERY := 0.066        # 15 a second
const SNAP_DISTANCE := 5.0               # a copy further than this from the truth jumps there
const UNMATCHED_GRACE := 2.5             # seconds a client's own extra enemy may wait for the host's
const MATCH_RADIUS := 1.0                # metres between a copy's and the host's spawn point
const MAX_DAMAGE := 10000000.0           # a hit reported as bigger than this is thrown away
const NET_ID := &"coop_id"               # meta on an enemy: its id in this area, the same everywhere
const NET_ENTRY := &"coop_entry"         # meta on the host's enemies: how to build it elsewhere

enum Hit { NONE, PLAYER, ENEMY }
## What is dealing damage right now (set by SkillBehavior.hit and EnemyBase's swing just around
## take_damage). Only these are sent to the owner; see the header.
var hit_source := Hit.NONE

var active := false                      # in a session (the lobby's room, or the game)
var in_game := false
## The main menu's LOBBY was pressed: Character Select goes to the lobby instead of the game.
var picking := false
var notice := ""                         # why the last session ended, for the main menu
var roster: Dictionary = {}              # peer id -> {name, class_id, level, loadout}
var start_town := ""                     # the host's last town: where the party starts
var travelling := false                  # go_to is running for a trip the host sent

# ---- finding hosts ----
var found: Dictionary = {}               # host id -> {name, class, address, port, players, max, seen}
var _announcer: PacketPeerUDP
var _listener: PacketPeerUDP
var _announce_timer := 0.0
var _host_id := ""

# ---- in the game ----
var _am: AreaManager
var _players: Dictionary = {}            # peer id -> Player (the remote copies)
var _player_goal: Dictionary = {}        # peer id -> {area, pos, rot, vel, walking}
var _enemies: Dictionary = {}            # enemy id -> EnemyBase
var _enemy_goal: Dictionary = {}         # enemy id -> {pos, rot} (clients)
var _enemy_sent: Dictionary = {}         # enemy id -> [pos, rot, state] last sent (host)
var _unmatched: Array = []               # clients: [{enemy, def, pos, at}] waiting for the host's list
var _next_enemy := 1
var _area_path := ""
var _area_live := false                  # this machine finished loading _area_path
var _list_done := false                  # clients: the host's enemy list for this area arrived
var _waiting: Dictionary = {}            # host: peer id -> the area it finished loading
var _adopting: Dictionary = {}           # the host's entry being spawned here right now
var _last_travel_msec := 0
var _send_player := 0.0
var _send_enemies := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS       # a paused menu never stops the session
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_host_gone)
	multiplayer.peer_disconnected.connect(_on_peer_left)


func is_host() -> bool:
	return active and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


# ---------- THE SESSION ----------
## This machine's character, from the save slot seated in Character Select.
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
		"level": int(data.get("level", 1)), "loadout": loadout}


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


## Out of the session, quietly (BACK in the lobby, the main menu, quitting).
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
	_waiting.clear()
	_forget_area()


func _forget_area() -> void:
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
		_set_roster.rpc(roster)
		_apply_roster()


## The session ended under us. In the game: save, and back to the main menu with the reason.
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


## A player that just connected says who they are.
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
		"level": int(info.get("level", 1)), "loadout": info["loadout"]}
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
	for id: int in _players.keys():                # someone left: their copy goes
		if not roster.has(id):
			if is_instance_valid(_players[id]):
				_players[id].queue_free()
			_players.erase(id)
			_player_goal.erase(id)


## The host's START: everyone loads the game, in the host's last town.
func start_game() -> void:
	if is_host() and not in_game:
		_start.rpc(SaveManager.last_town())


@rpc("authority", "call_local", "reliable")
func _start(town: String) -> void:
	start_town = town if ResourceLoader.exists(town) else ""
	in_game = true
	if _announcer != null:                         # no joining mid-game yet: off the lists
		_announcer.close()
		_announcer = null
	_forget_game()
	SaveManager.start_game()


# ---------- FINDING HOSTS ON THE NETWORK ----------
## The lobby's JOIN screen calls this while it shows. False = this window can't listen (another
## window on this PC already is): joining by address still works.
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
		# A host on this same PC is heard on 127.0.0.1 and on its LAN address: keep the LAN one
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


## One packet to everyone on the network: the broadcast address, each adapter's own x.y.z.255 (a
## PC with several adapters only sends the plain broadcast out of one), and this PC itself.
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


# ---------- THE GAME STARTS (AreaManager._ready) ----------
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
	var me := my_id()
	for id: int in roster:
		if id != me:
			_spawn_remote_player(id)
	mine.camera_rig.camera.make_current()          # a copy's camera may have taken over


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
	_am.player.add_sibling(p)                      # after ours in the tree: ours stays "the first player"
	p.global_position = _am.player.global_position
	var rig: Node3D = p.camera_rig                 # no camera, hover plate or pickups for a copy
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.visible = false
	rig.camera.current = false
	for child in ["EnemyHover", "PickupController"]:
		p.get_node(child).process_mode = Node.PROCESS_MODE_DISABLED
	if GameEvents.happened.is_connected(p.quests._on_event):
		GameEvents.happened.disconnect(p.quests._on_event)   # a copy has no quests to advance
	p.health.set_process(false)                    # no regen here: the owner sends the health
	p.health.remote_damage = func(amount: float, ignore_armour: bool) -> void:
		if is_host() and hit_source == Hit.ENEMY:  # the host's enemies are the real ones
			_p_hit.rpc_id(id, amount, ignore_armour)
	_players[id] = p
	_player_goal[id] = {"area": 0, "pos": p.global_position, "rot": 0.0, "vel": Vector3.ZERO, "walking": false}
	_show_remote(p, false)                         # until its first position says where it is


## A remote copy only counts (is seen, blocks, gets targeted) while its owner is in this area.
func _show_remote(p: Player, here: bool) -> void:
	p.visible = here
	p.collision_layer = 2 if here else 0
	if here and p.health.current_health > 0.0:
		p.add_to_group("players")
	elif not here:
		p.remove_from_group("players")


## The pause menu in co-op: the world keeps running, so only our own character stops.
func lock_input(on: bool) -> void:
	if _am != null and is_instance_valid(_am.player):
		_am.player.input_locked = on


# ---------- TRAVEL: THE PARTY MOVES TOGETHER ----------
## AreaManager.go_to in co-op: ask the host instead of going.
func request_travel(scene_path: String, spawn_id: StringName, dungeon_level: int, instance_id: int) -> void:
	if is_host():
		_host_travel(scene_path, spawn_id, dungeon_level, instance_id)
	else:
		_ask_travel.rpc_id(1, scene_path, spawn_id, dungeon_level)


@rpc("any_peer", "call_remote", "reliable")
func _ask_travel(scene_path: String, spawn_id: StringName, dungeon_level: int) -> void:
	if is_host() and roster.has(multiplayer.get_remote_sender_id()):
		_host_travel(scene_path, spawn_id, dungeon_level, WorldState.REJOIN_OR_NEW)


func _host_travel(scene_path: String, spawn_id: StringName, dungeon_level: int, instance_id: int) -> void:
	# Two players in the same doorway ask twice: the first one decides
	if travelling or Time.get_ticks_msec() - _last_travel_msec < 1500:
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
	_travel.rpc(scene_path, spawn_id, clampi(dungeon_level, 0, 999), inst_id, rng_seed, killed)


@rpc("authority", "call_local", "reliable")
func _travel(scene_path: String, spawn_id: StringName, dungeon_level: int, inst_id: int,
		rng_seed: int, killed: Array) -> void:
	if _am == null or not is_instance_valid(_am):
		return
	_last_travel_msec = Time.get_ticks_msec()
	while _am.is_busy():                           # still arriving from the last trip
		await get_tree().process_frame
		if _am == null or not is_instance_valid(_am):
			return
	if dungeon_level > 0:
		if is_host():
			WorldState.prepare_dungeon(scene_path, dungeon_level, inst_id)
		else:
			WorldState.adopt(inst_id, scene_path, dungeon_level, rng_seed, killed)
	travelling = true
	await _am.travel_now(scene_path, spawn_id)
	travelling = false


## AreaManager is about to swap areas: the old area's enemies are gone.
func area_changing() -> void:
	if active:
		_forget_area()


## AreaManager finished loading an area here.
func area_loaded(scene_path: String) -> void:
	if not active or not in_game:
		return
	_area_path = scene_path
	_area_live = true
	if is_host():
		for id: int in _waiting.keys():            # players who got here before us
			if _waiting[id] == scene_path:
				_send_enemy_list(id)
	else:
		_e_ready.rpc_id(1, scene_path)


# ---------- PLAYERS ----------
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _p_state(area: int, pos: Vector3, rot: float, vel: Vector3, walking: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _player_goal.has(id) and pos.is_finite() and vel.is_finite() and is_finite(rot):
		_player_goal[id] = {"area": area, "pos": pos, "rot": rot, "vel": vel.limit_length(60.0), "walking": walking}


@rpc("any_peer", "call_remote", "reliable")
func _p_health(current: float) -> void:
	var p := _players.get(multiplayer.get_remote_sender_id()) as Player
	if p == null or not is_instance_valid(p) or not is_finite(current):
		return
	if p.health.current_health <= 0.0 and current > 0.0:
		p.revive()                                 # stands the copy back up (its owner respawned)
		if not p.visible:
			p.remove_from_group("players")         # revive() put it back in; it isn't in this area
	p.health.apply_remote(current)


@rpc("any_peer", "call_remote", "reliable")
func _p_cast(action: StringName, facing: float, aim_point: Vector3) -> void:
	var p := _players.get(multiplayer.get_remote_sender_id()) as Player
	if p != null and is_instance_valid(p) and p.visible and action in SkillComponent.ACTIONS \
			and is_finite(facing) and aim_point.is_finite():
		p.remote_cast(action, facing, aim_point)


## One of the host's enemies hit this machine's player.
@rpc("authority", "call_remote", "reliable")
func _p_hit(amount: float, ignore_armour: bool) -> void:
	if _am != null and is_instance_valid(_am.player) and amount > 0.0 and amount < MAX_DAMAGE:
		_am.player.health.take_damage(amount, ignore_armour)


# ---------- ENEMIES ----------
## EnemySpawner calls this for every enemy it makes, on every machine.
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
				_e_health.rpc(id, current))
		e.ai.attack_requested.connect(func(_target: Node3D) -> void:
			if active:
				_e_attack.rpc(id))
		if _area_live:                             # spawned mid-fight (a summon, a wave): tell everyone
			_announce_enemy.call_deferred(id)
		return
	# A client: a remote copy from the start
	e.ai.halt()                                    # the host thinks for it
	var caster := e.get_node_or_null("EnemySkills")
	if caster != null:
		caster.process_mode = Node.PROCESS_MODE_DISABLED
	e.health.set_process(false)
	e.health.remote_damage = func(amount: float, ignore_armour: bool) -> void:
		if hit_source == Hit.PLAYER and e.has_meta(NET_ID):    # our own skill landed
			_e_hit.rpc_id(1, int(e.get_meta(NET_ID)), amount, ignore_armour)
	if not _adopting.is_empty():
		_enemies[int(_adopting.id)] = e
		e.set_meta(NET_ID, int(_adopting.id))
	else:
		_unmatched.append({"enemy": e, "def": def.id, "pos": e.global_position, "at": Time.get_ticks_msec()})


func _entry_of(e: EnemyBase) -> Dictionary:
	var entry: Dictionary = (e.get_meta(NET_ENTRY) as Dictionary).duplicate()
	var area := _am.current_area if _am != null else null
	entry["parent"] = str(area.get_path_to(e.get_parent())) if area != null and area.is_ancestor_of(e) else ""
	entry["pos"] = e.global_position
	entry["rot"] = e.global_rotation.y
	entry["hp"] = e.health.current_health
	entry["area"] = _area_path
	return entry


func _announce_enemy(id: int) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e != null and is_instance_valid(e) and e.is_inside_tree() and e.health.current_health > 0.0:
		_e_spawned.rpc(_entry_of(e))


## A client finished loading the area: it wants the host's enemies.
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
	var entries: Array = []
	for id: int in _enemies.keys():
		var e = _enemies[id]
		if not is_instance_valid(e) or not (e as Node).is_inside_tree() or e.health.current_health <= 0.0:
			_enemies.erase(id)                     # removed after spawning (killed on an earlier visit), or dead
			continue
		entries.append(_entry_of(e))
	_e_list.rpc_id(peer, _area_path, entries)


@rpc("authority", "call_remote", "reliable")
func _e_list(scene_path: String, entries: Array) -> void:
	if scene_path != _area_path or not _area_live:
		return                                     # for an area we already left
	for entry in entries:
		if entry is Dictionary:
			_adopt_or_spawn(entry)
	for u in _unmatched:                           # the host doesn't have these
		if is_instance_valid(u.enemy):
			u.enemy.queue_free()
	_unmatched.clear()
	_list_done = true


@rpc("authority", "call_remote", "reliable")
func _e_spawned(entry: Dictionary) -> void:
	if _list_done and str(entry.get("area", "")) == _area_path:
		_adopt_or_spawn(entry)


## Makes the host's enemy `entry` exist here: our own copy of it if we spawned one (same kind,
## same spawn point), otherwise a new one built from the entry.
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
	if e == null:
		return
	if e.global_position.distance_to(pos) > 0.1:
		e.global_position = pos
		e.global_rotation.y = float(entry.get("rot", 0.0))
	var hp := float(entry.get("hp", -1.0))
	if hp >= 0.0 and not is_equal_approx(hp, e.health.current_health):
		e.health.apply_remote(hp)


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
	return e


## A client's skill hit an enemy: the host applies it (and its health goes back to everyone).
@rpc("any_peer", "call_remote", "reliable")
func _e_hit(id: int, amount: float, ignore_armour: bool) -> void:
	var e := _enemies.get(id) as EnemyBase
	if is_host() and e != null and is_instance_valid(e) and amount > 0.0 and amount < MAX_DAMAGE \
			and roster.has(multiplayer.get_remote_sender_id()):
		for t in e.traits:                         # a lock the host owns: its port is shut, nothing lands
			if t is ChallengeLock and not (t as ChallengeLock).is_open():
				return
		e.health.take_damage(amount, ignore_armour)


# ---------- BOSS LOCKS THE HOST OWNS ----------
## A lock on the host talks to its copies, and a copy talks to the host's: the trait's own
## `what` and `args`, delivered to coop_message(what, args, from) on the same enemy's traits.
## From the host, peer 0 = every other machine. From a client it always goes to the host.
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
		return                                     # clients hear the host, the host hears its players
	var e := _enemies.get(id) as EnemyBase
	if e == null or not is_instance_valid(e) or what.length() > 32 or args.size() > 8:
		return
	for t in e.traits:
		if is_instance_valid(t) and t.has_method("coop_message"):
			t.coop_message(what, args, from)


## The machine a player's character belongs to (ours for our own).
func player_peer(p: Node) -> int:
	for id: int in _players:
		if _players[id] == p:
			return id
	return my_id()


func peer_name(id: int) -> String:
	return str((roster.get(id, {}) as Dictionary).get("name", "Player"))


@rpc("authority", "call_remote", "reliable")
func _e_health(id: int, current: float) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e != null and is_instance_valid(e):
		e.health.apply_remote(current)             # at 0 it dies here too (EnemyBase._on_died)
		if current <= 0.0:
			_enemies.erase(id)
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


## The swing, for show: the host's enemy deals the damage.
@rpc("authority", "call_remote", "reliable")
func _e_attack(id: int) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e == null or not is_instance_valid(e) or e.model == null:
		return
	var cooldown := 1.0 / maxf(e.stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 0.1)
	SoundManager.play_skill("attack", e, e.model.play_attack(cooldown))


## EnemyBase.play_skill_animation on the host: the clients play the same clip.
func enemy_skill_animation(enemy: Node3D, key: String, fit_duration: float) -> void:
	if is_host() and in_game and enemy.has_meta(NET_ID):
		_e_anim.rpc(int(enemy.get_meta(NET_ID)), key, fit_duration)


@rpc("authority", "call_remote", "reliable")
func _e_anim(id: int, key: String, fit_duration: float) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e != null and is_instance_valid(e) and e.model != null and is_finite(fit_duration):
		var hit_in := e.model.play_skill(key, fit_duration)
		if hit_in > 0.0:
			SoundManager.play_skill(key, e, hit_in)


# ---------- EVERY FRAME ----------
func _process(delta: float) -> void:
	_tick_discovery(delta)
	if not in_game or _list_done == false or _unmatched.is_empty():
		return
	# A client's own extra enemies (its copy of a boss's summon...): if the host never announces
	# one, it isn't real
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

	# Remote players ease to where their owner says they are
	for id: int in _player_goal:
		var p := _players.get(id) as Player
		if p == null or not is_instance_valid(p):
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
		p.velocity = goal.vel                      # the model picks its jog direction from this
		if p.walking != goal.walking:
			p.walking = goal.walking
			p.walking_changed.emit(p.walking)

	# On a client the enemies walk to where the host says they are (walk, so the run clip plays)
	for id: int in _enemy_goal.keys():
		var e := _enemies.get(id) as EnemyBase
		if e == null or not is_instance_valid(e) or e.health.current_health <= 0.0:
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
			_enemy_goal.erase(id)                  # arrived: nothing to do until the host moves it

	_send_player -= delta
	if _send_player <= 0.0:
		_send_player = SEND_PLAYER_EVERY
		var mine := _am.player
		if is_instance_valid(mine):
			_p_state.rpc(here, mine.global_position, mine.global_rotation.y, mine.velocity, mine.walking)
	if not is_host() or not _area_live:
		return
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
		if e.process_mode == Node.PROCESS_MODE_DISABLED:
			continue                               # asleep, far from everyone (EnemySleep)
		var now: Array = [e.global_position, e.global_rotation.y, int(e.ai.state)]
		var last: Array = _enemy_sent.get(id, [])
		if not last.is_empty() and (last[0] as Vector3).distance_to(now[0]) < 0.02 \
				and absf(float(last[1]) - float(now[1])) < 0.01 and last[2] == now[2]:
			continue                               # hasn't moved since the last send
		_enemy_sent[id] = now
		ids.append(id)
		positions.append(now[0])
		rotations.append(now[1])
		states.append(now[2])
	if not ids.is_empty():
		_e_state.rpc(ids, positions, rotations, states)
