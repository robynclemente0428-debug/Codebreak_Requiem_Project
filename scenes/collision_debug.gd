extends Node

const COLOR := Color(1, 0, 0, 0.35)

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	if n is CollisionShape3D:
		_add_debug.call_deferred(n)  # deferred so the shape is assigned first

func _add_debug(cs: CollisionShape3D) -> void:
	if not is_instance_valid(cs) or cs.shape == null or cs.has_node("DebugMesh"):
		return
	var mesh: Mesh
	var s := cs.shape
	if s is CylinderShape3D:
		var m := CylinderMesh.new()
		m.top_radius = s.radius
		m.bottom_radius = s.radius
		m.height = s.height
		mesh = m
	elif s is BoxShape3D:
		var m := BoxMesh.new()
		m.size = s.size
		mesh = m
	elif s is CapsuleShape3D:
		var m := CapsuleMesh.new()
		m.radius = s.radius
		m.height = s.height
		mesh = m
	elif s is SphereShape3D:
		var m := SphereMesh.new()
		m.radius = s.radius
		m.height = s.radius * 2.0
		mesh = m
	else:
		return

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = COLOR
	mat.no_depth_test = true   # visible even when inside a model

	var mi := MeshInstance3D.new()
	mi.name = "DebugMesh"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cs.add_child(mi)
