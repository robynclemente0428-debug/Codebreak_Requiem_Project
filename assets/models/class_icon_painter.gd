@tool
class_name ClassIconPainter
extends RefCounted
## Draws the class icons with signed-distance shapes (no art assets needed).
## Used by the generator EditorScript, which bakes the results to PNG files.
## Drawing a 128px icon takes a few hundred ms in GDScript, so bake once in the
## editor instead of painting at runtime.

const SIZE := 128

## One accent per class: pure classes use their attribute colour,
## hybrids get their own colour so every class is easy to tell apart.
const ACCENTS := {
	&"raider": Color("#FF5A3C"),      # strength
	&"rogue": Color("#39FF88"),       # dexterity
	&"enchanter": Color("#4D9DFF"),   # intelligence
	&"gladiator": Color("#FFC247"),   # strength / dexterity
	&"paladin": Color("#E04DFF"),     # strength / intelligence
	&"assassin": Color("#2EE6D6"),    # dexterity / intelligence
}

## Per-class glyph scale, so each shape fills the tile nicely.
const GLYPH_SCALE := {
	&"raider": 1.2,
	&"rogue": 1.3,
	&"enchanter": 1.0,
	&"gladiator": 1.15,
	&"paladin": 1.2,
	&"assassin": 1.1,
}

# ---------- Polygons (built once, not per pixel) ----------
const TILE := [Vector2(-60, -60), Vector2(36, -60), Vector2(60, -36),
		Vector2(60, 60), Vector2(-36, 60), Vector2(-60, 36)]
const DAGGER_BLADE := [Vector2(0, -48), Vector2(8.5, -16), Vector2(6.5, -6),
		Vector2(-6.5, -6), Vector2(-8.5, -16)]
const AXE_SPIKE := [Vector2(-3, -20), Vector2(-17, -13), Vector2(-3, -6)]
const SWORD_BLADE := [Vector2(0, -54), Vector2(8, -40), Vector2(8, -22),
		Vector2(-8, -22), Vector2(-8, -40)]
const STAR_30 := [Vector2(0, -30), Vector2(5.7, -5.7), Vector2(30, 0),
		Vector2(5.7, 5.7), Vector2(0, 30), Vector2(-5.7, 5.7),
		Vector2(-30, 0), Vector2(-5.7, -5.7)]
const STAR_17 := [Vector2(0, -17), Vector2(3.2, -3.2), Vector2(17, 0),
		Vector2(3.2, 3.2), Vector2(0, 17), Vector2(-3.2, 3.2),
		Vector2(-17, 0), Vector2(-3.2, -3.2)]
const SHIELD_OUTER := [Vector2(-26, -30), Vector2(0, -36), Vector2(26, -30),
		Vector2(26, 0), Vector2(14, 22), Vector2(0, 36), Vector2(-14, 22),
		Vector2(-26, 0)]
const SHIELD_INNER := [Vector2(-21, -25), Vector2(0, -30), Vector2(21, -25),
		Vector2(21, 0), Vector2(11, 18), Vector2(0, 30), Vector2(-11, 18),
		Vector2(-21, 0)]
const DIAMOND := [Vector2(0, -9), Vector2(9, 0), Vector2(0, 9), Vector2(-9, 0)]

static var _tile := PackedVector2Array(TILE)
static var _dagger_blade := PackedVector2Array(DAGGER_BLADE)
static var _axe_spike := PackedVector2Array(AXE_SPIKE)
static var _sword_blade := PackedVector2Array(SWORD_BLADE)
static var _star_30 := PackedVector2Array(STAR_30)
static var _star_17 := PackedVector2Array(STAR_17)
static var _shield_outer := PackedVector2Array(SHIELD_OUTER)
static var _shield_inner := PackedVector2Array(SHIELD_INNER)
static var _diamond := PackedVector2Array(DIAMOND)


static func accent_for(class_id: StringName) -> Color:
	return ACCENTS.get(class_id, Color("#00E5FF"))


## Paints the icon for a class id. `accent` defaults to the class's own colour.
static func paint(class_id: StringName, accent := Color(0, 0, 0, 0), size := SIZE) -> Image:
	if accent.a == 0.0:
		accent = accent_for(class_id)

	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var s := size / float(SIZE)
	var glyph_color := accent.lerp(Color.WHITE, 0.15)
	var edge_color := accent
	var g: float = GLYPH_SCALE.get(class_id, 1.0)

	for y in size:
		for x in size:
			# Work in a 128x128 space centred on (0, 0).
			var p := Vector2(x + 0.5, y + 0.5) / s - Vector2(SIZE, SIZE) * 0.5

			var tile_d := _poly(p, _tile)
			var tile_cov := clampf(0.5 - tile_d * s, 0.0, 1.0)
			if tile_cov <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			# Background: dark gradient, soft accent glow, faint scanlines.
			var t := (p.y + 64.0) / 128.0
			var col := Color(0.05, 0.13, 0.19).lerp(Color(0.03, 0.07, 0.11), t)
			col += accent * 0.22 * exp(-p.length_squared() / (2.0 * 34.0 * 34.0))
			if y % 2 == 1:
				col = col.darkened(0.05)

			# Glyph with outer glow.
			var d := _glyph(class_id, p / g) * g
			if d > 0.0:
				col += accent * 0.4 * exp(-d / 5.0)
			var cov := clampf(0.5 - d * s, 0.0, 1.0)
			var fill := glyph_color.lerp(Color.WHITE, 0.15 * (1.0 - t))
			col = col.lerp(fill, cov)

			# Border following the chamfered tile outline.
			var border_d := absf(tile_d + 2.5) - 1.3
			col = col.lerp(edge_color, clampf(0.5 - border_d * s, 0.0, 1.0) * 0.85)

			col.a = tile_cov
			img.set_pixel(x, y, col)
	return img


static func make_texture(class_id: StringName, accent := Color(0, 0, 0, 0), size := SIZE) -> ImageTexture:
	return ImageTexture.create_from_image(paint(class_id, accent, size))


# ---------- Glyphs (distance <= 0 means "inside the shape") ----------
static func _glyph(class_id: StringName, p: Vector2) -> float:
	match class_id:
		&"raider": return _raider(p)
		&"rogue": return _rogue(p)
		&"enchanter": return _enchanter(p)
		&"gladiator": return _gladiator(p)
		&"paladin": return _paladin(p)
		&"assassin": return _assassin(p)
	return _circle(p, Vector2.ZERO, 24.0)   # unknown class: plain disc


## STRENGTH: battle axe.
static func _raider(p: Vector2) -> float:
	var q := p.rotated(-0.5) + Vector2(12, 0)
	var handle := _seg(q, Vector2(0, -36), Vector2(0, 38), 3.6)
	var head := maxf(_circle(q, Vector2(14, -14), 26.0), -_circle(q, Vector2(-4, -14), 22.0))
	var spike := _poly(q, _axe_spike)
	var pommel := _circle(q, Vector2(0, 40), 5.5)
	return minf(minf(handle, head), minf(spike, pommel))


## DEXTERITY: two crossed daggers.
static func _rogue(p: Vector2) -> float:
	var front := _dagger(p.rotated(0.6) + Vector2(0, -10))
	var back := _dagger(p.rotated(-0.6) + Vector2(0, -10))
	back = maxf(back, -(front - 3.0))      # gap where the front blade crosses
	return minf(front, back)


## INTELLIGENCE: four-point star with an orbit ring and nodes.
static func _enchanter(p: Vector2) -> float:
	var star := _poly(p, _star_30)
	var ring := absf(p.length() - 40.0) - 1.3
	var nodes := 1000.0
	for a in [-PI / 2.0, PI / 6.0, 5.0 * PI / 6.0]:
		nodes = minf(nodes, _circle(p, Vector2.from_angle(a) * 40.0, 4.6))
	return minf(minf(star, ring), nodes)


## STRENGTH + DEXTERITY: sword rising out of a round shield.
static func _gladiator(p: Vector2) -> float:
	var q := p + Vector2(0, -6)
	var c := Vector2(0, 16)
	var shield := maxf(_circle(q, c, 27.0), -_circle(q, c, 20.5))
	shield = minf(shield, _circle(q, c, 8.0))
	var sword := minf(_poly(q, _sword_blade), _box(q, Vector2(0, -18), Vector2(17, 3.0)))
	sword = maxf(sword, -(_circle(q, c, 27.0) + 3.5))   # gap around the shield
	return minf(shield, sword)


## STRENGTH + INTELLIGENCE: kite shield carrying an arcane star.
static func _paladin(p: Vector2) -> float:
	var outline := maxf(_poly(p, _shield_outer), -_poly(p, _shield_inner))
	var star := _poly(p + Vector2(0, 2), _star_17)
	return minf(outline, star)


## DEXTERITY + INTELLIGENCE: targeting reticle.
static func _assassin(p: Vector2) -> float:
	var ring := absf(p.length() - 27.0) - 1.3
	var q := p.abs()
	var ticks := minf(_seg(q, Vector2(12, 0), Vector2(44, 0), 1.7),
			_seg(q, Vector2(0, 12), Vector2(0, 44), 1.7))
	var core := _poly(p, _diamond)
	return minf(minf(ring, ticks), core)


static func _dagger(q: Vector2) -> float:
	var blade := _poly(q, _dagger_blade)
	var guard := _box(q, Vector2(0, -4), Vector2(15, 3.0))
	var grip := _seg(q, Vector2(0, -2), Vector2(0, 20), 3.6)
	var pommel := _circle(q, Vector2(0, 25), 5.0)
	return minf(minf(blade, guard), minf(grip, pommel))


# ---------- Signed distance helpers ----------
static func _circle(p: Vector2, c: Vector2, r: float) -> float:
	return p.distance_to(c) - r


static func _seg(p: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length() - r


static func _box(p: Vector2, c: Vector2, half: Vector2) -> float:
	var d := (p - c).abs() - half
	return d.max(Vector2.ZERO).length() + minf(maxf(d.x, d.y), 0.0)


static func _poly(p: Vector2, v: PackedVector2Array) -> float:
	var n := v.size()
	var d := (p - v[0]).dot(p - v[0])
	var sgn := 1.0
	var j := n - 1
	for i in n:
		var e := v[j] - v[i]
		var w := p - v[i]
		var b := w - e * clampf(w.dot(e) / e.dot(e), 0.0, 1.0)
		d = minf(d, b.dot(b))
		var c1 := p.y >= v[i].y
		var c2 := p.y < v[j].y
		var c3 := e.x * w.y > e.y * w.x
		if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
			sgn = -sgn
		j = i
	return sgn * sqrt(d)
