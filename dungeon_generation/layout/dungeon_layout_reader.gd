@tool
class_name DungeonLayoutReader
extends RefCounted

static func read(root: Node, grid_map: GridMap, grid_w: int, grid_h: int) -> DungeonLayout:
	var layout := DungeonLayout.new()
	var bounds := Rect2i(1, 1, grid_w - 2, grid_h - 2)

	for node in root.find_children("*", "Marker3D", true, false):
		var m := node as DungeonMarker
		if m == null:
			continue
		var c3 := grid_map.local_to_map(grid_map.to_local(m.global_position))
		var cell := Vector2i(c3.x, c3.z)

		# Bare points: no room of their own, just a named spot inside a room another marker made
		if m is SpawnMarker and not m.create_room:
			if not bounds.has_point(cell):
				push_warning("%s is outside the grid, skipped" % m.name)
				continue
			layout.spawns[m.spawn_id] = cell
			continue
		if m is EnemyMarker and not m.create_room:
			if not bounds.has_point(cell):
				push_warning("%s is outside the grid, skipped" % m.name)
				continue
			layout.enemies.append(_enemy_entry(m, cell))
			continue

		var rect := Rect2i(cell - m.room_size / 2, m.room_size)
		var fitted := rect.intersection(bounds)
		if fitted != rect:
			push_warning("%s sticks out of the grid and was clipped" % m.name)
		if fitted.size.x < 3 or fitted.size.y < 3:
			push_warning("%s is outside the grid, skipped" % m.name)
			continue

		var room_type := "custom"
		if m is SpawnMarker:
			room_type = "start"
		elif m is PortalMarker:
			room_type = "portal"
		elif m is EnemyMarker and m.clear_room:
			room_type = "boss"
		var room := RoomData.new(fitted, room_type)
		layout.rooms.append(room)

		if m is SpawnMarker:
			var spot: Vector2i = cell if fitted.has_point(cell) else room.center()
			if layout.spawns.has(m.spawn_id):
				push_warning("Duplicate spawn id '%s', using the last" % m.spawn_id)
			layout.spawns[m.spawn_id] = spot
		elif m is PortalMarker:
			layout.portals.append({
				"cell": room.center(),
				"target_area": m.target_area,
				"target_spawn": m.target_spawn,
				"arrival_id": m.arrival_spawn_id,
				"dungeon_level": m.dungeon_level,
				# rotation around Y relative to the grid, so a rotated level still lines up
				"yaw": (grid_map.global_basis.orthonormalized().inverse() * m.global_basis.orthonormalized()).get_euler().y,
				"exit_distance": m.exit_distance,
				"sealed_by_key": m.sealed_by_key,
				"open_after_quest": m.open_after_quest,
				"shown_after_quest": m.shown_after_quest,
				"route_after_quest": m.route_after_quest,
				"routed_area": m.routed_area,
				"routed_spawn": m.routed_spawn,
				"route_when_done": m.route_when_done,
				"routed_level": m.routed_level,
				"clears_stop": m.clears_stop,
			})
		elif m is EnemyMarker:
			layout.enemies.append(_enemy_entry(m, cell if fitted.has_point(cell) else room.center()))

	# A "clear room" enemy that sits inside a room made by another marker turns that room
	# into a boss room, so the random enemy spawner skips it.
	for entry in layout.enemies:
		if not entry["clear_room"]:
			continue
		for r: RoomData in layout.rooms:
			if r.room_type == "custom" and r.rect.has_point(entry["cell"]):
				r.room_type = "boss"

	if layout.spawns.has(&"default"):
		layout.spawn_cell = layout.spawns[&"default"]
	elif not layout.spawns.is_empty():
		layout.spawn_cell = layout.spawns.values()[0]
	return layout


static func _enemy_entry(m, cell: Vector2i) -> Dictionary:
	if m.enemy == null:
		push_warning("%s has no Enemy assigned, nothing will spawn" % m.name)
	return {
		"cell": cell,
		"definition": m.enemy,
		"rarity": m.rarity,
		"clear_room": m.clear_room,
		"modifiers": m.modifiers,
		"replace_random": m.replace_random_modifiers,
		"threat_traits": m.threat_traits,
		"key": m.drops_key,
	}
