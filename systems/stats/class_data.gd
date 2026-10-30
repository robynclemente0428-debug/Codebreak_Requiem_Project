@tool
class_name ClassData
extends Resource
## One .tres per class in res://data/classes/.
## @tool lets the editor create and save these resources from an EditorScript.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var sort_order: int = 0            # order shown in Class Select
@export var tagline: String                 # e.g. "Breaches systems from range"x
@export var preview_scene: PackedScene      # the 3D character model
@export var accent_color := Color("#00E5FF")
@export_group('Starting attributes')
@export var strength: int = 8
@export var dexterity: int = 8
@export var intelligence: int = 8

@export_group('Appearance')
@export var model_scene: PackedScene       # a .glb or .tscn: skeleton + mesh (AnimationPlayer optional)
@export var model_scale: float = 1.0       # tune so every class matches the collision shape
@export var model_offset: Vector3 = Vector3.ZERO

@export_group('Loadout')
@export var starting_weapon: ItemDefinition
@export var starting_skill_gem: ItemDefinition   # replaces starting_skill_id


## The class's innate passive (res://data/class_traits/<id>.tres), or null if it has none.
func get_trait() -> ClassTrait:
	return ClassTrait.for_class(String(id))


## Copied into the save file when a character is created.
func get_attributes() -> Dictionary:
	return {
		Attr.STRENGTH: strength,
		Attr.DEXTERITY: dexterity,
		Attr.INTELLIGENCE: intelligence,
	}

## The icon to show in the UI. Uses the `icon` property if you assigned one,
## otherwise the PNG baked by tools/generate_classes.gd.
func get_icon() -> Texture2D:
	if icon != null:
		return icon
	var path := "res://assets/icons/classes/%s.png" % id
	if ResourceLoader.exists(path):
		return load(path)
	return null
