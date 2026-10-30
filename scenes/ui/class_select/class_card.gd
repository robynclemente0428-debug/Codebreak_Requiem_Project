class_name ClassCard
extends Button

@onready var icon_rect: TextureRect = $HBox/Icon
@onready var name_label: Label = $HBox/VBox/NameLabel
@onready var role_label: Label = $HBox/VBox/RoleLabel


func setup(c: ClassData) -> void:
	icon_rect.texture = c.icon
	name_label.text = c.display_name
	role_label.text = c.tagline
