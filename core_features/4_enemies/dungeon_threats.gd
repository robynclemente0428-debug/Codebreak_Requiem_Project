class_name DungeonThreats
extends RefCounted

const RANDOM := "random"

const INFO := {
	"swarm": {
		"label": "SWARM", "color": Color(0.45, 1.0, 0.55),
		"trait": "res://data/enemy_traits/swarmling.tres",
		"hint": "Twice the enemies, half the health each. Area and splash scripts shine.",
	},
	"firewalled": {
		"label": "FIREWALLED", "color": Color(1.0, 0.62, 0.25),
		"trait": "res://data/enemy_traits/firewalled.tres",
		"hint": "Blocks 75% of every hit. Pile on damage.",
	},
	"reflector": {
		"label": "REFLECTOR", "color": Color(0.80, 0.45, 1.0),
		"trait": "res://data/enemy_traits/reflector.tres",
		"hint": "Every hit you land zaps you back. Fewer, bigger hits.",
	},
	"fragmented": {
		"label": "FRAGMENTED", "color": Color(1.0, 0.84, 0.42),
		"trait": "res://data/enemy_traits/fragmented.tres",
		"hint": "Each pack takes full damage only in order: least life left first. Sort the registry.",
		"fixed": true, "every_enemy": true,
	},
	"paged": {
		"label": "PAGED", "color": Color(0.55, 0.9, 1.0),
		"trait": "res://data/enemy_traits/paged.tres",
		"hint": "Enemies page out of memory unless something references them. Keep them in your registry.",
		"fixed": true, "every_enemy": true,
	},
	RANDOM: {
		"label": "+ RANDOM", "color": Color(0.62, 0.68, 0.72),
		"hint": "More threats are rolled when the dungeon opens.",
	},
}
const TRAIT_CHANCE := {"normal": 0.35, "magic": 0.6, "rare": 1.0, "champion": 1.0}
const SWARM_COUNT := 2


static func for_scene(scene_path: String) -> PackedStringArray:
	var w := Waypoints.for_scene(scene_path)
	if w == null:
		return PackedStringArray()
	return PackedStringArray(w.threats)


static func roll_for(scene_path: String, rng_seed: int) -> PackedStringArray:
	var w := Waypoints.for_scene(scene_path)
	if w == null:
		return PackedStringArray()
	var out := PackedStringArray(w.threats)
	if w.random_threats.y <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed + 9241
	var pool: Array = []
	for id in INFO:
		if id != RANDOM and not (id in out) and not INFO[id].get("fixed", false):
			pool.append(id)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var n := mini(rng.randi_range(w.random_threats.x, w.random_threats.y), pool.size())
	for i in n:
		out.append(pool[i])
	return out


static func preview(scene_path: String, level: int, new_instance := false) -> PackedStringArray:
	var w := Waypoints.for_scene(scene_path)
	if w == null:
		return PackedStringArray()
	if not new_instance:
		var inst: DungeonInstance = WorldState.find_open(scene_path, level if level > 0 else w.dungeon_level)
		if inst != null:
			return inst.threats.duplicate()
	var out := PackedStringArray(w.threats)
	if w.random_threats.y > 0:
		out.append(RANDOM)
	return out


static func label(id: String) -> String:
	return INFO.get(id, {}).get("label", id.to_upper())


static func color(id: String) -> Color:
	return INFO.get(id, {}).get("color", Color.WHITE)


static func hint(id: String) -> String:
	return INFO.get(id, {}).get("hint", "")


static func trait_def(id: String) -> EnemyModifierDefinition:
	var path: String = INFO.get(id, {}).get("trait", "")
	return load(path) as EnemyModifierDefinition if path != "" and ResourceLoader.exists(path) else null


static func roll_traits(threats: PackedStringArray, rarity: String, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for id in threats:
		if id == "swarm" or INFO.get(id, {}).get("every_enemy", false):
			out.append(trait_def(id))
		elif rng.randf() < float(TRAIT_CHANCE.get(rarity, 0.5)):
			out.append(trait_def(id))
	return out.filter(func(d) -> bool: return d != null)
