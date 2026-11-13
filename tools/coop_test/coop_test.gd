extends Node
## Tests a real co-op session with two copies of the game on one PC.
## Run it twice, one after the other (headless is fine):
##     godot --headless res://tools/coop_test/coop_test.tscn -- host
##     godot --headless res://tools/coop_test/coop_test.tscn -- join
## Each seats a made-up level-1 character in slot 98 (host) / 99 (join), which no Character Select
## card shows, so no real character is loaded. Then, through the same Coop calls the lobby makes:
##   1. the guest joins and the host starts the game: both load the same town
##   2. each sees the other's character there
##   3. the host walks the party into a dungeon: both build it, and the guest's enemies are the host's
##   4. a guest's hit lowers the enemy's health on the host, and the host's number comes back
##   5. the host's enemy moves on the guest's screen
## Prints [COOP host] / [COOP join] lines; "ALL PASSED" at the end, or each FAIL.

const DUNGEON := "res://scenes/map/dungeon/act_1_map_1.tscn"
const APPROACH := "res://scenes/map/dungeon/act_2_checkpoint_approach.tscn"
const PatchPanelScript := preload("res://scenes/map/town/convoy/patch_panel.gd")

var _role := "host"
var _warden_run := false
var _keep_alive := false
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a == "join":
			_role = "join"
		elif a == "warden":
			_warden_run = true
	_run.call_deferred()


func _run() -> void:
	# Outlive the scene changes: an empty node becomes "the current scene" that START replaces
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	_seat("gladiator" if _role == "host" else "raider", 98 if _role == "host" else 99)

	# 1. Lobby: host / join, then START
	if _role == "host":
		_check("hosting", Coop.host() == OK)
		await _until(func() -> bool: return Coop.roster.size() == 2, 60.0)
		_check("the guest is in the party", Coop.roster.size() == 2)
		Coop.start_game()
	else:
		_check("connecting", Coop.join("127.0.0.1") == OK)
		await _until(func() -> bool: return Coop.active and Coop.roster.size() == 2, 30.0)
		_check("in the host's party", Coop.active and Coop.roster.size() == 2)
		await _until(func() -> bool: return Coop.in_game, 60.0)
	_check("the game started", Coop.in_game)
	await _until(_arrived, 60.0)
	var town := _am().current_scene_path() if _am() != null else ""
	_check("loaded a town (%s)" % town.get_file(), _arrived())

	# 2. The other player's character
	await _until(func() -> bool: return _other() != null and _other().visible, 20.0)
	var other := _other()
	_check("the other player is here", other != null and other.visible)
	if other != null:
		_check("their copy is remote and wears a class model", other.is_remote and other.class_data != null)
		_log("me at %s, their copy at %s" % [_me().global_position, other.global_position])

	if _warden_run:
		await _warden_test()
		return _done()

	# 3. Into a dungeon together
	if _role == "host":
		await _wait(2.0)
		_am().go_to(DUNGEON, &"default", 1)
	await _until(func() -> bool: return _arrived() and _am().current_area.get("instance") != null, 90.0)
	var in_dungeon := _arrived() and _am().current_area.get("instance") != null
	_check("in the dungeon (%s)" % (_am().current_scene_path().get_file() if _am() != null else "?"), in_dungeon)
	if not in_dungeon:
		return _done()
	var inst: DungeonInstance = _am().current_area.get("instance")
	_log("instance %d seed %d" % [inst.id, inst.rng_seed])
	if _role == "join":
		await _until(func() -> bool: return Coop._list_done, 30.0)
		_check("the host's enemy list arrived", Coop._list_done)
	await _wait(1.5)
	var local := get_tree().get_nodes_in_group("enemies").size()
	_log("enemies: %d synced, %d in the area" % [Coop._enemies.size(), local])
	_check("there are synced enemies", Coop._enemies.size() > 0)
	_check("every enemy here is one of the host's", Coop._enemies.size() == local)
	await _until(func() -> bool: return _other() != null and _other().visible, 20.0)
	_check("the other player is in the dungeon too", _other() != null and _other().visible)

	# 4 + 5. One enemy (the lowest id, the same on both): the host stands by it so it fights,
	# the guest hits it
	var ids := Coop._enemies.keys()
	ids.sort()
	var id: int = ids[0]
	var e: EnemyBase = Coop._enemies[id]
	var start_pos := e.global_position
	var full := e.health.current_health
	_log("enemy %d %s at %s, %.0f life" % [id, e.display_name, start_pos, full])
	if _role == "host":
		_stand(_spot_beside(start_pos))
		await _wait(3.0)
		_log("here the enemy is in state %d, at %s, facing %.2f" % [e.ai.state, e.global_position, e.global_rotation.y])
		await _until(func() -> bool: return is_instance_valid(e) and e.health.current_health < full, 25.0)
		_check("the guest's hit landed here (%.0f -> %.0f)" % [full, e.health.current_health if is_instance_valid(e) else -1.0],
				not is_instance_valid(e) or e.health.current_health < full)
		await _wait(6.0)
	else:
		var start_rot := e.global_rotation.y
		await _wait(5.0)                             # the host walks over, the enemy turns on it
		_log("here the enemy is in state %d, at %s, facing %.2f" % [e.ai.state, e.global_position, e.global_rotation.y])
		_check("the host's enemy moved or turned here", is_instance_valid(e)
				and (e.global_position.distance_to(start_pos) > 0.05 or e.ai.state != AIComponent.State.IDLE
				or absf(angle_difference(e.global_rotation.y, start_rot)) > 0.05))
		Coop.hit_source = Coop.Hit.PLAYER            # what SkillBehavior.hit does around a real hit
		e.health.take_damage(12.0, true)
		Coop.hit_source = Coop.Hit.NONE
		_check("nothing changes here until the host answers", is_equal_approx(e.health.current_health, full))
		await _until(func() -> bool: return not is_instance_valid(e) or e.health.current_health < full, 10.0)
		_check("the host's answer lowered it (%.0f -> %.0f)" % [full, e.health.current_health if is_instance_valid(e) else -1.0],
				not is_instance_valid(e) or e.health.current_health < full)
		await _wait(3.0)
	_done()


## `-- host warden` / `-- join warden`: the Perimeter Warden's challenge with a party (ChallengeLock's
## CO-OP notes). Only the Warden's lock runs (its AI and the other enemies are frozen on the host),
## and both characters are topped up every frame.
##   round 1  only the guest stands by it: the guest alone gets the panel, the fight isn't paused,
##            a wrong answer hurts the guest, the fix opens the port on both machines
##   round 2  only the host stands by it: now the host gets the panel; closing it hurts the host
func _warden_test() -> void:
	if _role == "host":
		await _wait(2.0)
		_am().go_to(APPROACH, &"approach_in", 21)
	await _until(func() -> bool: return _arrived() and Waypoints.normalize(_am().current_scene_path()) == APPROACH, 90.0)
	_check("at Checkpoint Approach", _arrived() and Waypoints.normalize(_am().current_scene_path()) == APPROACH)
	_keep_alive = true
	if _role == "host":
		for e in get_tree().get_nodes_in_group("enemies"):
			if _lock_of(e) == null:
				e.process_mode = Node.PROCESS_MODE_DISABLED
			else:
				(e.get("ai") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	else:
		await _until(func() -> bool: return Coop._list_done, 30.0)
	await _wait(1.0)
	var warden: EnemyBase = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if _lock_of(e) != null:
			warden = e
	_check("the Perimeter Warden is here", warden != null)
	if warden == null:
		return
	var lock := _lock_of(warden)
	var near := warden.global_position + warden.global_basis * Vector3(0, 0.2, 3)
	var far := warden.global_position + warden.global_basis * Vector3(0, 0.2, 22)
	var hp := _me().health

	# Round 1: the guest answers
	_stand(near if _role == "join" else far)
	if _role == "join":
		await _until(func() -> bool: return _panel() != null, 25.0)
		var panel = _panel()
		_check("the guest gets the panel (%s)" % lock.challenge, panel != null)
		_check("the fight isn't paused", not get_tree().paused)
		if panel == null:
			return
		_keep_alive = false
		var before := hp.current_health
		panel._on_run()
		_check("a wrong answer hurts the guest (%.0f -> %.0f)" % [before, hp.current_health], hp.current_health < before)
		_keep_alive = true
		_check("the port is still shut", not lock.is_open())
		_fix(panel.puzzle, lock.challenge)
		panel._on_run()
		await _until(func() -> bool: return lock.is_open(), 8.0)
		_check("solved: the port opens on the guest's copy", lock.is_open())
		_stand(far)
		await _wait(lock.open_time + 16.0)
		_check("round 2 isn't the guest's: no panel here", _panel() == null)
	else:
		await _until(func() -> bool: return lock.challenge != "", 25.0)
		_check("the host's lock asked the guest (peer %d)" % lock._asked_peer, lock.challenge != "" and lock._asked_peer != 1)
		_check("no panel on the host", _panel() == null)
		await _until(func() -> bool: return lock.is_open(), 30.0)
		_check("the guest's answer opened the port on the host", lock.is_open())
		# Round 2: the host answers
		_stand(near)
		await _until(func() -> bool: return _panel() != null, lock.open_time + 20.0)
		_check("next round the host gets the panel (%s)" % lock.challenge, _panel() != null and lock._asked_peer == 1)
		_check("the fight isn't paused", not get_tree().paused)
		if _panel() != null:
			_keep_alive = false
			var before := hp.current_health
			_panel().close()
			_check("walking away hurts the host (%.0f -> %.0f)" % [before, hp.current_health], hp.current_health < before)
			_keep_alive = true
			_check("and the port stays shut", not lock.is_open())
		await _wait(3.0)


func _lock_of(e: Node) -> ChallengeLock:
	for t in e.get("traits"):
		if t is ChallengeLock:
			return t
	return null


## A spot 1.6 m from `pos` that has floor under it and no wall between it and `pos` (the dungeon
## is random: a fixed offset sometimes lands inside a wall, and the enemy never sees the player).
func _spot_beside(pos: Vector3) -> Vector3:
	var space := _me().get_world_3d().direct_space_state
	for i in 8:
		var at := pos + Vector3(1.6, 0, 0).rotated(Vector3.UP, i * TAU / 8.0)
		var sight := PhysicsRayQueryParameters3D.create(at + Vector3.UP, pos + Vector3.UP, 1)
		var floor_under := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 2.0, 1)
		if space.intersect_ray(sight).is_empty() and not space.intersect_ray(floor_under).is_empty():
			return at + Vector3.UP * 0.2
	return pos + Vector3(1.6, 0.2, 0)


func _stand(at: Vector3) -> void:
	_me().global_position = at
	_me().velocity = Vector3.ZERO
	_me().reset_physics_interpolation()


func _panel():
	return get_tree().get_first_node_in_group(PatchPanelScript.GROUP)


func _process(_delta: float) -> void:
	if _keep_alive and _am() != null and is_instance_valid(_am().player):
		_am().player.health.heal(100000.0)


## The fix for each Warden puzzle, as a player would click it (as in challenge_lock_test).
func _fix(pz, id: String) -> void:
	match id:
		"w_crowd":
			pz.step("op", 3)                 # "<" -> ">="
		"w_ping":
			pz.step("count", 2)              # 2 -> 4
		"w_vitals":
			pz.step("op", -1)                # ">" -> "<"
		"w_handshake":
			pz.move(0, 1)                    # reply, sign, receive -> receive, sign, reply
			pz.move(1, 1)
			pz.move(0, 1)
		"w_identify":
			pz.step("status", 1)             # DELETED -> INBOUND


## A level-1 character of this class with its starting weapon and skill, in save-file form.
func _seat(class_id: String, slot: int) -> void:
	var c := load("res://data/classes/%s.tres" % class_id) as ClassData
	var data := {
		"version": 1, "name": "Test " + _role.capitalize(), "class_id": class_id, "level": 1, "xp": 0,
		"attributes": c.get_attributes(), "equipment": {}, "skills": [], "inventory": []}
	if c.starting_weapon != null:
		data["equipment"]["weapon"] = c.starting_weapon.id
	if c.starting_skill_gem != null:
		data["skills"] = [{"gem": c.starting_skill_gem.id, "supports": [], "action": "attack"}]
	SaveManager.begin_session(1)
	SaveManager.party.append(slot)
	SaveManager._loaded[slot] = data


func _am() -> AreaManager:
	return get_tree().get_first_node_in_group("area_manager") as AreaManager


func _arrived() -> bool:
	var am := _am()
	return am != null and am.current_area != null and not am.is_busy()


func _me() -> Player:
	return _am().player if _am() != null else null


func _other() -> Player:
	for p in Coop._players.values():
		if is_instance_valid(p):
			return p
	return null


func _until(cond: Callable, timeout: float) -> void:
	var waited := 0.0
	while waited < timeout and not cond.call():
		await get_tree().process_frame
		waited += get_process_delta_time()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	_log("%s  %s" % ["ok  " if ok else "FAIL", what])


func _log(text: String) -> void:
	print("[COOP %s] %s" % [_role, text])


func _done() -> void:
	_log("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	SaveManager.end_session()                        # nothing of the made-up character is saved on quit
	Coop.leave()
	get_tree().quit(0 if _fails == 0 else 1)
