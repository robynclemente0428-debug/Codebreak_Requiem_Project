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
##                  own save, quests, credits, shops and dialogue (none of that is shared)
##
## The party is always in one area together. A portal or the waypoint map asks the host
## (AreaManager.go_to -> request_travel), and the host sends everyone there with the dungeon
## instance's seed, so every machine builds the same dungeon and the same enemies.
##
## Enemies: every machine spawns them (EnemySpawner calls enemy_spawned). On a client each one is
## a remote copy (AI halted, no skills of its own) until the host's list arrives: the copies the
## host also has are matched by kind and spawn point, the ones it doesn't have are removed, and the
## ones only it has are spawned from the list. After that the host sends positions, health, attacks,
## and every skill cast, which the copy replays for show (EnemyBase.is_remote: it deals nothing).
##
## Damage always goes to the owner, and the owner sends the health back to everyone
## (HealthComponent.remote_damage / apply_remote). Only real hits are forwarded (hit_source):
##   a player's skill on a client's copy of an enemy   -> the host applies it
##   an enemy's hit on the host's copy of a player     -> that player's machine applies it
## Anything else that hurts (floor hazards, a lock's punishment) each machine works out for its
## own player only, so nothing lands twice.
##
## Each player's gear and skills are sent again whenever they change (_p_loadout), and the others
## rebuild their copy: a new character equips and sockets in play, after the lobby's snapshot.
##
## Loot is shared: only the host rolls item drops, every machine shows the same ones, and the
## first player to take one has it (it goes from everyone's floor). Barrels and chests open for
## everyone. Credits are still each player's own.
##
## Landed hits and kill credit: the host tells a player which of their hits (by number) landed,
## not absorbed by a lock, and whether it killed (_e_landed). Only then does that player's machine
## give what a landed hit gives (leech, life and mana on hit) and run the skill's on-kill supports
## (Explode on Kill, Tremor Chain). Their effects are shown on the other machines with show_impact.
##
## Events the host runs for anyone (event_send): a ward beacon stays dark while any player still
## needs it, and lighting it counts for everyone there.
##
## Visitor pass (visiting): a player taken somewhere they couldn't have reached themselves keeps
## playing, but nothing there unlocks for them: no waypoint, no last town, no cleared stop.
##
## Locks and other traits: the host's judge every player's hits (_e_hit, from HitFacts), and the
## copies only show what they say, their tags, ports, forms and blasts (EnemyTrait "Co-op").
##
## Traits notice any player (EnemyTrait.player_within); a PAGED lock hears what guests' scripts
## hold (_p_refs); a Null Echo sees guests' casts (player_cast); Handshake sees a guest's shield
## (_p_state's `shielded`).
##
## Act V's pull requests (KernelDirector): each player answers their own card; the host waits to
## travel while anyone has one open (_p_state's `answering`), and applies the enemy-side root and
## merged Null lines of every player here to its enemies (party_kernel, from the loadouts). A
## guest's TERMINATE champion is spawned by the host (KernelDirector.coop_message "defend").
##
## Not synced yet: Diff's charging orb, the convoy's and the dock's wave fights, quests, joining
## mid-game.

## Another player's character cast `action` here (its copy replayed it). A Null Echo watches
## these as it watches our own casts (GameEvents "cast").
signal player_cast(player: Node3D, action: StringName)
signal roster_changed
signal hosts_changed
## The session is over on this machine (the host left, or we were refused). `reason` may be "".
signal session_closed(reason: String)
signal join_failed(reason: String)

const PORT := 24547
const DISCOVERY_PORT := 24548
const GAME_TAG := "codebreak_requiem_coop"
## Bumped whenever the messages change: a host refuses a player on another number.
const PROTOCOL := 12
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
const ENEMIES_PER_PACKET := 50           # enemy positions per _e_state packet (under the MTU)
const SNAP_DISTANCE := 5.0               # a copy further than this from the truth jumps there
const UNMATCHED_GRACE := 2.5             # seconds a client's own extra enemy may wait for the host's
const MATCH_RADIUS := 1.0                # metres between a copy's and the host's spawn point
const MAX_DAMAGE := 10000000.0           # a hit reported as bigger than this is thrown away
const NET_ID := &"coop_id"               # meta on an enemy: its id in this area, the same everywhere
const NET_ENTRY := &"coop_entry"         # meta on the host's enemies: how to build it elsewhere
const NET_BOOST := &"coop_boost"         # meta on an enemy: every EnemySpawner.empower it was given
const LOOT_ID := &"coop_loot"            # meta on a shared drop: its id, the same everywhere
## One colour per player, by the order they joined: their ring, name plate and minimap marker.
const PLAYER_COLOURS: Array[Color] = [Color(0.0, 0.90, 1.0), Color(1.0, 0.82, 0.30),
		Color(0.45, 1.0, 0.55), Color(1.0, 0.50, 0.85)]

enum Hit { NONE, PLAYER, ENEMY }
## What is dealing damage right now (set by SkillBehavior.hit and EnemyBase's swing just around
## take_damage). Only these are sent to the owner; see the header.
var hit_source := Hit.NONE
## The player (peer id) whose hit is lowering an enemy's health right now, 0 = no player's. Set
## just around the damage (SkillBehavior.hit, _e_hit) and around a copy's health update
## (_e_health, which carries it), so DamageNumbers can tell our hits from another player's.
var damage_by := 0
## What the host's traits may know about the hit being sent right now (SkillBehavior.hit sets it
## for a hit on a copy of the host's enemy; _e_hit carries it).
var hit_facts: HitFacts

var active := false                      # in a session (the lobby's room, or the game)
var in_game := false
## The main menu's LOBBY was pressed: Character Select goes to the lobby instead of the game.
var picking := false
var notice := ""                         # why the last session ended, for the main menu
var roster: Dictionary = {}              # peer id -> {name, class_id, rank, loadout}
var start_town := ""                     # the host's last town: where the party starts
var travelling := false                  # go_to is running for a trip the host sent
## This player was taken somewhere they couldn't have reached themselves: nothing here unlocks
## for them (Waypoints.arrived / clear_stop, TownArea._remember_town). See _set_visiting.
var visiting := false
var _told_visiting := false
## This player has a card open the game can't pause for (the Null's PullRequestCard): sent with
## _p_state, so the host holds the party's travel and the others see ANSWERING over them.
var answering := false

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
var _answering: Dictionary = {}          # peer id -> true while their PullRequestCard is open (_p_state)
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
var _loadout_send_in := 0.0              # > 0: our gear or skills changed, send them when this runs out

const LOADOUT_SEND_DELAY := 0.6
const MAX_LOADOUT_BYTES := 262144        # a loadout bigger than this is thrown away


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS       # a paused menu never stops the session
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_host_gone)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	get_tree().node_added.connect(_on_node_added)


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
		"rank": Ranks.name_of_save(data), "loadout": loadout}


## A player's rank as it is now: from their live loadout once in game (it follows exams passed
## mid-session), else what the lobby was told.
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
	_refs.clear()                                  # (the ids were this area's)
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
	for id: int in _players.keys():                # someone left: their copy goes
		if not roster.has(id):
			if is_instance_valid(_players[id]):
				_players[id].queue_free()
			_players.erase(id)
			_player_goal.erase(id)
			_answering.erase(id)                   # their card can't hold the party up any more


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
	# Gear and skills change in play (a new character has nothing equipped until they do it
	# themselves): the others rebuild their copy of us whenever they do
	mine.equipment.equipment_changed.connect(_loadout_changed)
	mine.skills.changed.connect(_loadout_changed)
	_loadout_changed()                             # and once now: what we have on, not the lobby's snapshot
	_set_visiting(start_town if start_town != "" else am.start_area, 1)   # the host's town may be ahead of us
	var me := my_id()
	for id: int in roster:
		if id != me:
			_spawn_remote_player(id)
	mine.camera_rig.camera.make_current()          # a copy's camera may have taken over


## Our kernel changed (a pull request answered): the others' copies, and the host's party_kernel,
## get it with the next loadout.
func kernel_changed() -> void:
	if in_game:
		_loadout_changed()


## Act V: the root lines and merged Null lines of every player in this area (ours, and each copy's
## from its loadout): {"lines": [...], "merged": [...]}. KernelDirector applies the enemy-side ones
## on the host, so every player's answers count on the enemies they share.
## `beyond_act5`: a dungeon past Act V's zones, where only the players whose ending runs kernel.gd
## everywhere (Endings.runs_everywhere, sent as kernel_everywhere) count.
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


## The other players here and their pull-request answers (from their loadouts), for the KERNEL
## card: [[name, colour, answers], ...], answers in KernelScript.NULL_LINES order ("" = not yet).
## Only players who have root (any answer, or kernel lines) are listed.
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


## The name of a player in this area with a card open (us first), or "" when nobody has one.
func who_is_answering() -> String:
	if answering:
		return peer_name(my_id()) if in_game else "you"
	for id: int in _answering:
		if _answering[id] and _players.has(id) and is_instance_valid(_players[id]) and (_players[id] as Player).visible:
			return peer_name(id)
	return ""


func _loadout_changed() -> void:
	_loadout_send_in = LOADOUT_SEND_DELAY          # a burst of changes (swapping a whole set) sends once


## Our character as it is now, in the shape the lobby sent it (LOADOUT_KEYS).
func _live_loadout() -> Dictionary:
	return loadout_of(_am.player)


## A character's gear, skills, scripts and rank as they are now: what a copy of it is built from.
func loadout_of(mine: Player) -> Dictionary:
	var out := mine.loadout_save()
	out.erase("inventory")                         # the backpack is nobody else's business
	out["script_routines"] = mine.skills.routines_to_list()
	out["kernel"] = Array(mine.skills.kernel)
	# Act V: the Null's lines this player merged run on the host's enemies too (party_kernel)
	out["kernel_merged"] = KernelScript.null_running(mine.quests)
	out["kernel_everywhere"] = Endings.runs_everywhere(mine.quests)    # after MERGE / OVERWRITE (Endings)
	out["reboot"] = Reboot.count(mine.quests)          # the host's decides how tough enemies are (Reboot)
	# ...and their answer to each request, for the partner marks on the KERNEL card
	out["kernel_answers"] = KernelScript.NULL_LINES.keys().map(func(id: String) -> String:
		return KernelScript.answer_of(mine.quests, id))
	# Our rank and script budget: a copy has no quests, and would otherwise reject our scripts
	out["limits"] = {"rank": mine.skills.rank(), "points": mine.skills.bonus_points(),
			"steps": mine.skills.bonus_steps(), "rules": mine.skills.bonus_rules()}
	out["class_id"] = String(mine.class_data.id) if mine.class_data != null else ""
	return out


@rpc("any_peer", "call_remote", "reliable")
func _p_loadout(loadout: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id) or var_to_bytes(loadout).size() > MAX_LOADOUT_BYTES:
		return
	var info: Dictionary = roster[id]
	if str(loadout.get("class_id", "")) != str(info.get("class_id", "")):
		return                                     # a character doesn't change class mid-game
	if (info.get("loadout", {}) as Dictionary).hash() == loadout.hash() and _players.has(id):
		return                                     # nothing new
	info["loadout"] = loadout
	if not in_game or _am == null or not is_instance_valid(_am):
		return
	# Build the copy again with the new gear, where the old one stood and as hurt as it was
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
		p.health.apply_remote(minf(life, p.health.current_health), false)   # the same wounds, not a new hit


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
	_add_ring(p, player_colour(id))
	_show_remote(p, false)                         # until its first position says where it is


## A glowing ring on the floor under another player's character, in their colour.
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


## This machine's own character: ours in co-op even while it is down (a dead player leaves the
## "players" group, and the first one left in it would be someone else's copy).
func own_player(tree: SceneTree) -> Node:
	if in_game and _am != null and is_instance_valid(_am) and is_instance_valid(_am.player):
		return _am.player
	return tree.get_first_node_in_group("players") if tree != null else null


## The colour of a player in this session (PLAYER_COLOURS, by the order they joined).
func player_colour(id: int) -> Color:
	var ids := roster.keys()
	ids.sort()
	return PLAYER_COLOURS[maxi(ids.find(id), 0) % PLAYER_COLOURS.size()]


## The other players' characters that are in this area now, for the minimap and the name plates:
## [[Player, name, colour, answering], ...] (answering: their PullRequestCard is open). Empty in
## single player.
func others_here() -> Array:
	var out: Array = []
	if not in_game:
		return out
	for id: int in _players:
		var p = _players[id]
		if is_instance_valid(p) and (p as Player).visible:
			out.append([p, peer_name(id), player_colour(id), bool(_answering.get(id, false))])
	return out


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
	# Two players in the same doorway ask twice: the first one decides
	if travelling or Time.get_ticks_msec() - _last_travel_msec < 1500:
		return
	# Someone is answering the Null (PullRequestCard): the party waits for them
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


## The host held our trip (someone is answering a pull request): say why.
@rpc("authority", "call_remote", "reliable")
func _travel_held(text: String) -> void:
	if text.length() < 200:
		QuestItems.toast(get_tree(), text, Color(1.0, 0.82, 0.30))


## `asker`: the player whose portal, waypoint map or route terminal started the trip.
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
	while _am.is_busy():                           # still arriving from the last trip
		await get_tree().process_frame
		if _am == null or not is_instance_valid(_am):
			return
	if dungeon_level > 0:
		if is_host():
			WorldState.prepare_dungeon(scene_path, dungeon_level, inst_id)
		else:
			WorldState.adopt(inst_id, scene_path, dungeon_level, rng_seed, killed)
	_set_visiting(scene_path, asker)               # before we leave: it looks at this area's portals
	travelling = true
	await _am.travel_now(scene_path, spawn_id)
	travelling = false


## ---- The visitor pass ----
## Decides, as the party leaves for `dest`, whether this player is only visiting there. They are
## not when any of these holds:
##   they have that waypoint already, or it is their own last town or the game's first area
##   they started the trip themselves (their own doors, map and terminal let them through)
##   it is a convoy stop their own route terminal would sail to
##   a portal in the area they stand in leads there and isn't sealed for them
## Once visiting, walking on doesn't end it: only arriving somewhere of the first kind does.
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


## A convoy stop's exit was walked through (Portal.clears_stop): it is cleared for every player
## there who isn't only visiting, not just the one who touched the portal.
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


## ---- Staying in the same area ----
## Once a second the host says where the party is (_h_where). A guest that isn't there, or has
## no area at all, for RESYNC_AFTER checks in a row (and isn't mid-trip) goes there by itself.
## That covers a trip that arrived while this machine was still loading the game, and anything
## else that left it behind. It gives up after RESYNC_TRIES on one area (the area won't load
## here: a different build of the game) and says so.
const RESYNC_AFTER := 3
const RESYNC_TRIES := 3
var _where: Dictionary = {}              # the party's area: {path, spawn, level, inst, seed}
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


## One line into user://coop_log.txt (and the output), with the time and which side wrote it:
## what this machine was told and did. For working out a session that went wrong afterwards.
func note(text: String) -> void:
	var line := "%s [%s] %s" % [Time.get_time_string_from_system(), "host" if is_host() else "guest", text]
	print("[Coop] ", line)
	var f := FileAccess.open("user://coop_log.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://coop_log.txt") else FileAccess.WRITE)
	if f != null:
		if f.get_length() > 400000:              # start over rather than grow for ever
			f.resize(0)
		f.seek_end()
		f.store_line(line)
		f.close()


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
	note("area loaded: %s" % scene_path.get_file())
	if visiting and not _told_visiting:
		_told_visiting = true
		QuestItems.toast(get_tree(), "VISITING\nThis area is ahead of your own progress: nothing here unlocks for you.",
				Color(1.0, 0.82, 0.30))
	if is_host() and Waypoints.normalize(str(_where.get("path", ""))) != Waypoints.normalize(scene_path):
		_where = {"path": scene_path, "spawn": &"default", "level": 0, "inst": 0, "seed": 0}   # the starting town
	if is_host():
		for id: int in _waiting.keys():            # players who got here before us
			if _waiting[id] == scene_path:
				_send_enemy_list(id)
	else:
		_e_ready.rpc_id(1, scene_path)


# ---------- PLAYERS ----------
## `shielded`: the owner's character has a barrier or guard up now (HealthComponent.is_shielded).
## Their copy here says so too, for the host's HandshakeLock ("take its slam with a shield up").
## `answering_now`: their PullRequestCard is open (travel waits; ANSWERING over their head).
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
		player_cast.emit(p, action)


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
				_e_health.rpc(id, current, damage_by))     # and whose hit it was (DamageNumbers)
		e.ai.attack_requested.connect(func(_target: Node3D) -> void:
			if active:
				_e_attack.rpc(id))
		if _area_live:                             # spawned mid-fight (a summon, a wave): tell everyone
			_announce_enemy.call_deferred(id)
		return
	# A client: a remote copy from the start
	e.ai.halt()                                    # the host thinks for it
	e.is_remote = true                             # its casts are replayed, for show only (_e_cast)
	_switch_off_logic(e)                           # its AI, skills, boss parts: see COPY RUNS NO LOGIC
	e.health.set_process(false)
	e.health.remote_damage = func(amount: float, ignore_armour: bool) -> void:
		if hit_source == Hit.PLAYER and e.has_meta(NET_ID):    # our own skill landed
			_hit_seq += 1                          # its number: the host answers it if it lands (_e_landed)
			_sent_seq = _hit_seq
			_sent_for = int(e.get_meta(NET_ID))
			var facts := hit_facts.to_dict() if hit_facts != null else {}
			if hit_facts != null and hit_facts.loop_id != "":
				_my_loops[hit_facts.loop_id] = true    # the host hears when it ends (_loop_done)
			_e_hit.rpc_id(1, _sent_for, amount, ignore_armour, _hit_seq, facts)
	if not _adopting.is_empty():
		_enemies[int(_adopting.id)] = e
		e.set_meta(NET_ID, int(_adopting.id))
	else:
		_unmatched.append({"enemy": e, "def": def.id, "pos": e.global_position, "at": Time.get_ticks_msec()})


# ---------- A COPY RUNS NO LOGIC ----------
## On a client, an enemy is the host's: the copy here only shows it. So every script under a copy
## that comes from systems/enemies/ (its AIComponent, EnemySkills, boss parts like LoopCharger,
## WovenTraps, Summoner, and whatever is put there next) is switched off, at spawn and whenever
## one is added to it later (_on_node_added). Off unless synced: what the host's one does reaches
## the copy as messages (_e_cast, _e_state, enemy_send -> coop_message), never by running here.
## That includes its traits (locks, Firewalled, Reflector...): the host's judge every player's
## hits (_e_hit) and tell the copies what to show (EnemyTrait "Co-op"). Two kinds stay on:
##   COPY_KEEPS   helpers in that folder that only draw (death glitch, outlines, lock blasts)
##   COOP_AWARE   a trait that runs its own co-op (the Warden's ChallengeLock)
const COPY_KEEPS: Array[String] = ["enemy_silhouette.gd", "glitch_death.gd", "glitch_burst.gd", "lock_blast.gd"]
const ENEMY_LOGIC := "res://systems/enemies/"


func _is_enemy_logic(n: Node) -> bool:
	var s := n.get_script() as Script
	if s == null or (n is EnemyTrait and (n as EnemyTrait).coop_aware()):
		return false                               # a trait that runs its own co-op (the Warden's)
	var path := s.resource_path
	return path.begins_with(ENEMY_LOGIC) and not path.get_file() in COPY_KEEPS


func _switch_off_logic(e: EnemyBase) -> void:
	for n in e.find_children("*", "", true, false):
		if _is_enemy_logic(n):
			n.process_mode = Node.PROCESS_MODE_DISABLED


## A node joined the tree: a logic script added to a copy later (a phase's new part) is off too.
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
	entry["boost"] = e.get_meta(NET_BOOST, [])     # a wave's extra health and armour (EnemySpawner.empower)
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
	_tags_sent.clear()                             # the newcomer gets every lock's tag again (_send_tags)
	var entries: Array = []
	for id: int in _enemies.keys():
		var e = _enemies[id]
		if not is_instance_valid(e) or not (e as Node).is_inside_tree() or e.health.current_health <= 0.0:
			_enemies.erase(id)                     # removed after spawning (killed on an earlier visit), or dead
			continue
		entries.append(_entry_of(e))
	_e_list.rpc_id(peer, _area_path, entries)
	for id: int in _loot_data.keys():              # and the drops lying on the floor
		if not is_instance_valid(_loot.get(id)):
			_loot_data.erase(id)
			_loot.erase(id)
	_l_list.rpc_id(peer, _area_path, _loot_data.values())


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
		e.health.apply_remote(hp, false)           # hurt before we arrived: no number for it


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


## A client's skill hit an enemy: the host applies it (and its health goes back to everyone).
## A client's hit on the host's enemy. The host's traits judge it, as SkillBehavior.hit does a
## hit made here: from the hit's facts (HitFacts), with the client's character copy as caster.
## `seq`: the client's number for this hit, sent back with _e_landed if it lands (not absorbed).
## While the traits run, anything they do to a player (a Reflector's zap) is a real enemy hit,
## sent on to that player's machine.
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
			HitFacts.remote_loop(info.facts.loop_id, true)   # running until the client says (_loop_done)
	var was_alive := e.health.current_health > 0.0
	var traits: Array = e.traits.filter(func(t) -> bool: return is_instance_valid(t))
	hit_source = Hit.ENEMY
	damage_by = from                               # (a lock may release held damage here: theirs)
	for t: EnemyTrait in traits:
		t.modify_incoming(info)
	damage_by = 0
	hit_source = Hit.NONE
	if info.cancelled:
		return
	if info.absorbed:                              # a lock took it: it landed, for nothing
		if was_alive:
			info.landed = true
			_after_hit(traits, info)
		return
	damage_by = from                               # their hit: an ally's number here and elsewhere
	info.dealt = e.health.take_damage(info.damage, ignore_armour)
	damage_by = 0
	if info.dealt <= 0.0:
		return
	info.landed = true
	info.killed = e.health.current_health <= 0.0
	_after_hit(traits, info)
	# It landed: the client gets what a landed hit gives, and if THIS hit killed, its on-kill supports
	_e_landed.rpc_id(from, seq, info.dealt, was_alive and info.killed)


func _after_hit(traits: Array, info: HitInfo) -> void:
	hit_source = Hit.ENEMY
	for t: EnemyTrait in traits:
		if is_instance_valid(t):
			t.after_hit(info)
	hit_source = Hit.NONE


# ---------- A CLIENT'S LOOPS ----------
## The host's locks ask whether a loop is still repeating (HitFacts.loop_running): for a client's
## loop the client says when it has finished. _my_loops: the loops of ours the host has seen.
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


# ---------- WHAT A CLIENT'S SCRIPTS HOLD ----------
## A PAGED lock stays in memory while any player's script registry holds it (PagedLock). A
## client's registries are on its machine, so it tells the host which of the host's enemies
## with a PagedLock its scripts hold, whenever that changes (checked REFS_EVERY seconds).
const REFS_EVERY := 0.5
var _refs: Dictionary = {}               # host: peer id -> PackedInt32Array of enemy ids it holds
var _refs_sent := PackedInt32Array()     # client: what we told the host last
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


## The host: another player's script holds `enemy` (PagedLock._is_referenced).
func referenced_elsewhere(enemy: Node) -> bool:
	if not in_game or not is_host() or not enemy.has_meta(NET_ID):
		return false
	var id := int(enemy.get_meta(NET_ID))
	for peer: int in _refs:
		if id in (_refs[peer] as PackedInt32Array):
			return true
	return false


## The damage being shown now is another player's hit, not ours (damage_by). For DamageNumbers.
func damage_by_other() -> bool:
	return in_game and damage_by != 0 and damage_by != my_id()


# ---------- PLAYER TO PLAYER: INFO AND TRADE (PartyMenu) ----------
## Another player's character sheet, as their own machine has it (their copy here has no level,
## attributes or quests): asked for with ask_info, answered by my_sheet on theirs.
signal player_info(peer: int, info: Dictionary)
## A trade message from another player (PartyMenu: "ask", "answer", "offer", "accept", "commit",
## "cancel"). Straight from one player's machine to the other's.
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


## Our character sheet, for another player's CharacterPanel: who we are, and every stat now.
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


## A player's character on this machine: ours for our own id, else that player's copy (or null).
func player_node(peer: int) -> Node3D:
	if peer == my_id():
		return own_player(get_tree()) as Node3D
	var p = _players.get(peer)
	return p as Node3D if is_instance_valid(p) else null


# ---------- HOW A CLIENT'S HIT LANDED (and kill credit) ----------
## The host answers every hit of a client's that really landed (_e_landed): not one its traits
## absorbed (a closed port...), which it never answers. Only then does the client get what a
## landed hit gives (SkillBehavior.landing_rewards: leech of the host's damage, life and mana on
## hit, a rule's barrier and guard), and, if that hit killed, the skill's on-kill supports.
## _my_hits: hit number -> [SkillCast, target, HitInfo, msec] for every hit of ours the host may
## still answer. Kept per HIT, not per enemy: a slam that kills a pack is answered once per enemy,
## after the first kill's explosion has already hit the rest, and each answer must find the slam's
## own hit (depth 0, so it explodes), not the explosion's (depth 1, which doesn't).
var _my_hits: Dictionary = {}
var _hit_seq := 0                        # the last number given to a hit we sent (_e_hit)
var _sent_seq := 0                       # the hit just sent, waiting for my_hit to file it
var _sent_for := 0                       # ...and the enemy it was on
const HIT_KEEP_MSEC := 8000              # an unanswered hit is forgotten after this


## SkillBehavior.hit, after a hit of ours landed here. On a client the host decides how it
## landed, so the hit is kept until the host says so (_e_landed), or forgotten (absorbed).
func my_hit(target: Node, cast: SkillCast, info: HitInfo) -> void:
	if not in_game or is_host() or not target.has_meta(NET_ID):
		return
	var seq := _sent_seq
	_sent_seq = 0
	if seq == 0 or _sent_for != int(target.get_meta(NET_ID)):
		return                                     # not the hit remote_damage just sent
	var now := Time.get_ticks_msec()
	if _my_hits.size() > 128:                      # hits the host absorbed (never answered)
		for s: int in _my_hits.keys():
			if now - int(_my_hits[s][3]) > HIT_KEEP_MSEC or not is_instance_valid(_my_hits[s][1]):
				_my_hits.erase(s)
	_my_hits[seq] = [cast, target, info, now]


## The host: our hit number `seq` landed for `dealt` (after its armour), and `killed` its enemy
## or not. What a landed hit gives comes now; a kill runs the skill's on-kill supports here, as a
## kill of our own would in single player (the explosion's own hits go to the host like any other).
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


## A support's burst at a point (Explode on Kill, Tremor Chain), for the other machines: their
## copy of the caster deals no hits, so it never sets these off itself.
func show_impact(caster: Node, pos: Vector3, radius: float, colour: Color, accent: Color) -> void:
	if in_game and _area_live and caster is Player and not (caster as Player).is_remote:
		_fx_impact.rpc(_area_path, pos, radius, colour, accent)


@rpc("any_peer", "call_remote", "reliable")
func _fx_impact(scene_path: String, pos: Vector3, radius: float, colour: Color, accent: Color) -> void:
	if not _area_live or scene_path != _area_path or _am == null or not is_instance_valid(_am) \
			or not pos.is_finite() or not is_finite(radius) or not roster.has(multiplayer.get_remote_sender_id()):
		return
	ImpactEffect.spawn(_am.player.get_parent(), pos, clampf(radius, 0.1, 40.0), colour, accent)


# ---------- WHAT THE HOST'S TRAITS SHOW ----------
## Their tags (tag_state: ECHO's learned pattern, OVERFLOW's 3/5...) go to the copies whenever
## they change, checked TAGS_EVERY seconds. _tags_sent: trait instance id -> the text last sent.
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


## LockBlast's ring and orb, drawn on the other machines for show: the host's deal the hits.
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


# ---------- SHARED LOOT ----------
var _loot: Dictionary = {}               # loot id -> LootPickup, on every machine
var _loot_data: Dictionary = {}          # host: loot id -> {id, item (ItemInstance.to_dict), pos}
var _next_loot := 1
var _opening_prop := false               # a prop is opening because another machine said so


## False on a client: only the host rolls item drops (DungeonPopulator._drop_item).
func rolls_loot() -> bool:
	return not in_game or is_host()


## The host placed a drop (DungeonPopulator._place_pickup): every machine gets the same one.
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


## LootPickup.try_pickup in co-op: ask the host. Whoever it reaches first has the item.
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
	if _loot_data.has(id):                         # still there: nobody was quicker
		_loot_data.erase(id)
		_l_taken.rpc(id, peer)


## The drop is gone from every floor, and in `peer`'s backpack.
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
		(pickup as LootPickup).queue_free()        # no room after all: back on the floor, for anyone
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


## A barrel broke or a chest opened here (DungeonPopulator._place_prop): it does everywhere.
## Each player gets its credits; the host's copy drops the items, for all.
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


# ---------- EVENTS THE HOST RUNS FOR EVERYONE ----------
var _events: Dictionary = {}             # key -> the node in this area that takes its messages


## A world event in this area (a WardBeacon) that talks to its copies on the other machines:
## `what` and `args` arrive at coop_message(what, args, from) on the node registered under the
## same key there. From the host, peer 0 = every other machine; a client always talks to the host.
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


# ---------- ENEMY PARTS THE HOST OWNS (locks, boss parts) ----------
## A part of an enemy on the host talks to its copies, and a copy talks to the host's: its own
## `what` and `args`, delivered to coop_message(what, args, from) on every node of the same enemy
## that has one (its traits, and boss parts like LoopCharger inside its model). So each part's
## `what` names start with its own prefix ("loop_", "weave_"...): every part hears every message.
## From the host, peer 0 = every other machine. From a client it always goes to the host.
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
		return                                     # clients hear the host, the host hears its players
	var e := _enemies.get(id) as EnemyBase
	if e == null or not is_instance_valid(e) or what.length() > 32 or args.size() > 8:
		return
	for n in e.find_children("*", "", true, false):  # its traits, and the parts in its model
		if n.has_method("coop_message"):
			n.coop_message(what, args, from)


## The machine a player's character belongs to (ours for our own).
func player_peer(p: Node) -> int:
	for id: int in _players:
		if _players[id] == p:
			return id
	return my_id()


func peer_name(id: int) -> String:
	return str((roster.get(id, {}) as Dictionary).get("name", "Player"))


## `by`: the player whose hit it was (0 = no player's): our own hits' numbers look as always,
## another player's look like an ally's (DamageNumbers, damage_by_other).
@rpc("authority", "call_remote", "reliable")
func _e_health(id: int, current: float, by: int) -> void:
	var e := _enemies.get(id) as EnemyBase
	if e != null and is_instance_valid(e):
		damage_by = by
		e.health.apply_remote(current)             # at 0 it dies here too (EnemyBase._on_died)
		damage_by = 0
		if current <= 0.0:                         # (kept in _enemies: its last words still come)
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


## EnemySkills._cast on the host: the clients' copies cast the same skill, facing the same way,
## for show (the clip, the sound, the projectiles and effects; EnemySkills.remote_cast).
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


# ---------- EVERY FRAME ----------
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
		_check_my_refs(delta)                      # what our scripts hold, for PAGED locks
	if is_host() and in_game and _area_live:
		_send_tags(delta)                          # the locks' tags, to the copies
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
		if p == null or not is_instance_valid(p) or not p.is_inside_tree():
			continue                               # (quitting, or being rebuilt)
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
			_enemy_goal.erase(id)                  # arrived: nothing to do until the host moves it

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
			continue                               # killed on an earlier visit: removed, freed this frame
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
	# In packets of ENEMIES_PER_PACKET (21 bytes each): one unreliable packet bigger than the
	# network's MTU (~1400 bytes) is split, and lost whole if any piece is
	for start in range(0, ids.size(), ENEMIES_PER_PACKET):
		var end := mini(start + ENEMIES_PER_PACKET, ids.size())
		_e_state.rpc(ids.slice(start, end), positions.slice(start, end), rotations.slice(start, end),
				states.slice(start, end))
