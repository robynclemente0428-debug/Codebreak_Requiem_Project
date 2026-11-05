class_name MuzzleFlash
extends Node3D
## The flash at a gun's barrel when it fires, built in code (no scene to set up):
##   a bright billboard core, a star of spikes pointing along the shot, and a quick light pop
## It lasts a few frames and frees itself. ShootBehavior spawns one per cast:
##     MuzzleFlash.spawn(cast.effect_parent(), origin, direction)
## The materials and meshes are shared by every flash, so fast fire (Overclock) stays cheap.

const LIFETIME := 0.07          # seconds the flash is visible
const COLOR := Color(1.0, 0.82, 0.45)
const CORE_SIZE := 0.32
const SPIKE_LENGTH := 0.55
const SPIKE_WIDTH := 0.16
const LIGHT_ENERGY := 2.0
const LIGHT_RANGE := 3.5

static var _core_mesh: QuadMesh
static var _spike_mesh: QuadMesh
static var _core_mat: StandardMaterial3D
static var _spike_mat: StandardMaterial3D

var _t := 0.0
var _core: MeshInstance3D
var _spikes: Node3D
var _light: OmniLight3D


static func spawn(parent: Node, pos: Vector3, direction: Vector3) -> MuzzleFlash:
	if parent == null or not parent.is_inside_tree():
		return null
	var fx := MuzzleFlash.new()
	parent.add_child(fx)
	fx.global_position = pos
	var d := direction
	d.y = 0.0
	if d.length_squared() > 0.0001:
		fx.look_at(pos + d.normalized(), Vector3.UP)    # -Z points along the shot
	return fx


func _ready() -> void:
	_make_shared()
	_core = MeshInstance3D.new()
	_core.mesh = _core_mesh
	_core.material_override = _core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	# Spikes: crossed quads lying along the shot, starting at the barrel, randomly rolled so
	# no two flashes look the same
	_spikes = Node3D.new()
	_spikes.rotation.z = randf() * TAU
	add_child(_spikes)
	for i in 3:
		var s := MeshInstance3D.new()
		s.mesh = _spike_mesh
		s.material_override = _spike_mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.rotation = Vector3(0.0, 0.0, PI * i / 3.0)
		_spikes.add_child(s)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0, -0.2)
	if GraphicsQuality.allow_effect_light(_light):     # GRAPHICS > EFFECT LIGHTS
		add_child(_light)
	else:
		_light.free()
		_light = null
	_update(0.0)


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME:
		queue_free()
		return
	_update(_t / LIFETIME)


## k: 0 at the shot, 1 when gone. Pops to full size at once, then shrinks and fades.
func _update(k: float) -> void:
	var fade := 1.0 - k
	var grow := lerpf(1.0, 0.6, k)
	_core.scale = Vector3.ONE * grow * randf_range(0.9, 1.1)
	_spikes.scale = Vector3(grow, grow, lerpf(1.0, 1.35, k) * randf_range(0.85, 1.15))
	_core.transparency = 1.0 - fade
	for s in _spikes.get_children():
		(s as GeometryInstance3D).transparency = 1.0 - fade * fade
	if _light != null:
		_light.light_energy = LIGHT_ENERGY * fade * fade


static func _make_shared() -> void:
	if _core_mat != null:
		return
	var tex := _radial_texture()
	_core_mat = _additive(tex)
	_core_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_spike_mat = _additive(tex)
	_spike_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_core_mesh = QuadMesh.new()
	_core_mesh.size = Vector2.ONE * CORE_SIZE
	# A long thin flat quad laid along -Z (the shot), its near end at the barrel. Rolled copies
	# around the shot's axis make the star.
	_spike_mesh = QuadMesh.new()
	_spike_mesh.orientation = PlaneMesh.FACE_Y
	_spike_mesh.size = Vector2(SPIKE_WIDTH, SPIKE_LENGTH)
	_spike_mesh.center_offset = Vector3(0, 0, -SPIKE_LENGTH * 0.45)


static func _additive(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = tex
	m.albedo_color = Color(COLOR.r * 1.6, COLOR.g * 1.5, COLOR.b * 1.3)
	m.no_depth_test = false
	m.disable_receive_shadows = true
	return m


## White-hot centre fading to transparent at the edge.
static func _radial_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 0.95, 0.8, 0.9))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t
