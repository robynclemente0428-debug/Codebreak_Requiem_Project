class_name GlowLabel
extends Label

@export var glow_color := Color(0.0, 0.9, 1.0)
@export var layers := 6
@export var max_radius := 28          # how far the glow spreads, in px
@export_range(0.0, 1.0) var intensity := 0.6

func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	for i in layers:
		var g := Label.new()
		g.text = text
		g.horizontal_alignment = horizontal_alignment
		g.vertical_alignment = vertical_alignment
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.show_behind_parent = true        # draw under the real text
		g.material = mat

		g.add_theme_font_override("font", get_theme_font("font"))
		g.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
		g.add_theme_color_override("font_color", Color(0, 0, 0, 0))   # outline only
		g.add_theme_color_override("font_outline_color", Color(glow_color, intensity / layers))
		g.add_theme_constant_override("outline_size", int(max_radius * float(i + 1) / layers))

		add_child(g)
		g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
