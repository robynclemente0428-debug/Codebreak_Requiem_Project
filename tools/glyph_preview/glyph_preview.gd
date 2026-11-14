@tool
extends Control
## Preview sheet for the gem symbols in ItemGlyph. Open glyph_preview.tscn in the editor: it
## draws every skill and support symbol at inventory size, in the skill and support colours.

const CELL := 92.0
const COLUMNS := 7
const SKILL_COL := Color(1.0, 0.82, 0.30)
const SUPPORT_COL := Color(0.35, 0.85, 1.0)


func _ready() -> void:
	custom_minimum_size = Vector2(COLUMNS * CELL + 16, 4 * (CELL + 18) + 16)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), Color(0.03, 0.06, 0.1))
	var kinds: Array = []
	for k in ItemGlyph.SKILL_GLYPHS:
		kinds.append(["gem_" + k, SKILL_COL])
	for k in ItemGlyph.SUPPORT_GLYPHS:
		kinds.append(["gem_" + k, SUPPORT_COL])
	var font := ThemeDB.fallback_font
	for i in kinds.size():
		var at := Vector2(8 + (i % COLUMNS) * CELL, 8 + (i / COLUMNS) * (CELL + 18))
		var col: Color = kinds[i][1]
		var box := Rect2(at, Vector2(CELL - 12, CELL - 12))
		draw_rect(box, Color(col, 0.12))
		draw_rect(box, Color(col, 0.6), false, 1.0)
		ItemGlyph.draw(self, kinds[i][0], Rect2(at + Vector2(10, 8), Vector2(CELL - 32, CELL - 28)), col)
		draw_string(font, at + Vector2(0, CELL + 4), String(kinds[i][0]).trim_prefix("gem_"),
			HORIZONTAL_ALIGNMENT_CENTER, CELL - 12, 11, Color(1, 1, 1, 0.7))
