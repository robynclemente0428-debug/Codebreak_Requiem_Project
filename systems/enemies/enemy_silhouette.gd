class_name EnemySilhouette
extends RefCounted
## Enemies seen through walls: wherever something solid stands between the camera and an
## enemy, that part of the enemy is drawn as a flat red silhouette on top of the wall. It's each
## mesh's material_overlay (so the enemy's own materials stay as they are), drawn without the
## depth test and kept only where the scene in front is clearly nearer than the enemy, so an arm
## in front of the body doesn't light up.
##     EnemySilhouette.cover(model_root)      (EnemyBase.attach_model)
##     EnemySilhouette.uncover(model_root)    (on death, before the glitch effect)

const COLOR := Color(1.0, 0.22, 0.3)
const ALPHA := 0.55
## How much nearer the scene must be (metres) to count as a wall in front, not the enemy itself.
const MIN_GAP := 0.8

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 color : source_color = vec4(1.0, 0.22, 0.3, 1.0);
uniform float alpha = 0.55;
uniform float min_gap = 0.8;
uniform float open_amount = 0.0;                      // a boss lock's open port: glows in full view
uniform vec4 open_color : source_color = vec4(0.3, 0.95, 1.0, 1.0);

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = view.z / view.w;                  // view space: nearer the camera = larger
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	if (scene_z - VERTEX.z < min_gap) {
		if (open_amount <= 0.001) {
			discard;                                  // nothing in front: the enemy shows as itself
		}
		// Open port: the body floods with the open colour, bright bands of data scrolling up it.
		// Over 1, so the glow pass blooms it.
		float wy = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
		float band = smoothstep(0.55, 0.75, fract(wy * 2.2 - TIME * 1.8));
		ALBEDO = open_color.rgb * (1.3 + rim * 2.6 + band * 1.4);
		ALPHA = open_amount * clamp(0.6 + 0.35 * rim + 0.25 * band, 0.0, 0.95);
	} else {
		ALBEDO = color.rgb * (0.7 + rim * 0.8);       // behind a wall: the red silhouette
		ALPHA = alpha * (0.6 + 0.4 * rim);
	}
}
"""

static var _material: ShaderMaterial


static func cover(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g is GPUParticles3D or g is CPUParticles3D:
			continue
		g.material_overlay = _shared()


## Like cover(), with a copy of the material only this enemy uses, returned so its
## "open_amount" can be set (ChecksumLock glows while its port is open).
static func cover_own(root: Node) -> ShaderMaterial:
	var own := _shared().duplicate() as ShaderMaterial
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g is GPUParticles3D or g is CPUParticles3D:
			continue
		g.material_overlay = own
	return own


static func uncover(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		var m := g.material_overlay as ShaderMaterial
		if m != null and m.shader == _shared().shader:
			g.material_overlay = null


static func _shared() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("color", COLOR)
		_material.set_shader_parameter("alpha", ALPHA)
		_material.set_shader_parameter("min_gap", MIN_GAP)
	return _material
