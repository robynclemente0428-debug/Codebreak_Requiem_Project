class_name GraphicsQuality
extends RefCounted
## The GRAPHICS settings (Settings "graphics" section) and what they do to the running game.
## QUALITY is a preset: picking LOW / MEDIUM / HIGH sets every other graphics setting at once,
## and changing one of them by hand turns QUALITY into CUSTOM (Settings.set_value handles that).
##
##   render_scale        share of the window the 3D world is drawn at (UI is always sharp)
##   shadows             "off", "sun" (the sun only, small map) or "all" (sun + the player's light)
##   effect_lights       "none", "few" (MAX_FEW at once) or "all": the flashes skills make
##   glow                the bloom round bright things
##   tile_detail         "simple" or "full": the floor and wall shaders' finer patterns
##   damage_numbers_max  most damage numbers on screen at once
##   retro_filter        "off", "light" (the screen filter without its costly glow and colour
##                       bleed, which read the screen 6-8 extra times a pixel) or "full"
##
## Applied by Settings (when a value changes) and AreaManager (when the game scene and each
## area load). Things made later ask here: the player's light (player_shadows), skill flashes
## (allow_effect_light).

const QUALITIES := ["low", "medium", "high"]
const PRESETS := {
	"low": {"render_scale": 0.5, "shadows": "off", "effect_lights": "none", "glow": false,
			"tile_detail": "simple", "damage_numbers_max": 20, "retro_filter": "light"},
	"medium": {"render_scale": 0.75, "shadows": "sun", "effect_lights": "few", "glow": true,
			"tile_detail": "full", "damage_numbers_max": 40, "retro_filter": "full"},
	"high": {"render_scale": 1.0, "shadows": "all", "effect_lights": "all", "glow": true,
			"tile_detail": "full", "damage_numbers_max": 60, "retro_filter": "full"},
}
const RENDER_SCALES := [0.5, 0.6, 0.75, 0.85, 1.0]
const SHADOW_MODES := ["off", "sun", "all"]
const EFFECT_LIGHT_MODES := ["none", "few", "all"]
const TILE_DETAILS := ["simple", "full"]
const DAMAGE_NUMBER_CAPS := [20, 40, 60]
const RETRO_FILTERS := ["off", "light", "full"]
## The retro filter's parameters LIGHT turns off: the ones that sample the screen many times.
const RETRO_HEAVY := [&"glow", &"color_bleed"]
## Skill flash lights at once on "few".
const MAX_FEW := 4

static var _fx_lights := 0                       # skill flash lights alive now


static func value(key: String) -> Variant:
	return Settings.get_value("graphics", key)


## The preset `quality` matches exactly, or "custom".
static func matching_preset() -> String:
	for q in QUALITIES:
		var same := true
		for k in PRESETS[q]:
			if value(k) != PRESETS[q][k]:
				same = false
				break
		if same:
			return q
	return "custom"


## Applies every graphics setting to what's on screen now.
static func apply(tree: SceneTree) -> void:
	if tree == null:
		return
	var scene := tree.current_scene
	var shadows := str(value("shadows"))
	# The 3D world: drawn at a share of the window and scaled up, so the GPU has fewer pixels
	for vp in _game_viewports(tree):
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(value("render_scale"))
		vp.positional_shadow_atlas_size = 2048 if shadows == "all" else 1024     # 2048: the default
	tree.root.scaling_3d_scale = 1.0                 # the menus' own 3D (class select) stays sharp
	RenderingServer.directional_shadow_atlas_set_size(4096 if shadows == "all" else 2048, true)
	if scene != null:
		for sun in scene.find_children("*", "DirectionalLight3D", true, false):
			(sun as DirectionalLight3D).shadow_enabled = shadows != "off"
		for we in scene.find_children("*", "WorldEnvironment", true, false):
			var env := (we as WorldEnvironment).environment
			if env != null:
				env.glow_enabled = bool(value("glow"))
	for p in tree.get_nodes_in_group("players"):
		if p.has_method("set_light_shadows"):
			p.set_light_shadows(player_shadows())
	RenderingServer.global_shader_parameter_set("gfx_detail", 1.0 if value("tile_detail") == "full" else 0.0)
	for dn in tree.get_nodes_in_group("damage_numbers"):
		dn.set("max_active", int(value("damage_numbers_max")))
	if scene != null:
		for retro in scene.find_children("*", "CanvasLayer", true, false):
			if retro is RetroScreen:
				_apply_retro(retro as RetroScreen, str(value("retro_filter")))


## OFF hides the filter (no full-screen pass at all); LIGHT keeps its look minus the effects
## that read the screen many times per pixel; FULL is the scene's preset as made.
static func _apply_retro(retro: RetroScreen, mode: String) -> void:
	retro.preset = retro.preset                      # back to the preset's own values
	retro.rect.visible = mode != "off"
	if mode == "light":
		for p in RETRO_HEAVY:
			retro.set_param(p, 0.0)


## True when the players' own light should cast shadows (the costliest: six views a frame).
static func player_shadows() -> bool:
	return value("shadows") == "all"


## Ask before adding a skill's flash light (muzzle flash, slam impact, blast glow). False = leave
## it out (the effect still shows, just without lighting the room). A light that is allowed is
## counted until it leaves the tree.
static func allow_effect_light(light: Light3D) -> bool:
	match str(value("effect_lights")):
		"none":
			return false
		"few":
			if _fx_lights >= MAX_FEW:
				return false
	_fx_lights += 1
	light.tree_exited.connect(func() -> void: _fx_lights = maxi(_fx_lights - 1, 0), CONNECT_ONE_SHOT)
	return true


## The SubViewports the game world is drawn in (main.tscn's), not the menus'.
static func _game_viewports(tree: SceneTree) -> Array[SubViewport]:
	var out: Array[SubViewport] = []
	var am := tree.get_first_node_in_group("area_manager") as Node
	if am != null and am.get_viewport() is SubViewport:
		out.append(am.get_viewport() as SubViewport)
	return out
