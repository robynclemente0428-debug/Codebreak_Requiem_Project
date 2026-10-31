class_name NullDecals
extends RefCounted
## Null corruption on an area's floor: small holes into the void, projected with Decal nodes.
## Each is a black patch with a faint nebula, a few stars and a thin violet rim, in the palette
## of orb_void.gdshader. Kept small and dim so they read as scenery, not as something to dodge.
## The deeper the dungeon, the more of them.
##
## No art needed: the textures are made from noise the first time they're used and kept for
## the rest of the session. To use painted ones instead, fill `custom_stains` with
## {albedo, emission} pairs before the first scatter().
##
## Decals don't touch collision or the navmesh, so they change nothing about gameplay.

const VARIANTS := 4                     # different generated patches
const TEX_SIZE := 96                    # px
const DECAL_HEIGHT := 0.6               # metres the projection box reaches above and below the floor
# No distance fade: the isometric camera sits further away than any useful fade distance, so it
# hid every patch. MAX_DECALS keeps the cost down instead.
const MAX_DECALS := 240                 # per area, whatever its size

const COL_VOID := Color(0.005, 0.0, 0.02, 0.96)    # the hole itself
const COL_RIM := Color(0.55, 0.1, 1.0)            # orb_void rim
const COL_NEBULA_A := Color(0.08, 0.12, 0.55)     # deep blue
const COL_NEBULA_B := Color(0.45, 0.1, 0.8)       # violet
const COL_STAR := Color(0.9, 0.85, 1.0)

## Painted patches to use instead of the generated ones: [{"albedo": Texture2D, "emission": Texture2D}]
static var custom_stains: Array[Dictionary] = []
static var _stains: Array[Dictionary] = []


## How many patches an area of this dungeon level gets, for its number of floor cells.
## Level 1 has one on about 1 cell in 12, level 10 on about 1 in 4.
static func count_for_level(level: int, floor_cells: int) -> int:
	var t := clampf((level - 1) / 9.0, 0.0, 1.0)
	return clampi(roundi(floor_cells * lerpf(0.08, 0.25, t)), 8, MAX_DECALS)


## Adds `count` patches under `host` (in a child node called NullDecals), on random floor cells.
##   cells        every walkable cell of the area (Vector2i grid cells)
##   to_world     Callable(Vector2i) -> Vector3, the floor surface at the centre of a cell
##   cell_size    metres per cell
##   rooms        optional Rect2i list; about half the patches land inside these
## The same seed gives the same patches, so rejoining a dungeon instance looks the same.
static func scatter(host: Node3D, cells: Array[Vector2i], to_world: Callable, count: int,
		rng_seed: int, cell_size: float, rooms: Array[Rect2i] = [], level := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "NullDecals"
	host.add_child(root)
	if cells.is_empty() or count <= 0:
		return root
	var stains := _get_stains()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var room_cells: Array[Vector2i] = []
	if not rooms.is_empty():
		for c in cells:
			for r in rooms:
				if r.has_point(c):
					room_cells.append(c)
					break

	# Deeper levels: slightly bigger and brighter, but never larger than about one cell
	var t := clampf((level - 1) / 9.0, 0.0, 1.0)
	var max_cells := lerpf(0.7, 1.1, t)
	var glow := lerpf(0.8, 1.4, t)
	for i in count:
		var pool := room_cells if (not room_cells.is_empty() and rng.randf() < 0.5) else cells
		var cell: Vector2i = pool[rng.randi() % pool.size()]
		var stain: Dictionary = stains[rng.randi() % stains.size()]
		var d := Decal.new()
		var s := rng.randf_range(0.35, max_cells) * cell_size
		d.size = Vector3(s, DECAL_HEIGHT, s)
		d.texture_albedo = stain["albedo"]
		d.texture_emission = stain["emission"]
		d.emission_energy = glow * rng.randf_range(0.8, 1.1)
		d.albedo_mix = 1.0
		d.normal_fade = 0.6                   # don't streak down walls, legs and barrels
		d.upper_fade = 0.4
		d.lower_fade = 0.4
		root.add_child(d)
		# Nudge off the cell centre, so patches don't line up on the grid
		var jitter := Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4)) * cell_size
		d.global_position = to_world.call(cell) + jitter
		d.global_rotation = Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)
	return root


static func _get_stains() -> Array[Dictionary]:
	if not custom_stains.is_empty():
		return custom_stains
	if _stains.is_empty():
		for i in VARIANTS:
			_stains.append(_make_stain(1009 + i * 7919))
	return _stains


## One patch: noise shaped into a blob that fades out before the texture's edge. Inside, black
## void with a faint nebula and a few stars; around it, a thin soft violet rim.
static func _make_stain(noise_seed: int) -> Dictionary:
	var shape := FastNoiseLite.new()
	shape.seed = noise_seed
	shape.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shape.frequency = 0.045
	shape.fractal_octaves = 4
	var nebula := FastNoiseLite.new()
	nebula.seed = noise_seed + 1
	nebula.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nebula.frequency = 0.07
	nebula.fractal_octaves = 3
	var albedo := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var emission := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var half := TEX_SIZE * 0.5
	var threshold := 0.42
	var inside_of := PackedFloat32Array()
	inside_of.resize(TEX_SIZE * TEX_SIZE)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var v := _blob(shape, x, y, half)
			var a := smoothstep(threshold, threshold + 0.08, v)
			albedo.set_pixel(x, y, Color(COL_VOID, COL_VOID.a * a))
			var rim := smoothstep(threshold - 0.03, threshold + 0.02, v) \
					* (1.0 - smoothstep(threshold + 0.03, threshold + 0.09, v))
			var inside := smoothstep(threshold + 0.06, threshold + 0.16, v)
			inside_of[y * TEX_SIZE + x] = inside
			var n := nebula.get_noise_2d(x, y) * 0.5 + 0.5
			var cloud := smoothstep(0.5, 0.85, n) * inside * 0.3
			var col := COL_RIM * rim * 0.7 + COL_NEBULA_A.lerp(COL_NEBULA_B, n) * cloud
			emission.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))
	# Stars: single pixels, a few brighter 2x2 ones, only well inside the void
	var stars := RandomNumberGenerator.new()
	stars.seed = noise_seed
	for i in 40:
		var x := stars.randi_range(2, TEX_SIZE - 3)
		var y := stars.randi_range(2, TEX_SIZE - 3)
		if inside_of[y * TEX_SIZE + x] < 0.9:
			continue
		var b := stars.randf_range(0.5, 1.0)
		var big := stars.randf() < 0.2
		for dy in (2 if big else 1):
			for dx in (2 if big else 1):
				emission.set_pixel(x + dx, y + dy, Color(COL_STAR.r * b, COL_STAR.g * b, COL_STAR.b * b, 1.0))
	return {"albedo": ImageTexture.create_from_image(albedo),
		"emission": ImageTexture.create_from_image(emission)}


## Noise in 0..1, pulled down towards the edge of the texture so the blob never gets cut off.
static func _blob(noise: FastNoiseLite, x: int, y: int, half: float) -> float:
	var r := Vector2(x - half, y - half).length() / half
	var falloff := 1.0 - smoothstep(0.35, 0.95, r)
	return (noise.get_noise_2d(x, y) * 0.5 + 0.5) * falloff * 1.35
