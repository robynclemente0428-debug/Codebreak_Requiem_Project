extends Node3D
## For every saved character: builds the character as its owner has it, then the co-op copy the
## OTHER machines build from the loadout Coop sends (Coop.loadout_of), and checks the copy matches:
##   every skill on a key is on the copy, and swings when cast
##   every script the owner runs also runs on the copy (the copy gets the owner's rank)
##   every skill's numbers (its flags: arc, range, radius...) are the same on both
## Reads the save slots, writes nothing. Prints [LOADOUT] lines.
##     godot --headless res://tools/coop_test/loadout_check.tscn

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	for slot in SaveManager.MAX_SLOTS:
		var data := SaveManager.load_slot(slot)
		if data.is_empty():
			continue
		# The owner's own character (never saved: no slot is seated)
		var owner_p := _build(data, false)
		await get_tree().process_frame
		await get_tree().process_frame
		# Through the same encoding a network message uses
		var loadout: Dictionary = bytes_to_var(var_to_bytes(Coop.loadout_of(owner_p)))
		print("[LOADOUT] slot %d: %s the %s, rank %d, +%.1f points, +%d steps, %d bytes" % [slot,
				data.get("name", "?"), data.get("class_id", "?"), owner_p.skills.rank(),
				owner_p.skills.bonus_points(), owner_p.skills.bonus_steps(), var_to_bytes(loadout).size()])
		var copy := _build(loadout, true)
		await get_tree().process_frame
		await get_tree().process_frame
		for i in owner_p.skills.sockets.size():
			var mine := owner_p.skills.sockets[i].skill
			if mine == null:
				continue
			var theirs := copy.skills.sockets[i].skill
			var action := owner_p.skills.action_of(i)
			var problems: Array[String] = []
			if theirs == null:
				problems.append("not on the copy")
			else:
				if copy.skills.action_of(i) != action:
					problems.append("on another key")
				if (owner_p.skills.get_program(i) != null) != (copy.skills.get_program(i) != null):
					problems.append("script %s for the owner, %s on the copy" % [
						"runs" if owner_p.skills.get_program(i) != null else "off",
						"runs" if copy.skills.get_program(i) != null else "off"])
				for key in mine._flags:
					if not is_equal_approx(float(mine._flags[key]), theirs.get_flag(key)):
						problems.append("%s %.2f / %.2f" % [key, mine._flags[key], theirs.get_flag(key)])
				if action != &"":
					copy.remote_cast(action, 0.0, Vector3(0, 0, 5))
					await get_tree().create_timer(0.1).timeout
					if not bool(copy.get_node("model").get("_action_playing")):
						problems.append("no animation")
			if not problems.is_empty():
				fails += 1
			print("[LOADOUT]   %s on %s, script %s: %s" % [mine.gem.id, action if action != &"" else &"no key",
				"on" if owner_p.skills.get_program(i) != null else "off",
				"ok" if problems.is_empty() else "FAIL: " + "; ".join(problems)])
		# A stored script that doesn't fit this owner's rank: with a high rank and budget sent, it
		# must run on the copy (shows the copy really uses the limits it's sent, not its own rank 0)
		for i in owner_p.skills.sockets.size():
			if owner_p.skills.sockets[i].skill == null or owner_p.skills.get_program(i) != null \
					or owner_p.skills.stored_program(i) == null:
				continue
			var generous: Dictionary = loadout.duplicate(true)
			generous["limits"] = {"rank": Ranks.LADDER.size() - 1, "points": 500.0, "steps": 50}
			var boosted := _build(generous, true)
			await get_tree().process_frame
			var runs := boosted.skills.get_program(i) != null
			if not runs:
				fails += 1
			print("[LOADOUT]   %s: its stored script with a top rank sent: %s" % [
				owner_p.skills.sockets[i].skill.gem.id, "runs on the copy, ok" if runs else "FAIL: still off"])
			boosted.queue_free()
		await get_tree().create_timer(0.8).timeout
		owner_p.queue_free()
		copy.queue_free()
		await get_tree().process_frame
	print("[LOADOUT] %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit()


func _build(data: Dictionary, remote: bool) -> Player:
	var p := (load(Coop.PLAYER_SCENE) as PackedScene).instantiate() as Player
	p.is_remote = remote
	p.coop_data = data
	add_child(p)
	return p
