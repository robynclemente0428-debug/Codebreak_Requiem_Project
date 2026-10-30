class_name SkillStyle
extends RefCounted
## Reads the colours (and the shader) of whatever the character is holding, so skill effects
## match the equipped weapon: a blue arcane orb gives blue shots, a red one gives red ones.
##
## It works with any held item whose material is a ShaderMaterial with colour uniforms: the
## known pairs listed in PARAM_PAIRS first, otherwise the first two colours the shader
## declares. Anything else falls back to the
## original orange Blast colours.
##
## Usage from a skill behavior:
##     var style := SkillStyle.for_caster(caster)
##     style["primary"]     # color_a, the deeper colour
##     style["secondary"]   # color_b, the bright colour
##     style["material"]    # the held item's ShaderMaterial, or null

const DEFAULT_PRIMARY := Color(1.0, 0.45, 0.1)
const DEFAULT_SECONDARY := Color(1.0, 0.8, 0.5)
## Known shaders, as [primary parameter, secondary parameter]. The primary is the deeper
## colour and the secondary the bright one. Shaders not listed here still work: the first two
## colour uniforms they declare are used (see _first_colors).
const PARAM_PAIRS := [
	[&"color_a", &"color_b"],           # orb_arcane
	[&"rim_color", &"vein_color"],      # orb_void
	[&"color_ice", &"color_frost"],     # orb_frost
	[&"color_arc", &"color_flash"],     # orb_storm
	[&"color_liquid", &"color_glow"],   # orb_toxic
	[&"color_gold", &"color_core"],     # orb_radiant
	[&"color_blood", &"color_glow"],    # orb_crimson
]


static func default_style() -> Dictionary:
	return {"primary": DEFAULT_PRIMARY, "secondary": DEFAULT_SECONDARY, "material": null}


## Asks the caster for its style. Casters without get_effect_style() (enemies, for example)
## get the default colours.
static func for_caster(caster: Node) -> Dictionary:
	if caster != null and caster.has_method("get_effect_style"):
		return caster.get_effect_style()
	return default_style()


## `held` is the list of nodes in the character's hands, main hand first.
static func from_held(held: Array) -> Dictionary:
	for node in held:
		if not is_instance_valid(node):
			continue
		var meshes: Array = (node as Node).find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.push_front(node)
		for mesh in meshes:
			var mat = _material_of(mesh as MeshInstance3D)
			if not (mat is ShaderMaterial):
				continue
			for pair in PARAM_PAIRS:
				var a = _param(mat, pair[0])
				var b = _param(mat, pair[1])
				if a is Color and b is Color:
					return {"primary": a, "secondary": b, "material": mat}
			var found := _first_colors(mat)          # unknown shader: use its own colour uniforms
			if not found.is_empty():
				return {"primary": found[0], "secondary": found[found.size() - 1], "material": mat}
	return default_style()


static func _material_of(mi: MeshInstance3D) -> Material:
	if mi.material_override != null:
		return mi.material_override
	if mi.mesh != null and mi.mesh.get_surface_count() > 0:
		return mi.mesh.surface_get_material(0)
	return null


## The value set on the material, or the shader's own default if the material never set it.
static func _param(mat: ShaderMaterial, param: StringName) -> Variant:
	var v = mat.get_shader_parameter(param)
	if v == null and mat.shader != null:
		v = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), param)
	return v


## The first two colour uniforms the shader declares, in the order they are written.
## One colour gives a one-item list, and the style then uses it for both slots.
static func _first_colors(mat: ShaderMaterial) -> Array:
	var out: Array = []
	if mat.shader == null:
		return out
	for u in mat.shader.get_shader_uniform_list():
		if u["type"] != TYPE_COLOR:
			continue
		var v = _param(mat, StringName(u["name"]))
		if v is Color:
			out.append(v)
		if out.size() == 2:
			break
	return out
