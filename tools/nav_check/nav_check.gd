extends Node3D
## NAVIGATION CHECK. Open nav_check.tscn and press F6 (Run Current Scene), then read the
## Output panel. For every area in `areas` it:
##   1. enters the area and waits for the navmesh to bake
##   2. checks every enemy stands on the navmesh and has a path to the player
##   3. checks every breakable prop is cut out of the navmesh
##   4. tells every enemy to chase the player for a few seconds and counts who actually moved
## A healthy area prints   off_mesh=0 unreachable=0 moved=N/N   and no "not moving" lines.
## Dungeons are random each visit, so run it a few times when hunting a rare problem.

@export var areas: PackedStringArray = ["act_1_map_1", "act_1_spillway", "act_1_cache_warrens",
	"act_1_map_2", "act_1_dead_sector", "act_1_relay_trench", "act_1_coolant_vaults",
	"act_1_overclock_foundry", "act_1_firewall_approach", "act_1_map_3"]
@export var area_folder := "res://scenes/map/dungeon/"
@export var first_level := 1          # dungeon level of the first area; +1 for each next one
@export var chase_seconds := 3.0

func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = load("res://scenes/map/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _secs(3.0)
	var am = get_tree().get_first_node_in_group("area_manager")
	var player = get_tree().get_first_node_in_group("players")
	var level := first_level - 1
	var bad_areas := 0
	for a in areas:
		level += 1
		player.health.current_health = 1e9
		am.go_to(area_folder + a + ".tscn", &"default", level, 9000 + level)
		var t0 := Time.get_ticks_msec()
		while (am.current_area == null or am.current_area.scene_file_path.get_file().get_basename() != a) \
				and Time.get_ticks_msec() - t0 < 15000:
			await get_tree().process_frame
		var area: Node = am.current_area
		var region := area.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
		if region == null:
			print("NAV %-24s has no NavigationRegion3D" % a)
			continue
		t0 = Time.get_ticks_msec()
		while (region.is_baking() or region.navigation_mesh == null or region.navigation_mesh.get_polygon_count() == 0) \
				and Time.get_ticks_msec() - t0 < 20000:
			await get_tree().process_frame
		await _secs(0.5)
		player.input_locked = true
		player.health.current_health = 1e9
		var map := region.get_navigation_map()
		var ppos: Vector3 = player.global_position
		var p_close := NavigationServer3D.map_get_closest_point(map, ppos)
		var enemies := get_tree().get_nodes_in_group("enemies").filter(func(e): return is_instance_valid(e) and area.is_ancestor_of(e))
		var off := 0
		var unreach := 0
		for e in enemies:
			var pos: Vector3 = e.global_position
			var c := NavigationServer3D.map_get_closest_point(map, pos)
			if Vector2(c.x - pos.x, c.z - pos.z).length() > 0.6 or absf(c.y - pos.y) > 1.0:
				off += 1
			var path := NavigationServer3D.map_get_path(map, pos, ppos, true)
			if path.is_empty() or path[path.size() - 1].distance_to(p_close) > 1.5:
				unreach += 1
		var props_in := 0
		var holder := area.get_node_or_null("Props")
		if holder:
			for p in holder.get_children():
				var pc := NavigationServer3D.map_get_closest_point(map, p.global_position)
				if Vector2(pc.x - p.global_position.x, pc.z - p.global_position.z).length() < 0.25:
					props_in += 1
		# Live test: everyone chases the player
		var start := {}
		for e in enemies:
			start[e] = e.global_position
			e.ai.target = player
			e.nav.target_position = ppos
		await _secs(chase_seconds)
		var moved := 0
		var still := []
		for e in enemies:
			if not is_instance_valid(e):
				continue
			var d: float = Vector2(e.global_position.x - start[e].x, e.global_position.z - start[e].z).length()
			if d > 1.0 or start[e].distance_to(ppos) < 3.0:
				moved += 1
			elif still.size() < 5:
				var hits := []
				for i in e.get_slide_collision_count():
					var col = e.get_slide_collision(i).get_collider()
					if col:
						hits.append(str(area.get_path_to(col)))
				still.append("%s at %s, blocked by %s" % [e.display_name, e.global_position.snapped(Vector3.ONE * 0.1), hits])
		var ok: bool = off == 0 and unreach == 0 and props_in == 0 and moved == enemies.size()
		if not ok:
			bad_areas += 1
		print("NAV %s %-24s navmesh polygons=%d enemies=%d off_mesh=%d unreachable=%d props_not_cut_out=%d moved=%d/%d" % [
			"ok " if ok else "BAD", a, region.navigation_mesh.get_polygon_count(), enemies.size(), off, unreach, props_in, moved, enemies.size()])
		for s in still:
			print("NAV      not moving: ", s)
	print("NAV done: %d of %d areas had problems" % [bad_areas, areas.size()])
	get_tree().quit()
