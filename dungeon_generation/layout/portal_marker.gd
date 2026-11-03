@tool
class_name PortalMarker
extends DungeonMarker
## A portal in a generated level. Rotate the marker (Y axis) to turn the portal: players
## arriving through it step out on the side the blue arrow points to (the marker's -Z,
## Godot's "forward"), exit_distance metres from the portal, so it looks like they came out of it.
@export_file("*.tscn") var target_area: String:
	set(v):
		target_area = v
		_refresh_portal_preview()
@export var target_spawn: StringName = &"default":     # spawn id in the TARGET area
	set(v):
		target_spawn = v
		_refresh_portal_preview()
## Above 0 when this portal leads into another dungeon: the level of that dungeon's instance.
@export var dungeon_level: int = 0:
	set(v):
		dungeon_level = v
		_refresh_portal_preview()
## A quest key that opens this portal (an id from QuestItems, e.g. "brood_key"). Until the
## player has it the portal is sealed: red, and it turns them back. Empty = always open.
@export var sealed_by_key: String = ""
## Also open once this quest is done, for saves from before the seal existed.
@export var open_after_quest: String = ""
## Story routing, see Portal: hidden until this quest starts...
@export var shown_after_quest: String = ""
## ...or, once this quest starts, leads to routed_area / routed_spawn instead.
@export var route_after_quest: String = ""
@export_file("*.tscn") var routed_area: String = ""
@export var routed_spawn: StringName = &"default"
## Convoy stops: the waypoint id this portal marks cleared when used (its exit), which opens the
## next stop on the route terminal (Waypoints.clear_stop). Empty = none.
@export var clears_stop: String = ""
@export var arrival_spawn_id: StringName = &"exit"        # players arriving here with this id step out of this portal
## How far in front of the portal arriving players appear, in metres.
@export_range(0.5, 6.0, 0.1) var exit_distance: float = 1.6:
	set(v):
		exit_distance = v
		_refresh_arrow()

## Editor only: the real portal model, where and how the game will place it.
const PORTAL_SCENE_PATH := "res://scenes/map/map_management/portal.tscn"

var _arrow: MeshInstance3D
var _portal_preview: Node3D
var _label: Label3D

func _marker_color() -> Color: return Color(0.3, 0.6, 1.0, 0.3)


func _ready() -> void:
	super._ready()
	_refresh_arrow()
	_refresh_portal_preview()


## The base class moves the room box when the marker moves; the portal preview follows it.
func _snap_preview() -> void:
	super._snap_preview()
	_place_portal_preview()


## Editor only: shows the actual portal and where it leads. Not saved (no owner).
func _refresh_portal_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _portal_preview == null and ResourceLoader.exists(PORTAL_SCENE_PATH):
		var scene := load(PORTAL_SCENE_PATH) as PackedScene
		if scene != null:
			_portal_preview = scene.instantiate() as Node3D
			_portal_preview.top_level = true             # placed by hand, like the game does
			_portal_preview.process_mode = Node.PROCESS_MODE_DISABLED
			add_child(_portal_preview)
	if _label == null:
		_label = Label3D.new()
		_label.top_level = true
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.font_size = 64
		_label.pixel_size = 0.01
		_label.outline_size = 12
		_label.modulate = Color(0.55, 0.85, 1.0)
		add_child(_label)
	_label.text = _destination_text()
	_place_portal_preview()


## "-> ACT 1 SPILLWAY · spillway_in · LVL 2"
func _destination_text() -> String:
	if target_area == "":
		return "PORTAL: NO TARGET"
	var path := target_area
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		if ResourceUID.has_id(id):
			path = ResourceUID.get_id_path(id)
	var text := "-> " + path.get_file().get_basename().replace("_", " ").to_upper()
	text += "  ·  " + String(target_spawn)
	if dungeon_level > 0:
		text += "  ·  LVL %d" % dungeon_level
	return text


## Same spot and facing as Dungeon._place_portal: the centre of the marker's room, turned by
## the marker's yaw (PortalMarker.portal_basis).
func _place_portal_preview() -> void:
	if not is_inside_tree():
		return
	var at := global_position
	if _preview != null:
		at = Vector3(_preview.global_position.x, global_position.y, _preview.global_position.z)
	if _portal_preview != null:
		_portal_preview.global_position = at
		_portal_preview.global_basis = portal_basis(global_rotation.y)
	if _label != null:
		_label.global_position = at + Vector3.UP * 3.4


## Editor only: an arrow showing where arriving players step out.
func _refresh_arrow() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _arrow == null:
		_arrow = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.8, 1.0, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_arrow.material_override = mat
		add_child(_arrow)                              # no owner, so it is never saved
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.15, 0.1, exit_distance)
	_arrow.mesh = shaft
	_arrow.position = Vector3(0, 0.4, -exit_distance * 0.5)
	var head := _arrow.get_node_or_null("Head") as MeshInstance3D
	if head == null:
		head = MeshInstance3D.new()
		head.name = "Head"
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.35
		cone.height = 0.6
		head.mesh = cone
		head.rotation_degrees = Vector3(-90, 0, 0)     # the cone's tip along -Z
		_arrow.add_child(head)
	head.position = Vector3(0, 0, -exit_distance * 0.5)


## Turns a portal (portal.tscn walks through along its local X) to face like a marker with this
## yaw, and where arriving players stand. Both in the GridMap's local space.
static func portal_basis(yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw + PI * 0.5)


static func exit_offset(yaw: float, distance: float) -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(0, 0, -distance)
