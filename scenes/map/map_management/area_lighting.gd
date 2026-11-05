class_name AreaLighting
extends RefCounted
## How bright the shared world light is in the area that's loaded (GameArea.light_scale): the
## WorldEnvironment's ambient light and the sun in main.tscn, as a share of the values saved
## there. Towns use 1; dungeons are darker (dungeon.gd), so the player's own light and the
## skills carry the scene. The player's light (Player.set_light_strength) follows the same
## scale the other way: off at 1, full in the dark.

static var _env: Environment
static var _sun: DirectionalLight3D
static var _base_ambient := 0.0
static var _base_sun := 0.0
## How strong the players' own light is in the area that's loaded (0 off .. 1 full).
static var player_light := 0.0


static func apply(area: Node, scale: float) -> void:
	player_light = clampf(1.0 - scale, 0.0, 1.0)
	for p in area.get_tree().get_nodes_in_group("players"):
		if p.has_method("set_light_strength"):
			p.set_light_strength(player_light)
	if not _find(area.get_tree()):
		return
	_env.ambient_light_energy = _base_ambient * scale
	_sun.light_energy = _base_sun * scale


## The environment and sun, with their saved values (read once, so scaling never compounds).
static func _find(tree: SceneTree) -> bool:
	if is_instance_valid(_sun) and _env != null:
		return true
	var envs := tree.root.find_children("*", "WorldEnvironment", true, false)
	var suns := tree.root.find_children("*", "DirectionalLight3D", true, false)
	if envs.is_empty() or suns.is_empty() or (envs[0] as WorldEnvironment).environment == null:
		return false
	_env = (envs[0] as WorldEnvironment).environment
	_sun = suns[0] as DirectionalLight3D
	_base_ambient = _env.ambient_light_energy
	_base_sun = _sun.light_energy
	return true
