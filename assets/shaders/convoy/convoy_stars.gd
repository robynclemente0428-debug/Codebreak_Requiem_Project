class_name ConvoyStars
extends RefCounted
## Fallback star textures for convoy_void.gdshader, made in code. The Act II convoy uses the
## painted ones in assets/textures/convoy; ConvoyMotion only fills in these when a material
## has no far_tex / near_tex. Both tile seamlessly.
##   far()   opaque: near-black space, a faint nebula and many dim pixel stars (slow layer)
##   near()  transparent: fewer, brighter stars, some 2x2 or with a cross glint (fast layer)
## Seeded, so they look the same every time. Built once and kept.

const SIZE := 256

static var _far: ImageTexture
static var _near: ImageTexture


static func far() -> ImageTexture:
	if _far == null:
		_far = _make_far(SIZE, 7)
	return _far


static func near() -> ImageTexture:
	if _near == null:
		_near = _make_near(SIZE, 11)
	return _near


static func _make_far(size: int, seed: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var base := Color(0.005, 0.004, 0.02)
	var neb_a := Color(0.06, 0.10, 0.40)
	var neb_b := Color(0.30, 0.06, 0.45)
	for y in size:
		for x in size:
			# Tileable noise: sample on a torus by blending the four wrapped corners
			var fx := float(x) / size
			var fy := float(y) / size
			var n := (noise.get_noise_2d(x, y) * (1.0 - fx) * (1.0 - fy)
					+ noise.get_noise_2d(x - size, y) * fx * (1.0 - fy)
					+ noise.get_noise_2d(x, y - size) * (1.0 - fx) * fy
					+ noise.get_noise_2d(x - size, y - size) * fx * fy)
			var t := clampf(n * 0.5 + 0.5, 0.0, 1.0)
			var neb := neb_a.lerp(neb_b, t) * smoothstep(0.45, 0.9, t) * 0.5
			img.set_pixel(x, y, base + neb)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in 420:
		var b := rng.randf_range(0.25, 0.7)
		var tint := Color(b * rng.randf_range(0.8, 1.0), b * rng.randf_range(0.85, 1.0), b)
		img.set_pixel(rng.randi() % size, rng.randi() % size, tint)
	return ImageTexture.create_from_image(img)


static func _make_near(size: int, seed: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in 70:
		var x := rng.randi() % size
		var y := rng.randi() % size
		var warm := rng.randf() < 0.25
		var col := Color(1.0, 0.85, 0.65) if warm else Color(0.75, 0.9, 1.0)
		var kind := rng.randf()
		_dot(img, x, y, col, size)
		if kind > 0.6:                                   # a bigger star: 2x2
			_dot(img, x + 1, y, col, size)
			_dot(img, x, y + 1, col, size)
			_dot(img, x + 1, y + 1, col, size)
		elif kind > 0.45:                                # a glint: faint cross
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				_dot(img, x + d.x, y + d.y, Color(col, 0.45), size)
	return ImageTexture.create_from_image(img)


static func _dot(img: Image, x: int, y: int, col: Color, size: int) -> void:
	img.set_pixel(posmod(x, size), posmod(y, size), col)
