class_name ConvoyDressing
extends Node3D
## The bits that sell the convoy camp as a ship under way, built from the painted deck when the
## town loads (so they follow the layout if you repaint it):
##   engines        glowing thruster plumes off the stern, flickering, with their own light
##   streaks        faint light streaks (convoy_streak.png) blowing down the deck, the same way
##                  the stars flow; they stretch out during a warp
##   running lights a red and a green light blinking at the bow corners
## The stern and bow are the deck's two ends along ConvoyMotion.heading.
## Docked (the convoy moored at Hardfault's dock, act_1_dock.tscn): point `hull` at the convoy's
## GridMap and tick `docked`. The engines idle low and nothing streams past.

@export var engine_count := 3
@export var engine_color := Color(0.35, 0.85, 1.0)
@export var dust_amount := 70
@export var dust_speed := 9.0            # metres per second down the deck
@export var streak_texture: Texture2D = preload("res://assets/textures/convoy/convoy_streak.png")
@export var streak_length := 1.2         # metres while cruising
@export var warp_streak_length := 5.0    # metres at full warp

## The deck to dress. Empty = the area's own (its DungeonDirector's GridMap).
@export var hull: GridMap
## The hull's tiles, to tell its walls from its deck. Empty = the director's theme.
@export var hull_theme: DungeonTheme
## Moored, not under way: idling engines, no streaks.
@export var docked := false

const FLOOR_LAYER := 0

var _plumes: Array[MeshInstance3D] = []
var _lights: Array[OmniLight3D] = []
var _blinkers: Array[MeshInstance3D] = []
var _streak: QuadMesh
var _dust: GPUParticles3D
var _motion: ConvoyMotion
var _t := 0.0


func _ready() -> void:
	var area := get_parent()
	var director: DungeonDirector = null
	var motion: ConvoyMotion = null
	for c in area.get_children():
		if c is DungeonDirector:
			director = c
		elif c is ConvoyMotion:
			motion = c
	var gm: GridMap = hull if hull != null else (director.grid_map if director != null else null)
	var theme: DungeonTheme = hull_theme if hull_theme != null else (director.dungeon_theme if director != null else null)
	if gm == null or theme == null:
		return
	_motion = motion
	var heading := (motion.heading if motion != null else Vector3.RIGHT).normalized()
	var side := heading.cross(Vector3.UP).normalized()
	# The deck's extent along the heading and across it, in this node's space
	var lo := INF
	var hi := -INF
	var left := INF
	var right := -INF
	var y := 0.0
	# Deck cells only: the walls are on the same layer
	var wall_id := gm.mesh_library.find_item_by_name(theme.wall_name)
	var cells: Array[Vector3i] = []
	for c in gm.get_used_cells():
		if c.y == FLOOR_LAYER and gm.get_cell_item(c) != wall_id:
			cells.append(c)
	for c in cells:
		var p := to_local(gm.to_global(gm.map_to_local(c)))
		y = p.y
		lo = minf(lo, p.dot(heading))
		hi = maxf(hi, p.dot(heading))
		left = minf(left, p.dot(side))
		right = maxf(right, p.dot(side))
	if lo == INF:
		return
	var cell := gm.cell_size.x
	# The very back and front rows: the engines sit across the stern, the running lights on the
	# bow's corners (not the whole ship's width, which takes in the side pods)
	var stern := _row_span(gm, cells, heading, side, lo, cell)
	var bow_row := _row_span(gm, cells, heading, side, hi, cell)
	# The stern wall stands one cell behind the last floor row: its outer face is 1.5 cells back
	_build_engines(heading, side, lo - cell * 1.5, stern.x, stern.y, y)
	if not docked:
		_build_dust(heading, side, lo, hi, left, right, y)
	var bow := hi + cell * 0.5
	_blinker(heading * bow + side * (bow_row.y + cell * 0.5) + Vector3.UP * (y + 2.2), Color(0.2, 1.0, 0.4))
	_blinker(heading * bow + side * (bow_row.x - cell * 0.5) + Vector3.UP * (y + 2.2), Color(1.0, 0.2, 0.25))
	_blinker(heading * (lo - cell * 0.5) + side * ((stern.x + stern.y) * 0.5) + Vector3.UP * (y + 2.6),
			Color(1.0, 0.85, 0.4))


## (left, right) across the ship of the deck cells in the row at `along` on the heading.
func _row_span(gm: GridMap, cells: Array[Vector3i], heading: Vector3, side: Vector3, along: float,
		cell: float) -> Vector2:
	var span := Vector2(INF, -INF)
	for c in cells:
		var p := to_local(gm.to_global(gm.map_to_local(c)))
		if absf(p.dot(heading) - along) <= cell * 0.5:
			span = Vector2(minf(span.x, p.dot(side)), maxf(span.y, p.dot(side)))
	return span


## Engines bolted to the stern wall's outer face (`face`, along the heading), at hull height
## (`y`, the middle of the wall), so they read as part of the ship: a housing block set into the
## wall, a flared nozzle on it, and the plume out of the nozzle.
func _build_engines(heading: Vector3, side: Vector3, face: float, from: float, to: float, y: float) -> void:
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.10, 0.11, 0.14)
	hull_mat.metallic = 0.7
	hull_mat.roughness = 0.35
	var plume_mat := StandardMaterial3D.new()
	plume_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plume_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plume_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	plume_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plume_mat.albedo_color = Color(engine_color, 0.55)
	# Points the cylinders' Y axis backwards (out of the stern)
	var aim := Basis(side, -heading, side.cross(-heading)).orthonormalized()
	var flat := Basis(heading, Vector3.UP, heading.cross(Vector3.UP)).orthonormalized()
	for i in engine_count:
		var t := (i + 0.5) / engine_count
		var s := lerpf(from, to, t)
		var base := heading * face + side * s + Vector3.UP * y
		# Housing: half sunk into the wall
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(1.2, 1.3, 1.7)          # along the heading, up, across
		box_mesh.material = hull_mat
		var housing := MeshInstance3D.new()
		housing.mesh = box_mesh
		housing.basis = flat
		housing.position = base - heading * 0.4
		add_child(housing)
		# Nozzle: flares out towards the exhaust
		var at := base - heading * 1.5
		var nozzle_mesh := CylinderMesh.new()
		nozzle_mesh.top_radius = 0.6
		nozzle_mesh.bottom_radius = 0.4
		nozzle_mesh.height = 1.4
		nozzle_mesh.radial_segments = 8
		nozzle_mesh.material = hull_mat
		var nozzle := MeshInstance3D.new()
		nozzle.mesh = nozzle_mesh
		nozzle.basis = aim
		nozzle.position = at
		add_child(nozzle)
		var plume_mesh := CylinderMesh.new()
		plume_mesh.top_radius = 0.05                     # tapers away from the ship
		plume_mesh.bottom_radius = 0.45
		plume_mesh.height = 3.5
		plume_mesh.radial_segments = 10
		plume_mesh.material = plume_mat
		var plume := MeshInstance3D.new()
		plume.mesh = plume_mesh
		plume.basis = aim
		plume.position = at - heading * (0.7 + 1.75)      # starts at the nozzle's mouth
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(plume)
		_plumes.append(plume)
		var light := OmniLight3D.new()
		light.light_color = engine_color
		light.light_energy = 2.0
		light.omni_range = 6.0
		light.position = at - heading * 1.2
		add_child(light)
		_lights.append(light)


func _build_dust(heading: Vector3, side: Vector3, lo: float, hi: float, left: float, right: float, y: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = dust_amount
	p.lifetime = (hi - lo + 12.0) / dust_speed
	p.preprocess = p.lifetime
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(1.0, 2.0, (right - left) * 0.5 + 6.0)
	mat.direction = Vector3(-1, 0, 0)                  # local: the node is turned to face the heading
	mat.spread = 3.0
	mat.initial_velocity_min = dust_speed * 0.8
	mat.initial_velocity_max = dust_speed * 1.2
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.5
	mat.scale_max = 1.2
	p.process_material = mat
	# A flat streak lying along the flow (the particles keep the emitter's turn, whose X is the
	# heading). The texture is bright at its right end: mirrored, so the bright head leads.
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2(streak_length, 0.07)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dmat.albedo_texture = streak_texture
	dmat.albedo_color = Color(0.8, 0.95, 1.0, 0.6)
	dmat.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	quad.material = dmat
	p.draw_pass_1 = quad
	_streak = quad
	_dust = p
	# Spawn line just past the bow, across the whole deck, blowing back towards the stern
	p.basis = Basis(heading, Vector3.UP, heading.cross(Vector3.UP)).orthonormalized()
	p.position = heading * (hi + 6.0) + side * ((left + right) * 0.5) + Vector3.UP * (y + 2.0)
	p.visibility_aabb = AABB(Vector3(-(hi - lo) - 20.0, -4.0, -40.0), Vector3(hi - lo + 30.0, 8.0, 80.0))
	add_child(p)


func _blinker(at: Vector3, col: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.material = mat
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	_blinkers.append(m)


func _process(delta: float) -> void:
	_t += delta
	for i in _plumes.size():
		# Each engine flickers on its own
		var f := 0.9 + 0.1 * sin(_t * 23.0 + i * 1.7) + 0.05 * sin(_t * 41.0 + i)
		if docked:
			f = 0.45 + 0.08 * sin(_t * 9.0 + i * 1.7)     # idling at the dock: short, dim, slow
		_plumes[i].scale = Vector3(f, 0.85 + 0.15 * f, f) if not docked else Vector3(f, f * 0.6, f)
		_lights[i].light_energy = 1.6 + 0.6 * f
	# Streaks stretch and speed up with the convoy (a warp jump)
	if _motion != null and _streak != null:
		var w := clampf(inverse_lerp(_motion.cruise_speed, _motion.warp_speed, _motion.speed), 0.0, 1.0)
		_streak.size.x = lerpf(streak_length, warp_streak_length, w)
		_dust.speed_scale = lerpf(1.0, 3.0, w)
	for i in _blinkers.size():
		_blinkers[i].visible = fmod(_t + i * 0.5, 1.6) < 0.25
