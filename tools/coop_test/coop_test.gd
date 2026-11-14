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
## Add `warden` to both for the Perimeter Warden's challenge (_warden_test), or `locks` for the
## host judging a guest's hits through its locks (_locks_test).

const DUNGEON := "res://scenes/map/dungeon/act_1_map_1.tscn"
const APPROACH := "res://scenes/map/dungeon/act_2_checkpoint_approach.tscn"
const PatchPanelScript := preload("res://scenes/map/town/convoy/patch_panel.gd")

var _role := "host"
var _warden_run := false
var _locks_run := false
var _keep_alive := false
var _shots_dir := ""
var _host_town := ""
var _from_slot := -1
var _real_character := false
var _travel_act := ""
var _fails := 0


## The act's town scene says which act it is (TownArea.act: "I", "II"...); read from the file name.
func act_roman(act: WaypointAct) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI"][clampi(act.act_number, 0, 6)]


func _role_is(role: String, _arg: String) -> bool:
	return ("join" in OS.get_cmdline_user_args()) == (role == "join")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a == "join":
			_role = "join"
		elif a == "warden":
			_warden_run = true
		elif a == "locks":
			_locks_run = true
		elif a.begins_with("shots="):                # with real windows (no --headless)
			_shots_dir = a.trim_prefix("shots=")
		elif a.begins_with("town="):                 # the HOST's last town (a beginner joins it there)
			_host_town = a.trim_prefix("town=")
		elif a.begins_with("travel="):
			_travel_act = a.trim_prefix("travel=")
		elif a.begins_with("hostslot=") and _role_is("host", a):   # a COPY of a real save slot's data
			_from_slot = int(a.trim_prefix("hostslot="))
		elif a.begins_with("joinslot=") and _role_is("join", a):
			_from_slot = int(a.trim_prefix("joinslot="))
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
	if _arrived():
		var area := _am().current_area
		var tiles := area.find_children("*", "GridMap", true, false)
		_log("the town: %s, visible %s, %d tiles, me at %s, floor under me %s" % [area.name, area.is_visible_in_tree(),
			(tiles[0] as GridMap).get_used_cells().size() if not tiles.is_empty() else -1, _me().global_position,
			_me().is_on_floor()])
	if _real_character:                              # the scripted steps below are for the made-up characters
		await _until(func() -> bool: return _other() != null and _other().visible, 20.0)
		_check("the other player is here", _other() != null and _other().visible)
		if _travel_act != "":                        # `travel=V`: the host takes the waypoint to that act's town
			var before := _am().current_scene_path()
			if _role == "host":
				await _wait(2.0)
				for act in Waypoints.acts():
					for w in act.waypoints:
						if w.kind == Waypoint.Kind.TOWN and act_roman(act) == _travel_act:
							_log("travelling to %s (%s, spawn %s, level %d)" % [w.display_name, w.scene, w.spawn_id, w.dungeon_level])
							_am().travel(w.scene, w.spawn_id, w.dungeon_level)
			await _until(func() -> bool: return _arrived() and _am().current_scene_path() != before, 60.0)
			_check("travelled with the host (%s)" % _am().current_scene_path().get_file(),
					_arrived() and _am().current_scene_path() != before)
			var area := _am().current_area
			var tiles := area.find_children("*", "GridMap", true, false) if area != null else []
			_log("there: %s, visible %s, %d tiles, me at %s" % [area.name if area != null else "NONE",
				area.is_visible_in_tree() if area != null else false,
				(tiles[0] as GridMap).get_used_cells().size() if not tiles.is_empty() else -1, _me().global_position])
		await _wait(6.0)
		if _shots_dir != "":
			var img := get_tree().root.get_texture().get_image()
			img.resize(img.get_width() / 2, img.get_height() / 2)
			img.save_png("%s/%s_arrived.png" % [_shots_dir, _role])
		if _am() != null:                            # (null: the host finished first and its session closed)
			_log("after a while: area %s, me at %s, floor under me %s" % [
				_am().current_area.name if _am().current_area != null else "NONE", _me().global_position, _me().is_on_floor()])
		return _done()

	# 2. The other player's character
	await _until(func() -> bool: return _other() != null and _other().visible, 20.0)
	var other := _other()
	_check("the other player is here", other != null and other.visible)
	if other != null:
		_check("their copy is remote and wears a class model", other.is_remote and other.class_data != null)
		_log("me at %s, their copy at %s" % [_me().global_position, other.global_position])

	# 2c. The guest loses its area (as if a trip never reached it): it must find its way back to
	# the host's by itself (Coop._h_where)
	if _role == "join":
		var lost := _am().current_area
		_am().current_area = null
		lost.queue_free()
		await _wait(0.5)
		_check("the guest's area is gone", _am().current_area == null)
		await _until(func() -> bool: return _arrived() and _am().current_scene_path() == town, 15.0)
		_check("the guest came back to the host's area by itself", _arrived() and _am().current_scene_path() == town)
		await _until(func() -> bool: return _other() != null and _other().visible, 10.0)
		_check("and sees the host again", _other() != null and _other().visible)
	else:
		if other != null:                            # (before the guest gears up, further down)
			_check("the new character's copy starts with no skill", other.skills.get_skill(&"attack") == null)
		await _until(func() -> bool: return Coop._player_goal.values().any(
				func(g: Dictionary) -> bool: return g.area == 0 or not _other().visible), 6.0)
		await _wait(9.0)
	other = _other()

	# 2a. The guest is a NEW character: nothing equipped or socketed when it left the lobby. It
	# gears up now, in play, and the host's copy of it must follow
	if _role == "join":
		var c := _me().class_data
		var weapon := ItemInstance.new()
		weapon.definition = c.starting_weapon
		_me().equipment.equip(weapon, EquipmentSlots.Slot.WEAPON)
		_me().skills.socket_skill(0, ItemInstance.make_gem(c.starting_skill_gem))
		_me().skills.bind_action(&"attack", 0)
	await _wait(3.0)
	other = _other()
	if _role == "host" and other != null:
		_check("after they gear up, their copy has the weapon and the skill",
				other.skills.get_skill(&"attack") != null
				and other.equipment.get_equipped(EquipmentSlots.Slot.WEAPON) != null)

	# 2b. Each casts their skill for a few seconds; the other must see the copy swing
	if other != null:
		await _cast_check("in town")

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
	if _other() != null:
		await _cast_check("in the dungeon")
	if _locks_run:
		await _locks_test()
		return _done()

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
		var beside := _spot_beside(start_pos)
		_stand(beside)
		await _wait(1.5)
		# Whether it attacks depends on the enemy and the room; a nudge towards us is a move the
		# guest must see either way
		if is_instance_valid(e) and e.global_position.distance_to(start_pos) < 0.05:
			e.global_position = start_pos.lerp(Vector3(beside.x, start_pos.y, beside.z), 0.3)
		await _wait(1.5)
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

	# 6. Kill credit: the guest kills that enemy with real skill hits. The host decides it died and
	# tells the guest, whose skill then runs its on-kill supports (a spy support counts them).
	if _role == "join":
		var skill := _me().skills.get_skill(&"attack")
		var spy := _KillSpy.new()
		skill.support_behaviors.append(spy)
		var cast := SkillCast.new(_me(), skill, skill.build_effective_stats(_me().stats), skill.get_behavior())
		for i in 60:
			if spy.kills > 0 or not is_instance_valid(e):
				break
			if e.health.current_health > 0.0:
				cast.already_hit.clear()
				cast.behavior.hit(cast, e, 20.0)
			await _wait(0.25)
		await _until(func() -> bool: return spy.kills > 0, 5.0)
		_check("the host credited the guest's kill, and its on-kill support ran once (%d)" % spy.kills, spy.kills == 1)
		skill.support_behaviors.erase(spy)
	else:
		await _until(func() -> bool: return not is_instance_valid(e) or e.health.current_health <= 0.0, 40.0)
		_check("the guest's hits killed the enemy on the host", not is_instance_valid(e) or e.health.current_health <= 0.0)

	# 7. Shared loot: the host drops an item, the guest sees the same one and takes it, and it
	# leaves the host's floor.
	if _role == "host":
		await _wait(2.0)
		var before := Coop._loot.size()
		var bag := _me().inventory.items.size()
		Coop._populator().drop_item_at(_me().global_position + Vector3(1.0, 0, 0), "rare")
		await _until(func() -> bool: return Coop._loot.size() > before, 5.0)
		_check("the host's drop is tracked (%d on the floor)" % Coop._loot.size(), Coop._loot.size() > before)
		var with_drop := Coop._loot.size()
		await _until(func() -> bool: return Coop._loot.size() < with_drop, 40.0)
		_check("the drop left the host's floor when the guest took it", Coop._loot.size() < with_drop)
		_check("the host didn't get the item", _me().inventory.items.size() == bag)
		await _wait(2.0)
	else:
		var seen_at := Time.get_ticks_msec()
		var want_id := -1
		while Time.get_ticks_msec() - seen_at < 40000 and want_id < 0:
			for loot_id: int in Coop._loot:
				var p := Coop._loot[loot_id] as LootPickup
				# the one the host just dropped beside itself (not a drop from elsewhere in the dungeon)
				if is_instance_valid(p) and p.item != null and _other() != null \
						and p.global_position.distance_to(_other().global_position) < 3.0:
					want_id = loot_id
			await _wait(0.25)
		_check("the host's drop is on the guest's floor", want_id >= 0)
		if want_id >= 0:
			var pickup := Coop._loot[want_id] as LootPickup
			var item_name := pickup.item.get_display_name()
			var had := _me().inventory.items.size()
			_check("the guest may take it", pickup.try_pickup(_me().inventory))
			await _until(func() -> bool: return not Coop._loot.has(want_id), 10.0)
			await _wait(0.3)                             # the pickup is freed at the end of that frame
			_check("the drop is gone here", not Coop._loot.has(want_id) and not is_instance_valid(pickup))
			_check("and %s is in the guest's backpack" % item_name, _me().inventory.items.size() == had + 1)
		await _wait(2.0)
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


## `-- host locks` / `-- join locks`, in the dungeon: the host's locks judge the guest's hits
## (Coop._e_hit, HitFacts) and the guest's copy only shows them (EnemyTrait "Co-op"). Both machines
## put the same two traits on the same enemy (the lowest id): an OVERFLOW lock (a port, shut until
## the host opens it here) and a REFLECTOR. The enemies' AI and skills are off on the host, so
## nothing but the Reflector hurts the guest.
##   1  on the guest the copy's traits are switched off
##   2  a guest's real skill hit, port shut: absorbed on the host (its life stays), the host never
##      answers it (no leech or on-hit for the guest), and the Reflector's zap reaches the guest
##   3  the host opens the port: it opens on the guest's copy too, and its tag says OPEN there
##   4  a guest's hit now lands on the host, and the host answers it (_e_landed)
const OVERFLOW_TRAIT := preload("res://systems/enemies/traits/overflow_lock_trait.gd")
const REFLECTOR_TRAIT := preload("res://systems/enemies/traits/reflector_trait.gd")


func _locks_test() -> void:
	var ids := Coop._enemies.keys()
	ids.sort()
	var target: EnemyBase = null
	for id: int in ids:                              # the lowest id still alive (the same on both)
		var cand = Coop._enemies[id]
		if is_instance_valid(cand) and (cand as EnemyBase).health.current_health > 0.0:
			target = cand
			break
	_check("an enemy to lock", target != null)
	if target == null:
		return
	_log("locking enemy %d %s" % [int(target.get_meta(Coop.NET_ID)), target.display_name])
	EnemySpawner._add_trait(target, OVERFLOW_TRAIT, "test_overflow")
	EnemySpawner._add_trait(target, REFLECTOR_TRAIT, "test_reflector")
	var lock: OverflowLock = null
	for t in target.traits:
		if t is OverflowLock:
			lock = t
	_check("the traits are on it", lock != null and target.traits.size() >= 2)
	if lock == null:
		return
	var full := target.health.current_health

	if _role == "host":
		# Nothing but the Reflector may hurt anyone: every enemy's AI and skills off (not the enemy
		# itself, so its traits still run), and we stand by the target to keep it awake
		for e in get_tree().get_nodes_in_group("enemies"):
			(e.get("ai") as Node).process_mode = Node.PROCESS_MODE_DISABLED
			for c in e.get_children():
				if c is EnemySkills:
					c.process_mode = Node.PROCESS_MODE_DISABLED
		_stand(_spot_beside(target.global_position))
		EnemySleep.wake(target)
		# 2. The guest's hit with the port shut
		# (the write it starts is only kept for OverflowLock.tail_time: watched every frame)
		await _until(func() -> bool: return lock._writes.size() > 0, 20.0)
		_check("the guest's hit reached the lock here", lock._writes.size() > 0)
		await _wait(1.0)
		_check("the guest's hit was absorbed here: its life stays (%.0f -> %.0f)" % [full, target.health.current_health],
				is_equal_approx(target.health.current_health, full))
		# 3. Open the port
		await _wait(2.0)
		lock.open_port("TEST // PORT OPEN", 0.0, 12.0)
		_check("the port is open here", lock.is_open())
		# 4. The guest's next hit lands
		await _until(func() -> bool: return not is_instance_valid(target) or target.health.current_health < full, 15.0)
		_check("the guest's hit landed through the open port (%.0f -> %.0f)" % [
				full, target.health.current_health if is_instance_valid(target) else -1.0],
				not is_instance_valid(target) or target.health.current_health < full)
		await _wait(4.0)
		return

	# The guest
	_check("its traits are switched off on the copy", lock.process_mode == Node.PROCESS_MODE_DISABLED
			and lock.is_copy())
	await _wait(3.0)                                 # the host adds its own, and stands by it
	var skill := _me().skills.get_skill(&"attack")
	_check("the guest has a skill to hit with", skill != null)
	if skill == null:
		return
	var cast := SkillCast.new(_me(), skill, skill.build_effective_stats(_me().stats), skill.get_behavior())
	# 2. Port shut: absorbed, not answered, zapped
	var hp := _me().health
	var life := hp.current_health
	cast.behavior.hit(cast, target, 2.0)
	var seq := Coop._hit_seq
	_check("the hit went to the host (hit %d)" % seq, seq > 0 and Coop._my_hits.has(seq))
	await _wait(2.0)
	_check("the host didn't answer it: absorbed, no reward here", Coop._my_hits.has(seq))
	_check("its life here stays too", is_equal_approx(target.health.current_health, full))
	_check("the Reflector's zap reached the guest (%.0f -> %.0f)" % [life, hp.current_health], hp.current_health < life)
	# 3. The host opens the port
	await _until(func() -> bool: return lock.is_open(), 20.0)
	_check("the port opened on the guest's copy", lock.is_open())
	await _until(func() -> bool: return lock.shown_tag_state() == "OPEN", 3.0)
	_check("its tag says OPEN here (%s)" % lock.shown_tag_state(), lock.shown_tag_state() == "OPEN")
	# 4. Now it lands
	cast.already_hit.clear()
	cast.behavior.hit(cast, target, 1.0)
	var seq2 := Coop._hit_seq
	await _until(func() -> bool: return not Coop._my_hits.has(seq2), 6.0)
	_check("the host answered the landed hit (hit %d)" % seq2, not Coop._my_hits.has(seq2))
	await _until(func() -> bool: return not is_instance_valid(target) or target.health.current_health < full, 6.0)
	_check("and its life dropped here too", not is_instance_valid(target) or target.health.current_health < full)
	await _wait(2.0)


## Both sides cast their attack for 8 seconds, through the player's own input path, and watch
## the other's copy: it must play the skill's animation.
func _cast_check(where: String) -> void:
	var count := {"mine": 0, "theirs": 0}             # a Dictionary: lambdas copy plain numbers
	var on_mine := func(_a: StringName) -> void: count.mine += 1
	var on_theirs := func(_cooldown: float) -> void: count.theirs += 1
	_me().skill_cast.connect(on_mine)
	var their_skill := _other().skills.get_skill(&"attack")
	_check("the other player's copy has their skill %s" % where, their_skill != null)
	if their_skill != null:
		their_skill.used.connect(on_theirs)           # fires each time the copy casts it
	if _shots_dir != "" and _role == "join":
		_stand(_me().global_position + Vector3(2.2, 0.1, 0))    # side by side, both on screen
	for i in 16:
		_me()._held[&"attack"] = true                 # as if the attack button is held
		Input.action_press(&"attack")
		await _wait(0.5)
		if _shots_dir != "" and i >= 4 and i < 12:    # `shots=<folder>`: what this window shows, mid-cast
			await _wait(0.07 * (i - 4))               # a different moment of the swing each time
			var img := get_tree().root.get_texture().get_image()
			img.resize(img.get_width() / 2, img.get_height() / 2)
			img.save_png("%s/%s_%s_%d.png" % [_shots_dir, _role, where.replace(" ", "_"), i])
	Input.action_release(&"attack")
	_me()._held[&"attack"] = false
	_me().skill_cast.disconnect(on_mine)
	if their_skill != null:
		their_skill.used.disconnect(on_theirs)
	var o := _other()
	_log("their copy: life %.0f, dead %s, reach %.2f, attack speed %.2f, weapon %s, skill %s" % [
		o.health.current_health, SkillBehavior.is_dead(o), o.stats.get_stat(StatTypes.Stat.ATTACK_RANGE),
		o.stats.get_stat(StatTypes.Stat.ATTACK_SPEED),
		o.equipment.get_equipped(EquipmentSlots.Slot.WEAPON) != null,
		their_skill.gem.id if their_skill != null else "none"])
	_check("cast our own skill %s (%d casts)" % [where, count.mine], count.mine > 0)
	_check("the other player's copy cast theirs %s (%d casts)" % [where, count.theirs], count.theirs > 0)


## Counts the on-kill calls a skill makes (the kill credit step).
class _KillSpy extends SupportBehavior:
	var kills := 0

	func on_kill(_cast: SkillCast, _target: Node, _hit: HitInfo) -> void:
		kills += 1


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
	if _role == "host" and _host_town != "":
		data[SaveManager.LAST_TOWN_KEY] = _host_town
	if _role == "host":                              # the guest starts bare, like a new character
		if c.starting_weapon != null:
			data["equipment"]["weapon"] = c.starting_weapon.id
		if c.starting_skill_gem != null:
			data["skills"] = [{"gem": c.starting_skill_gem.id, "supports": [], "action": "attack"}]
	if _from_slot >= 0:                              # a real character's data, seated in the test's own slot
		var real := SaveManager.load_slot(_from_slot)
		if not real.is_empty():
			data = real.duplicate(true)
			_real_character = true
			if _role == "host" and _host_town != "":
				data[SaveManager.LAST_TOWN_KEY] = _host_town
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
