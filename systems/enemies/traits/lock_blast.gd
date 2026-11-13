class_name LockBlast
extends RefCounted
## What a lock throws back at the player, sized to the PLAYER'S life, never to their damage, so a
## huge buff can't come back as a one-shot: OVERFLOW's spill, ECHO's return ring, DIFF's mirror.
## Everything here is telegraphed (a ring that grows, an orb that charges and flies slowly) and
## only references its own nodes, so it finishes cleanly even if the lock that threw it is gone
## (RECALL swaps its borrowed locks out mid-fight).


## A flat ring grows from `at` to `radius` over `seconds`, then every player inside it takes
## `share` of their maximum life. Returns at once; `on_hit` (optional) runs if anyone was hit.
static func ring(parent: Node, at: Vector3, radius: float, seconds: float, share: float, col: Color,
		ignore_armour := false, on_hit := Callable()) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.92
	mesh.outer_radius = 1.0
	mesh.rings = 48
	mesh.ring_segments = 4
	var mat := _glow(col, 0.85)
	mesh.material = mat
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.top_level = true
	parent.add_child(node)
	node.global_position = at + Vector3.UP * 0.08
	node.scale = Vector3(0.6, 1.0, 0.6)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3(radius, 1.0, radius), seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if hit_players(node.get_tree(), at, radius, share, ignore_armour) and on_hit.is_valid():
			on_hit.call())
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(node.queue_free)


## An orb that has charged on its thrower flies from `from` to `to` at `speed` m/s, then every
## player within `radius` of where it lands takes `share` of their maximum life. Not homing: step
## off the spot it was aimed at. Returns the flight time in seconds.
static func orb(parent: Node, node: MeshInstance3D, from: Vector3, to: Vector3, speed: float,
		radius: float, share: float, on_hit := Callable()) -> float:
	if parent == null or not parent.is_inside_tree() or node == null:
		return 0.0
	if node.get_parent() != parent:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		parent.add_child(node)
	node.top_level = true
	node.global_position = from
	var flight := maxf(from.distance_to(to) / maxf(speed, 0.1), 0.15)
	var tw := node.create_tween()
	tw.tween_property(node, "global_position", to, flight)
	tw.tween_callback(func() -> void:
		if hit_players(node.get_tree(), to, radius, share, false) and on_hit.is_valid():
			on_hit.call())
	tw.tween_property(node, "scale", Vector3.ONE * 2.2, 0.18)
	var prim := node.mesh as PrimitiveMesh
	if prim != null and prim.material != null:
		tw.parallel().tween_property(prim.material, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(node.queue_free)
	return flight


## A small glowing sphere, for orb(): put it on the thrower while it charges, then throw it.
static func make_orb(col: Color, size := 0.35) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = _glow(col, 0.9)
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.top_level = true
	return node


## Every living player within `radius` of `at` (on the ground plane) takes `share` of their
## maximum life. Barrier and guard soak it like any hit; armour too unless `ignore_armour`.
## True when anyone was hit.
static func hit_players(tree: SceneTree, at: Vector3, radius: float, share: float, ignore_armour := false) -> bool:
	if tree == null:
		return false
	var hit_any := false
	for p in tree.get_nodes_in_group("players"):
		var body := p as Node3D
		var hp := p.get("health") as HealthComponent
		var stats := p.get("stats") as StatComponent
		if body == null or hp == null or stats == null or hp.current_health <= 0.0:
			continue
		var flat := Vector2(body.global_position.x - at.x, body.global_position.z - at.z)
		if flat.length() > radius:
			continue
		hp.take_damage(stats.get_stat(StatTypes.Stat.MAX_HEALTH) * share, ignore_armour)
		hit_any = true
	return hit_any


static func _glow(col: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(col.r * 1.6, col.g * 1.6, col.b * 1.6, alpha)
	return mat
