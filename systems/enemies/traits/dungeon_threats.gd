class_name DungeonThreats
extends RefCounted
## What a dungeon's fights favour, so players change their scripts for it. A dungeon's Waypoint
## (data/waypoints/act_*.tres) lists the threats it always has (`threats`) and how many more
## each new instance rolls at random (`random_threats`). The roll is stored on the instance
## (DungeonInstance.threats), so coming back to it gives the same threats. Then:
##   - DungeonPopulator spawns for them (twice the enemies for a swarm, traits on the rest)
##   - portal cards show them as tags over the portal (NpcNameplates)
##
##   swarm       twice as many enemies, each a Swarmling (half health, smaller)
##   firewalled  enemies may be Firewalled: they block 75% of every hit
##   reflector   enemies may be Reflectors: every hit you land zaps you back
##   fragmented  every enemy is a Fragment (FragmentLock): a pack only takes full damage in order
##               of life left, least first. Act V only: "fixed" threats never roll at random.

## Shown for the threats an instance will roll when it opens (no instance open yet).
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
	RANDOM: {
		"label": "+ RANDOM", "color": Color(0.62, 0.68, 0.72),
		"hint": "More threats are rolled when the dungeon opens.",
	},
}
## Chance an enemy of each rarity gets a dungeon's Firewalled / Reflector trait.
const TRAIT_CHANCE := {"normal": 0.35, "magic": 0.6, "rare": 1.0, "champion": 1.0}
## A swarm dungeon spawns this many times the enemies.
const SWARM_COUNT := 2


## The threats every instance of the area scene has (empty when it has no waypoint).
static func for_scene(scene_path: String) -> PackedStringArray:
	var w := Waypoints.for_scene(scene_path)
	if w == null:
		return PackedStringArray()
	return PackedStringArray(w.threats)


## The threats of one instance: the fixed ones plus the random roll. The same seed always
## gives the same threats. WorldState calls this when it opens an instance.
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
	# Shuffle with this rng (Array.shuffle uses the global one)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var n := mini(rng.randi_range(w.random_threats.x, w.random_threats.y), pool.size())
	for i in n:
		out.append(pool[i])
	return out


## What to show for a trip to a dungeon (portal cards, the waypoint map): the open instance's
## threats if the trip rejoins one, otherwise the fixed threats plus RANDOM when more will roll.
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


## The trait modifiers one enemy gets in a dungeon with these threats.
static func roll_traits(threats: PackedStringArray, rarity: String, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for id in threats:
		if id == "swarm" or INFO.get(id, {}).get("every_enemy", false):
			out.append(trait_def(id))                # every enemy in a swarm is a Swarmling
		elif rng.randf() < float(TRAIT_CHANCE.get(rarity, 0.5)):
			out.append(trait_def(id))
	return out.filter(func(d) -> bool: return d != null)
