class_name ClassCard
extends Button

@onready var icon_rect: TextureRect = $HBox/Icon
@onready var name_label: Label = $HBox/VBox/NameLabel
@onready var role_label: Label = $HBox/VBox/RoleLabel


func setup(c: ClassData) -> void:
	icon_rect.texture = c.get_icon()
	name_label.text = c.display_name
	role_label.text = c.tagline
	tooltip_text = c.tagline
	toggled.connect(_show_selected)
	_show_selected(button_pressed)


## The chosen class reads brighter than the rest.
func _show_selected(on: bool) -> void:
	name_label.add_theme_color_override("font_color", Color(0, 1, 1, 1.0 if on else 0.7))
	role_label.add_theme_color_override("font_color", Color(0.85, 0.97, 1.0, 0.9) if on else Color(0, 1, 1, 0.6))
