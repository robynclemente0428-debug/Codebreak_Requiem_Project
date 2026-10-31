class_name VoidBackdrop
extends Node
## What an area shows where a sky would be (GameArea.backdrop).
##
## The camera is orthographic, so a sky shader can only ever show one flat colour: every pixel
## looks in the same direction. Instead this keeps a quad filling the view just inside the
## camera's far plane, with the backdrop material on it (e.g. void_binary.gdshader). It follows
## the camera and its zoom, and passes the camera's movement to the material's `scroll`
## (in screen pixels, times PARALLAX) so the backdrop drifts a little as you walk.

const PARALLAX := 0.15
const MARGIN := 1.1                     # quad slightly larger than the view, so edges never show

var material: Material
var _camera: Camera3D
var _quad: MeshInstance3D


## Adds a backdrop to `area`. It goes away with the area.
static func attach(area: Node, backdrop: Material) -> void:
	var b := VoidBackdrop.new()
	b.name = "VoidBackdrop"
	b.material = backdrop
	area.add_child(b)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if cam != _camera:
		_free_quad()
		_camera = cam
		_make_quad()
	var view := get_viewport().get_visible_rect().size
	var h := cam.size                                  # orthographic size = view height in metres
	var w := h * view.x / view.y
	(_quad.mesh as QuadMesh).size = Vector2(w, h) * MARGIN
	_quad.position = Vector3(0.0, 0.0, -cam.far * 0.95)
	var sm := material as ShaderMaterial
	if sm != null:
		var px_per_metre := view.y / h
		var pos := cam.global_position
		sm.set_shader_parameter("scroll", Vector2(pos.dot(cam.global_basis.x),
				-pos.dot(cam.global_basis.y)) * px_per_metre * PARALLAX)


func _make_quad() -> void:
	_quad = MeshInstance3D.new()
	_quad.name = "VoidBackdropQuad"
	_quad.mesh = QuadMesh.new()
	_quad.material_override = material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_camera.add_child(_quad)


func _exit_tree() -> void:
	_free_quad()


func _free_quad() -> void:
	if is_instance_valid(_quad):
		_quad.queue_free()
	_quad = null
