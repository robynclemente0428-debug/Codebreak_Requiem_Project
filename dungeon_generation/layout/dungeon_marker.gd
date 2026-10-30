@tool
class_name DungeonMarker
extends Marker3D

@export var room_size: Vector2i = Vector2i(5, 5):
	set(v):
		room_size = Vector2i(maxi(v.x, 3), maxi(v.y, 3))
		_refresh_preview()
@export var preview_cell_size: float = 2.0     # match DungeonTheme.cell_size

var _preview: MeshInstance3D

func _ready() -> void:
	set_notify_transform(true)
	_refresh_preview()

func _marker_color() -> Color:
	return Color(1, 1, 1, 0.25)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_snap_preview()

func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		_preview.top_level = true                      # ignore marker rotation/scale
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _marker_color()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_preview.material_override = mat
		add_child(_preview)                            # no owner, so it is never saved
	var box := BoxMesh.new()
	var fp := _footprint()
	box.size = Vector3(fp.x * preview_cell_size, 0.3, fp.y * preview_cell_size)
	_preview.mesh = box
	_snap_preview()

func _footprint() -> Vector2i:
	return room_size

func _snap_preview() -> void:
	if _preview == null or not is_inside_tree():
		return
	var cs := preview_cell_size
	var p := global_position
	var cell := Vector2i(floori(p.x / cs), floori(p.z / cs))
	var fp := _footprint()
	var origin := cell - fp / 2             # same maths as the reader
	_preview.global_position = Vector3(
		(origin.x + fp.x * 0.5) * cs, p.y, (origin.y + fp.y * 0.5) * cs)
