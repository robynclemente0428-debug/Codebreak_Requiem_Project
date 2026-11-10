class_name EnemySilhouette
extends RefCounted
## Enemies seen through walls: wherever something solid stands between the camera and an
## enemy, that part of the enemy is drawn as a flat red silhouette on top of the wall. It's each
## mesh's material_overlay (so the enemy's own materials stay as they are), drawn without the
## depth test and kept only where the scene in front is clearly nearer than the enemy, so an arm
## in front of the body doesn't light up.
##     EnemySilhouette.cover(model_root)      (EnemyBase.attach_model)
##     EnemySilhouette.uncover(model_root)    (on death, before the glitch effect)
## The same overlay carries a lock's effect on the body in full view (cover_aura, from
## EnemyTrait), so a puzzle enemy is picked out of a pack before its tag can be read:
##     AURA_ECHO      ice blue rings running down it, one after another   (EchoLock)
##     AURA_DIFF      a split double image: one side magenta, one cyan     (DiffLock)
##     AURA_FIREWALL  an orange hex shield shimmering over it              (Firewalled)
##     AURA_REFLECT   a chrome sheen sweeping across it                    (Reflector)

const AURA_ECHO := 1
const AURA_DIFF := 2
const AURA_FIREWALL := 3
const AURA_REFLECT := 4
## How strongly an aura shows (0..1): enough to pick out, not enough to hide the model.
const AURA_STRENGTH := 0.85

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
uniform int aura = 0;                                 // a lock's effect on the body (AURA_*)
uniform vec4 aura_color : source_color = vec4(0.3, 0.95, 1.0, 1.0);
uniform float aura_strength = 0.85;

float lock_hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = view.z / view.w;                  // view space: nearer the camera = larger
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	if (scene_z - VERTEX.z < min_gap) {
		vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		if (open_amount > 0.001) {
			// Open port: the body floods with the open colour, bright bands of data scrolling up
			// it. Over 1, so the glow pass blooms it.
			float band = smoothstep(0.55, 0.75, fract(wpos.y * 2.2 - TIME * 1.8));
			ALBEDO = open_color.rgb * (1.3 + rim * 2.6 + band * 1.4);
			ALPHA = open_amount * clamp(0.6 + 0.35 * rim + 0.25 * band, 0.0, 0.95);
		} else if (aura == 1) {
			// ECHO: rings of light run down the body one after another, fading like an echo.
			float f = fract(wpos.y * 1.6 + TIME * 1.1);
			float ring = smoothstep(0.0, 0.05, f) * (1.0 - smoothstep(0.05, 0.3, f));
			ALBEDO = aura_color.rgb * (1.2 + ring * 1.2 + rim);
			ALPHA = aura_strength * clamp(ring * 0.6 + rim * 0.4, 0.0, 0.9);
		} else if (aura == 2) {
			// DIFF: a split double image, the rim magenta on one side and cyan on the other,
			// with slices of the body flickering out of step.
			float side = step(0.0, NORMAL.x);
			vec3 c = mix(vec3(1.0, 0.25, 0.75), vec3(0.25, 0.95, 1.0), side);
			float slice = step(0.88, lock_hash(floor(wpos.y * 14.0) * 12.9898 + floor(TIME * 9.0) * 78.233));
			ALBEDO = c * (1.4 + slice);
			ALPHA = aura_strength * clamp(rim * 0.8 + slice * 0.35, 0.0, 0.9);
		} else if (aura == 3) {
			// FIREWALLED: an orange hex shield over the body, its cells pulsing up it.
			vec2 p = vec2(wpos.x + wpos.z, wpos.y) * 3.2;
			vec2 r = vec2(1.0, 1.7320508);
			vec2 h = r * 0.5;
			vec2 a = mod(p, r) - h;
			vec2 b = mod(p - h, r) - h;
			vec2 g = dot(a, a) < dot(b, b) ? a : b;
			vec2 q = abs(g);
			float d = max(dot(q, normalize(r)), q.x);     // 0.5 on a cell's edge
			float edge = smoothstep(0.40, 0.49, d);
			float pulse = 0.55 + 0.45 * sin(TIME * 2.4 - wpos.y * 2.5);
			ALBEDO = aura_color.rgb * (1.3 + edge);
			ALPHA = aura_strength * clamp(edge * 0.55 * pulse + rim * 0.3, 0.0, 0.9);
		} else if (aura == 4) {
			// REFLECT: a chrome sheen sweeping across the body.
			float s = smoothstep(0.82, 1.0, sin((wpos.y + wpos.x * 0.6) * 3.0 - TIME * 2.6));
			ALBEDO = mix(aura_color.rgb, vec3(1.0), 0.45 + 0.55 * s) * (1.2 + s);
			ALPHA = aura_strength * clamp(s * 0.6 + rim * 0.45, 0.0, 0.9);
		} else {
			discard;                                  // nothing in front: the enemy shows as itself
		}
	} else {
		ALBEDO = color.rgb * (0.7 + rim * 0.8);       // behind a wall: the red silhouette
		ALPHA = alpha * (0.6 + 0.4 * rim);
	}
}
"""

## A mesh has one material_overlay slot, and some models fill it themselves (Act II's Loop
## Hound, Eye Drone and Trilobite: red_glitch_overlay). Those keep it: the silhouette is chained
## after it as its next_pass, on a copy (shared by every mesh with that same overlay), and the
## model's own overlay is kept in this meta so uncover() can put it back.
const OWN_META := &"_own_overlay"

static var _material: ShaderMaterial
static var _chained: Dictionary = {}             # "own overlay|silhouette" -> its copy + the silhouette
static var _auras: Dictionary = {}               # "aura|colour" -> the silhouette with that aura


static func cover(root: Node) -> void:
	for g in _meshes(root):
		_attach(g, _shared(), true)


## Like cover(), with a copy of the material only this enemy uses, returned so its
## "open_amount" can be set (ChecksumLock glows while its port is open).
static func cover_own(root: Node) -> ShaderMaterial:
	var own := _shared().duplicate() as ShaderMaterial
	for g in _meshes(root):
		_attach(g, own, false)
	return own


## Like cover(), with a lock's effect on the body in full view (AURA_*). Every enemy with the
## same aura and colour shares one material.
static func cover_aura(root: Node, aura: int, color: Color) -> void:
	var key := "%d|%s" % [aura, color.to_html()]
	var mat := _auras.get(key) as ShaderMaterial
	if mat == null:
		mat = _shared().duplicate() as ShaderMaterial
		mat.set_shader_parameter("aura", aura)
		mat.set_shader_parameter("aura_color", color)
		mat.set_shader_parameter("aura_strength", AURA_STRENGTH)
		_auras[key] = mat
	for g in _meshes(root):
		_attach(g, mat, true)


static func uncover(root: Node) -> void:
	for g in _meshes(root):
		if g.has_meta(OWN_META):
			g.material_overlay = g.get_meta(OWN_META)    # the model's own overlay, as it was
			g.remove_meta(OWN_META)
			continue
		var m := g.material_overlay as ShaderMaterial
		if m != null and m.shader == _shared().shader:
			g.material_overlay = null


static func _meshes(root: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		if not (n is GPUParticles3D or n is CPUParticles3D):
			out.append(n as GeometryInstance3D)
	return out


## Puts `sil` on the mesh: alone in an empty overlay slot, or chained after the model's own.
## shared: the chained copy is cached per own overlay (cover); otherwise a copy just for this
## mesh (cover_own's material is this enemy's alone).
static func _attach(g: GeometryInstance3D, sil: ShaderMaterial, shared: bool) -> void:
	var own: Material = g.get_meta(OWN_META) if g.has_meta(OWN_META) else g.material_overlay
	if own == null or (own is ShaderMaterial and (own as ShaderMaterial).shader == sil.shader):
		g.material_overlay = sil                        # nothing of its own (or only ours)
		return
	g.set_meta(OWN_META, own)
	var key := "%d|%d" % [own.get_instance_id(), sil.get_instance_id()]   # plain and aura silhouettes apart
	var chain: Material = _chained.get(key) if shared else null
	if chain == null or not is_instance_valid(chain):
		chain = own.duplicate()
		var tail := chain
		while tail.next_pass != null:                   # after any passes it already has
			tail.next_pass = tail.next_pass.duplicate()
			tail = tail.next_pass
		tail.next_pass = sil
		if shared:
			_chained[key] = chain
	g.material_overlay = chain


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
