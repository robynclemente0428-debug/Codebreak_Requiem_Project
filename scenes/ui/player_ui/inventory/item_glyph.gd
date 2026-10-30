class_name ItemGlyph
extends RefCounted
## Small vector icons that show what TYPE of item something is (sword, axe, helmet, shield...),
## drawn in code so no art is needed. Used by the inventory slots when an item has no icon.
## All shapes are drawn in a 0..1 box, so you can tweak a glyph by editing its coordinates.

const WEAPON_KINDS := ["sword", "axe", "scepter", "orb", "sniper", "rifle"]


## Which glyph an item should use, or "" if its type isn't recognised.
## Weapons are matched on their type's id / display name; gear on its equipment slot.
static func kind_for(def: ItemDefinition) -> String:
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


## An open line through the given points.
static func _line(ci: CanvasItem, o: Vector2, s: float, pts: Array, col: Color, w: float) -> void:
	ci.draw_polyline(_pts(o, s, pts), col, w, true)
