class_name CyberDialog
extends RefCounted
## Gives a ConfirmationDialog the cyber look: dark panel, cyan chamfer-style border, no grey title bar.
## Usage:  CyberDialog.style(my_dialog)

const ACCENT := Color("#00E5FF")


static func style(d: ConfirmationDialog) -> void:
	d.borderless = true                  # removes the grey title bar and the X; the panel below is the whole look
	d.min_size = Vector2i(640, 0)

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.02, 0.05, 0.09, 0.96)
	panel.border_color = ACCENT
	panel.set_border_width_all(2)
	panel.corner_radius_top_right = 18
	panel.corner_radius_bottom_left = 18
	panel.shadow_color = Color(ACCENT, 0.35)
	panel.shadow_size = 12
	panel.set_content_margin_all(28)
	d.add_theme_stylebox_override("panel", panel)

	d.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for b: Button in [d.get_ok_button(), d.get_cancel_button()]:
		b.custom_minimum_size = Vector2(190, 56)
		# the OK button is focused by default, which is what drew the grey box
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
