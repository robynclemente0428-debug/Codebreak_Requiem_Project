class_name ItemGlyph
extends RefCounted
## Small vector icons that show what TYPE of item something is (sword, axe, helmet, shield...),
## drawn in code so no art is needed. Used by the inventory slots when an item has no icon,
## and for the skill and support gem symbols (inventory, skill panel sockets, skill bar).
## All shapes are drawn in a 0..1 box, so you can tweak a glyph by editing its coordinates.

const WEAPON_KINDS := ["sword", "axe", "scepter", "orb", "sniper", "rifle"]


## Skill and support gems that have a symbol, by gem id. Their kind is "gem_" + the name here.
const SKILL_GLYPHS := ["strike", "slam", "blast", "shoot"]
const SUPPORT_GLYPHS := ["cleave", "many_projectiles", "explode_on_kill", "aftershock", "tremor_chain",
	"finishing_blow", "rending_wave", "variable_store", "pointer", "try_except", "fork", "breakpoint",
	"overclock", "multicast", "rollback", "for_loop"]


## Which glyph an item should use, or "" if its type isn't recognised.
## Weapons are matched on their type's id / display name; gear on its equipment slot;
## gems on their id.
static func kind_for(def: ItemDefinition) -> String:
	if def.skill_gem != null:
		return "gem_" + def.skill_gem.id if def.skill_gem.id in SKILL_GLYPHS else ""
	if def.support_gem != null:
		var name := def.support_gem.id.trim_suffix("_support")
		return "gem_" + name if name in SUPPORT_GLYPHS else ""
	if def.stim != null:
		return "stim"
	if def.weapon_type != null:
		var key := (def.weapon_type.id + " " + def.weapon_type.display_name).to_lower()
		for k in WEAPON_KINDS:
			if key.contains(k):
				return "scepter" if k == "sceptre" else k
		return ""
	if def.equipment_type != null:
		var key := (def.equipment_type.id + " " + def.equipment_type.display_name).to_lower()
		if key.contains("trinket"):
			return "trinket"
		match def.equipment_type.slot:
			EquipmentSlots.Slot.HEAD:
				return "helmet"
			EquipmentSlots.Slot.BODY:
				return "body"
			EquipmentSlots.Slot.HANDS:
				return "hands"
			EquipmentSlots.Slot.FEET:
				return "boots"
			EquipmentSlots.Slot.OFF_HAND:
				return "shield"
	return ""


## Short type label for the bottom of a slot, e.g. "SWORD".
static func type_tag(def: ItemDefinition) -> String:
	if def.stim != null:
		return "STIM"
	if def.skill_gem != null:
		return "SKILL"
	if def.support_gem != null:
		return "SUPPORT"
	if def.weapon_type != null:
		return def.weapon_type.display_name.to_upper().left(7)
	if def.equipment_type != null:
		return def.equipment_type.display_name.to_upper().left(7)
	return ""


## Draws the glyph inside `rect` on any CanvasItem. Call it from that item's _draw().
## Returns false if the kind is unknown, so the caller can fall back to something else.
static func draw(ci: CanvasItem, kind: String, rect: Rect2, col: Color) -> bool:
	var s := minf(rect.size.x, rect.size.y)
	var o := rect.position + (rect.size - Vector2(s, s)) * 0.5     # centred square
	var fill := Color(col, 0.28)
	var w := 2.5

	match kind:
		"sword":
			_shape(ci, o, s, [[0.5, 0.04], [0.6, 0.2], [0.6, 0.64], [0.4, 0.64], [0.4, 0.2]], col, fill, w)
			_line(ci, o, s, [[0.26, 0.64], [0.74, 0.64]], col, w)
			_line(ci, o, s, [[0.5, 0.64], [0.5, 0.86]], col, w)
			ci.draw_circle(_p(o, s, 0.5, 0.92), s * 0.05, col)
		"axe":
			_line(ci, o, s, [[0.38, 0.94], [0.38, 0.06]], col, w)
			_shape(ci, o, s, [[0.38, 0.14], [0.74, 0.10], [0.88, 0.30], [0.74, 0.50], [0.38, 0.46]], col, fill, w)
		"scepter":
			_shape(ci, o, s, [[0.5, 0.05], [0.65, 0.2], [0.5, 0.35], [0.35, 0.2]], col, fill, w)
			_line(ci, o, s, [[0.5, 0.35], [0.5, 0.94]], col, w)
			_line(ci, o, s, [[0.38, 0.46], [0.62, 0.46]], col, w)
		"orb":
			var c := _p(o, s, 0.5, 0.4)
			ci.draw_circle(c, s * 0.28, fill)
			ci.draw_arc(c, s * 0.28, 0.0, TAU, 32, col, w, true)
			ci.draw_arc(c, s * 0.17, deg_to_rad(200.0), deg_to_rad(270.0), 10, col, w, true)    # glint
			_shape(ci, o, s, [[0.36, 0.72], [0.64, 0.72], [0.7, 0.88], [0.3, 0.88]], col, fill, w)
		"wand":
			_line(ci, o, s, [[0.16, 0.92], [0.78, 0.22]], col, w)
			_line(ci, o, s, [[0.8, 0.06], [0.8, 0.34]], col, w)
			_line(ci, o, s, [[0.66, 0.2], [0.94, 0.2]], col, w)
		"sniper":
			_shape(ci, o, s, [[0.06, 0.44], [0.34, 0.44], [0.34, 0.6], [0.24, 0.74], [0.06, 0.62]], col, fill, w)
			_line(ci, o, s, [[0.34, 0.48], [0.96, 0.48]], col, w * 1.6)
			_shape(ci, o, s, [[0.42, 0.3], [0.7, 0.3], [0.7, 0.4], [0.42, 0.4]], col, fill, w)
			_line(ci, o, s, [[0.46, 0.52], [0.5, 0.7]], col, w)
		"rifle":
			_shape(ci, o, s, [[0.06, 0.44], [0.34, 0.44], [0.34, 0.6], [0.24, 0.74], [0.06, 0.62]], col, fill, w)
			_line(ci, o, s, [[0.34, 0.48], [0.96, 0.48]], col, w * 1.6)
			_shape(ci, o, s, [[0.42, 0.3], [0.7, 0.3], [0.7, 0.4], [0.42, 0.4]], col, fill, w)
			_line(ci, o, s, [[0.46, 0.52], [0.5, 0.7]], col, w)
		"helmet":
			_shape(ci, o, s, [[0.2, 0.72], [0.2, 0.42], [0.3, 0.2], [0.5, 0.1], [0.7, 0.2], [0.8, 0.42],
				[0.8, 0.72], [0.62, 0.72], [0.62, 0.52], [0.38, 0.52], [0.38, 0.72]], col, fill, w)
		"body":
			_shape(ci, o, s, [[0.12, 0.22], [0.34, 0.1], [0.42, 0.2], [0.58, 0.2], [0.66, 0.1], [0.88, 0.22],
				[0.8, 0.5], [0.7, 0.9], [0.3, 0.9], [0.2, 0.5]], col, fill, w)
			_line(ci, o, s, [[0.5, 0.26], [0.5, 0.9]], col, w)
		"hands":
			_shape(ci, o, s, [[0.28, 0.44], [0.72, 0.44], [0.72, 0.84], [0.28, 0.84]], col, fill, w)
			_line(ci, o, s, [[0.34, 0.44], [0.34, 0.22]], col, w)
			_line(ci, o, s, [[0.45, 0.44], [0.45, 0.16]], col, w)
			_line(ci, o, s, [[0.56, 0.44], [0.56, 0.16]], col, w)
			_line(ci, o, s, [[0.67, 0.44], [0.67, 0.22]], col, w)
			_line(ci, o, s, [[0.28, 0.56], [0.14, 0.42]], col, w)
		"boots":
			_shape(ci, o, s, [[0.34, 0.1], [0.64, 0.1], [0.64, 0.56], [0.9, 0.72], [0.9, 0.9], [0.28, 0.9]],
				col, fill, w)
		"shield":
			_shape(ci, o, s, [[0.5, 0.08], [0.84, 0.2], [0.8, 0.58], [0.5, 0.92], [0.2, 0.58], [0.16, 0.2]],
				col, fill, w)
			_line(ci, o, s, [[0.5, 0.2], [0.5, 0.76]], col, w)
			_line(ci, o, s, [[0.3, 0.4], [0.7, 0.4]], col, w)
		"stim":                                                   # an injector: cap, vial, needle
			_shape(ci, o, s, [[0.36, 0.06], [0.64, 0.06], [0.64, 0.18], [0.36, 0.18]], col, fill, w)
			_shape(ci, o, s, [[0.32, 0.18], [0.68, 0.18], [0.68, 0.72], [0.32, 0.72]], col, fill, w)
			_line(ci, o, s, [[0.32, 0.38], [0.68, 0.38]], col, w)
			_line(ci, o, s, [[0.32, 0.55], [0.68, 0.55]], col, w)
			_shape(ci, o, s, [[0.42, 0.72], [0.58, 0.72], [0.54, 0.8], [0.46, 0.8]], col, fill, w)
			_line(ci, o, s, [[0.5, 0.8], [0.5, 0.96]], col, w)
		"trinket":
			_line(ci, o, s, [[0.5, 0.06], [0.5, 0.26]], col, w)
			_shape(ci, o, s, [[0.5, 0.26], [0.76, 0.52], [0.5, 0.86], [0.24, 0.52]], col, fill, w)
			_line(ci, o, s, [[0.24, 0.52], [0.76, 0.52]], col, w)

		# ---- skill gems ----
		"gem_strike":                                             # a sword swing and its trail
			_swoosh(ci, o, s, Vector2(0.12, 0.88), 0.76, -88.0, -2.0, 0.26, col, fill, w)
			ci.draw_polyline(_arc_pts(o, s, Vector2(0.12, 0.88), 0.4, -76.0, -14.0, 10),
				Color(col, 0.6), w, true)
		"gem_slam":                                               # down onto the ground
			_shape(ci, o, s, [[0.42, 0.06], [0.58, 0.06], [0.58, 0.4], [0.72, 0.4], [0.5, 0.66],
				[0.28, 0.4], [0.42, 0.4]], col, fill, w)
			_line(ci, o, s, [[0.06, 0.82], [0.94, 0.82]], col, w)
			_line(ci, o, s, [[0.32, 0.74], [0.16, 0.62]], col, w)
			_line(ci, o, s, [[0.68, 0.74], [0.84, 0.62]], col, w)
		"gem_blast":                                              # a flying orb with a trail
			var c := _p(o, s, 0.64, 0.38)
			ci.draw_circle(c, s * 0.2, fill)
			ci.draw_arc(c, s * 0.2, 0.0, TAU, 28, col, w, true)
			ci.draw_arc(c, s * 0.11, deg_to_rad(190.0), deg_to_rad(260.0), 8, col, w, true)
			_line(ci, o, s, [[0.06, 0.72], [0.36, 0.42]], col, w)
			_line(ci, o, s, [[0.12, 0.92], [0.46, 0.58]], col, w)
			_line(ci, o, s, [[0.32, 0.94], [0.56, 0.7]], col, w)
		"gem_shoot":                                              # a crosshair
			var c := _p(o, s, 0.5, 0.5)
			ci.draw_circle(c, s * 0.3, fill)
			ci.draw_arc(c, s * 0.3, 0.0, TAU, 32, col, w, true)
			_line(ci, o, s, [[0.5, 0.06], [0.5, 0.32]], col, w)
			_line(ci, o, s, [[0.5, 0.68], [0.5, 0.94]], col, w)
			_line(ci, o, s, [[0.06, 0.5], [0.32, 0.5]], col, w)
			_line(ci, o, s, [[0.68, 0.5], [0.94, 0.5]], col, w)
			ci.draw_circle(c, s * 0.05, col)

		# ---- support gems ----
		"gem_cleave":                                             # a wide fan
			var pts := PackedVector2Array([_p(o, s, 0.5, 0.88)])
			pts.append_array(_arc_pts(o, s, Vector2(0.5, 0.88), 0.72, -145.0, -35.0, 14))
			_poly(ci, pts, col, fill, w)
			ci.draw_polyline(_arc_pts(o, s, Vector2(0.5, 0.88), 0.44, -145.0, -35.0, 10), col, w, true)
		"gem_many_projectiles":                                   # three arrows spreading out
			for tip in [Vector2(0.14, 0.22), Vector2(0.5, 0.08), Vector2(0.86, 0.22)]:
				_line(ci, o, s, [[0.5, 0.92], [tip.x, tip.y]], col, w)
				_head(ci, _p(o, s, tip.x, tip.y), (tip - Vector2(0.5, 0.92)).normalized(), s * 0.14, col)
		"gem_explode_on_kill":                                    # a burst
			var pts := PackedVector2Array()
			for i in 16:
				var a := deg_to_rad(i * 22.5 - 90.0)
				var r := 0.46 if i % 2 == 0 else 0.2
				pts.append(_p(o, s, 0.5 + cos(a) * r, 0.5 + sin(a) * r))
			_poly(ci, pts, col, fill, w)
			ci.draw_circle(_p(o, s, 0.5, 0.5), s * 0.07, col)
		"gem_aftershock":                                         # ripples from the ground
			_line(ci, o, s, [[0.04, 0.84], [0.96, 0.84]], col, w)
			var c := _p(o, s, 0.5, 0.84)
			ci.draw_arc(c, s * 0.14, PI, TAU, 10, col, w, true)
			ci.draw_arc(c, s * 0.29, PI, TAU, 16, Color(col, 0.8), w, true)
			ci.draw_arc(c, s * 0.44, PI, TAU, 22, Color(col, 0.55), w, true)
		"gem_tremor_chain":                                       # three linked impacts
			var nodes := [Vector2(0.18, 0.78), Vector2(0.5, 0.26), Vector2(0.82, 0.74)]
			for i in 2:
				var a: Vector2 = nodes[i]
				var b: Vector2 = nodes[i + 1]
				var d := (b - a).normalized() * 0.13
				_line(ci, o, s, [[a.x + d.x, a.y + d.y], [b.x - d.x, b.y - d.y]], col, w)
			for n in nodes:
				var c := _p(o, s, n.x, n.y)
				ci.draw_circle(c, s * 0.12, fill)
				ci.draw_arc(c, s * 0.12, 0.0, TAU, 18, col, w, true)
		"gem_finishing_blow":                                     # crossed slashes, on the 3rd
			_line(ci, o, s, [[0.16, 0.1], [0.84, 0.72]], col, w * 1.5)
			_line(ci, o, s, [[0.84, 0.1], [0.16, 0.72]], col, w * 1.5)
			ci.draw_circle(_p(o, s, 0.3, 0.92), s * 0.04, Color(col, 0.6))
			ci.draw_circle(_p(o, s, 0.5, 0.92), s * 0.04, Color(col, 0.6))
			ci.draw_circle(_p(o, s, 0.7, 0.92), s * 0.07, col)
		"gem_rending_wave":                                       # a flying crescent blade
			_swoosh(ci, o, s, Vector2(0.24, 0.5), 0.46, -70.0, 70.0, 0.17, col, fill, w)
			_line(ci, o, s, [[0.04, 0.36], [0.3, 0.36]], Color(col, 0.7), w)
			_line(ci, o, s, [[0.0, 0.5], [0.34, 0.5]], Color(col, 0.7), w)
			_line(ci, o, s, [[0.04, 0.64], [0.3, 0.64]], Color(col, 0.7), w)
		"gem_variable_store":                                     # a charge cell
			_shape(ci, o, s, [[0.1, 0.28], [0.8, 0.28], [0.8, 0.72], [0.1, 0.72]], col, fill, w)
			_shape(ci, o, s, [[0.8, 0.4], [0.9, 0.4], [0.9, 0.6], [0.8, 0.6]], col, fill, w)
			for x in [0.17, 0.36, 0.55]:
				ci.draw_rect(Rect2(_p(o, s, x, 0.35), Vector2(0.14, 0.3) * s), col)
		"gem_pointer":                                            # from here to the next target
			ci.draw_circle(_p(o, s, 0.16, 0.84), s * 0.08, col)
			_line(ci, o, s, [[0.16, 0.84], [0.16, 0.5], [0.62, 0.5], [0.62, 0.3]], col, w)
			_head(ci, _p(o, s, 0.62, 0.16), Vector2.UP, s * 0.16, col)
			_shape(ci, o, s, [[0.74, 0.62], [0.94, 0.62], [0.94, 0.82], [0.74, 0.82]], col, fill, w)
		"gem_try_except":                                         # { ! }
			_line(ci, o, s, [[0.32, 0.1], [0.22, 0.14], [0.22, 0.42], [0.1, 0.5], [0.22, 0.58],
				[0.22, 0.86], [0.32, 0.9]], col, w)
			_line(ci, o, s, [[0.68, 0.1], [0.78, 0.14], [0.78, 0.42], [0.9, 0.5], [0.78, 0.58],
				[0.78, 0.86], [0.68, 0.9]], col, w)
			_line(ci, o, s, [[0.5, 0.22], [0.5, 0.6]], col, w * 1.4)
			ci.draw_circle(_p(o, s, 0.5, 0.76), s * 0.055, col)
		"gem_fork":                                               # one shot splits in two
			_line(ci, o, s, [[0.5, 0.94], [0.5, 0.54]], col, w)
			_line(ci, o, s, [[0.5, 0.54], [0.2, 0.2]], col, w)
			_line(ci, o, s, [[0.5, 0.54], [0.8, 0.2]], col, w)
			_head(ci, _p(o, s, 0.16, 0.14), Vector2(-0.66, -0.75).normalized(), s * 0.15, col)
			_head(ci, _p(o, s, 0.84, 0.14), Vector2(0.66, -0.75).normalized(), s * 0.15, col)
			ci.draw_circle(_p(o, s, 0.5, 0.54), s * 0.07, col)
		"gem_breakpoint":                                         # the debugger's red dot
			var pts := PackedVector2Array()
			for i in 8:
				var a := deg_to_rad(i * 45.0 + 22.5)
				pts.append(_p(o, s, 0.5 + cos(a) * 0.42, 0.5 + sin(a) * 0.42))
			_poly(ci, pts, col, fill, w)
			ci.draw_circle(_p(o, s, 0.5, 0.5), s * 0.2, col)
		"gem_overclock":                                          # a gauge in the red
			var c := _p(o, s, 0.5, 0.68)
			ci.draw_arc(c, s * 0.42, PI, TAU, 24, col, w, true)
			for deg in [180.0, 225.0, 270.0, 315.0, 360.0]:
				var a := deg_to_rad(deg)
				ci.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.32, c + Vector2(cos(a), sin(a)) * s * 0.42,
					col, w, true)
			var needle := deg_to_rad(-30.0)
			ci.draw_line(c, c + Vector2(cos(needle), sin(needle)) * s * 0.36, col, w * 1.3, true)
			ci.draw_circle(c, s * 0.07, col)
			_line(ci, o, s, [[0.14, 0.86], [0.86, 0.86]], col, w)
		"gem_multicast":                                          # you and your hologram
			_shape(ci, o, s, [[0.38, 0.08], [0.64, 0.38], [0.38, 0.68], [0.12, 0.38]],
				Color(col, 0.45), Color(col, 0.1), w)
			_shape(ci, o, s, [[0.62, 0.32], [0.88, 0.62], [0.62, 0.92], [0.36, 0.62]], col, fill, w)
		"gem_rollback":                                           # a clock, turned back
			var c := _p(o, s, 0.5, 0.52)
			ci.draw_arc(c, s * 0.38, deg_to_rad(-60.0), deg_to_rad(240.0), 30, col, w, true)
			var a := deg_to_rad(-60.0)
			_head(ci, c + Vector2(cos(a), sin(a)) * s * 0.38, Vector2(sin(a), -cos(a)), s * 0.16, col)
			_line(ci, o, s, [[0.5, 0.52], [0.5, 0.32]], col, w)
			_line(ci, o, s, [[0.5, 0.52], [0.64, 0.6]], col, w)
		"gem_for_loop":                                           # round and round
			var c := _p(o, s, 0.5, 0.5)
			ci.draw_arc(c, s * 0.34, deg_to_rad(200.0), deg_to_rad(330.0), 16, col, w * 1.2, true)
			ci.draw_arc(c, s * 0.34, deg_to_rad(20.0), deg_to_rad(150.0), 16, col, w * 1.2, true)
			for deg in [330.0, 150.0]:
				var a := deg_to_rad(deg)
				_head(ci, c + Vector2(cos(a), sin(a)) * s * 0.34, Vector2(-sin(a), cos(a)), s * 0.16, col)
			ci.draw_circle(c, s * 0.06, col)
		_:
			return false
	return true


# ---------- helpers ----------
static func _p(o: Vector2, s: float, x: float, y: float) -> Vector2:
	return o + Vector2(x, y) * s


static func _pts(o: Vector2, s: float, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_p(o, s, p[0], p[1]))
	return out


## A filled, outlined closed shape.
static func _shape(ci: CanvasItem, o: Vector2, s: float, pts: Array, col: Color, fill: Color, w: float) -> void:
	var poly := _pts(o, s, pts)
	ci.draw_colored_polygon(poly, fill)
	var outline := PackedVector2Array(poly)
	outline.append(poly[0])
	ci.draw_polyline(outline, col, w, true)


## A filled, outlined closed shape from points already in pixels.
static func _poly(ci: CanvasItem, poly: PackedVector2Array, col: Color, fill: Color, w: float) -> void:
	ci.draw_colored_polygon(poly, fill)
	var outline := PackedVector2Array(poly)
	outline.append(poly[0])
	ci.draw_polyline(outline, col, w, true)


## Points along an arc (degrees; 0 = right, 90 = down), centre and radius in the 0..1 box.
static func _arc_pts(o: Vector2, s: float, c: Vector2, r: float, from_deg: float, to_deg: float,
		steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
		out.append(_p(o, s, c.x + cos(a) * r, c.y + sin(a) * r))
	return out


## A blade-like crescent along an arc: full `thick` in the middle, pointed at both ends.
static func _swoosh(ci: CanvasItem, o: Vector2, s: float, c: Vector2, r: float, from_deg: float,
		to_deg: float, thick: float, col: Color, fill: Color, w: float) -> void:
	const STEPS := 16
	var outer := _arc_pts(o, s, c, r, from_deg, to_deg, STEPS)
	var poly := PackedVector2Array(outer)
	for i in range(STEPS - 1, 0, -1):
		var t := float(i) / STEPS
		var a := deg_to_rad(lerpf(from_deg, to_deg, t))
		var ri := r - thick * sin(PI * t)
		poly.append(_p(o, s, c.x + cos(a) * ri, c.y + sin(a) * ri))
	_poly(ci, poly, col, fill, w)


## A filled arrowhead with its point at `tip`, pointing along `dir`.
static func _head(ci: CanvasItem, tip: Vector2, dir: Vector2, size: float, col: Color) -> void:
	var back := tip - dir * size
	var side := Vector2(-dir.y, dir.x) * size * 0.6
	ci.draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), col)


## An open line through the given points.
static func _line(ci: CanvasItem, o: Vector2, s: float, pts: Array, col: Color, w: float) -> void:
	ci.draw_polyline(_pts(o, s, pts), col, w, true)
