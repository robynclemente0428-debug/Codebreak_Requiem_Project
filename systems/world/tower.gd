class_name Tower
extends RefCounted
## The Recursion: the endgame tower after the campaign (story_plan/CodeBreak_Requiem_Endgame_Plan.md).
## FLOORS floors, one generic dungeon scene (TowerFloor, SCENE) that each floor dresses differently:
## a look (a campaign DungeonTheme: its tiles and its enemies), a level and threats.
##
## Each floor is ROLLED ONCE and saved as a seed, so the tower map can show it before you go in
## (like an atlas). Everything about a floor comes from its seed alone (look_of_seed,
## threats_of_seed, floor_of_seed), so a co-op guest who only gets the host's instance seed builds
## the same floor. The floor number sits in the seed's low bits.
##
## The trip: the tower map sends you to SCENE with dungeon_level = the FLOOR NUMBER (so each floor
## is its own instance in WorldState). WorldState._create asks seed_of(floor) for the seed, and
## TowerFloor turns the floor into its real level (level_of) and puts its look on before generating.
## Clearing a floor (DungeonPopulator -> TowerFloor.on_floor_cleared) reveals the next and rerolls
## the cleared one, so a cleared floor is a new run every time.
##
## Saved per character under SAVE_KEY: {"cleared": highest floor cleared, "seeds": {floor: seed}}.
## The tower opens once an ending is chosen (Endings.current).
##
## THREATS PAY (REWARDS, rewards_for): each threat on a floor has a reward, and every threat past
## the first raises all of them by STACK_BONUS. Before entering, anyone can RAISE THE STAKES: add up
## to MAX_STAKES threats the floor didn't roll, for their rewards (set_stakes). Stakes ride in the
## run's seed (stake bits), so a co-op guest's copy of the floor has them too; a floor's look and
## rolled threats come from the seed without them (base_of), so staking only adds.

const SCENE := "res://scenes/map/dungeon/tower_floor.tscn"
const SPAWN_IN := &"tower_in"
const FLOORS := 50
const SAVE_KEY := "tower"
## The tower counts as Act VI for EnemySpawner's act scaling (+50% health and armour per act).
const ACT_NUMBER := 6
const BOSS_EVERY := 10
const FLOOR_BITS := 6                                     # 50 floors fit in 6 bits (0..63)
const STAKE_BITS := 5                                     # one bit per threat in STAKEABLE
const BASE_SHIFT := FLOOR_BITS + STAKE_BITS
const MAX_STAKES := 2
## Threats in the order their stake bits use (DungeonThreats ids).
const STAKEABLE := ["swarm", "firewalled", "reflector", "fragmented", "paged"]

## What each threat pays (rewards_for adds them up). Shown on the tower map.
##   quantity     more items dropped (+40% = 1.4 times the drops)
##   item_level   added to every drop's item level (capped at ITEM_LEVEL_CAP)
##   rarity       chance a drop is raised a step (normal -> magic -> rare)
##   top_tier     every rare drop has a modifier from the highest tier its item level allows
##   bonus_rare   clearing the floor drops a rare at the floor's level + BONUS_RARE_LEVELS
const REWARDS := {
	"swarm": {"quantity": 0.4, "text": "+40% items dropped"},
	"firewalled": {"item_level": 2, "text": "+2 item level on every drop"},
	"reflector": {"rarity": 0.3, "text": "30% of drops raised a rarity step"},
	"fragmented": {"top_tier": true, "text": "every rare has a top-tier modifier"},
	"paged": {"bonus_rare": true, "text": "a guaranteed rare when the floor is cleared"},
}
## Every threat past the first adds this to all the rewards (4 threats: +30% each).
const STACK_BONUS := 0.1
## No affix needs more than item level 60, so more would only change the number.
const ITEM_LEVEL_CAP := 60
const BONUS_RARE_LEVELS := 2

## The looks a floor can roll: the campaign's dungeon themes (tiles and enemy pool together).
const LOOKS := [
	{"id": "ward", "name": "Hardfault's Ward", "act": "I",
		"theme": "res://dungeon_generation/rendering/mesh_library/resources/act1_ward.tres"},
	{"id": "road", "name": "The Migration Road", "act": "II",
		"theme": "res://dungeon_generation/rendering/mesh_library/resources/act2_stops.tres"},
	{"id": "mire", "name": "The Mire", "act": "II",
		"theme": "res://dungeon_generation/rendering/mesh_library/resources/act2_mire.tres"},
	{"id": "districts", "name": "Checkpoint's Districts", "act": "III",
		"theme": "res://dungeon_generation/rendering/mesh_library/resources/act3_districts.tres"},
	{"id": "heap", "name": "The Heap", "act": "III",
		"theme": "res://dungeon_generation/rendering/mesh_library/resources/act3_heap.tres"},
	{"id": "null", "name": "The Null Zone", "act": "IV",
		"theme": "res://dungeon_generation/rendering/mesh_library/resources/null_zone.tres"},
	{"id": "wells", "name": "The Echo Wells", "act": "IV",
		"theme": "res://dungeon_generation/rendering/mesh_library/resources/null_wells.tres"},
	{"id": "stack", "name": "The Stack Trace", "act": "V",
		"theme": "res://dungeon_generation/rendering/mesh_library/resources/stack_trace.tres"},
	{"id": "core", "name": "The Core", "act": "V",
		"theme": "res://dungeon_generation/rendering/mesh_library/resources/scheduler.tres"},
]


# ---------- WHAT A FLOOR IS ----------
static func is_tower(scene_path: String) -> bool:
	return Waypoints.normalize(scene_path) == SCENE


## A floor's enemy level: 51 on floors 1-5, one more every 5 floors, 60 on floors 46-50
## (the level 60 affixes only roll up there).
static func level_of(floor_n: int) -> int:
	return 50 + ceili(clampi(floor_n, 1, FLOORS) / 5.0)


static func is_boss_floor(floor_n: int) -> bool:
	return floor_n % BOSS_EVERY == 0


## How many random threats a floor rolls: 1 below 10, 2 below 25, 3 from there. From floor 40 an
## Act V threat (FRAGMENTED or PAGED) comes on top (fixed_threat).
static func threat_count(floor_n: int) -> int:
	return 1 if floor_n < 10 else 2 if floor_n < 25 else 3


static func has_fixed_threat(floor_n: int) -> bool:
	return floor_n >= 40


static func make_seed(base: int, floor_n: int, stake_bits := 0) -> int:
	return ((base & 0x7FFFFFFF) << BASE_SHIFT) | ((stake_bits & ((1 << STAKE_BITS) - 1)) << FLOOR_BITS) \
			| clampi(floor_n, 1, FLOORS)


static func floor_of_seed(rng_seed: int) -> int:
	return clampi(rng_seed & ((1 << FLOOR_BITS) - 1), 1, FLOORS)


## The seed without its stakes, Null flag or patches: what the floor's look and rolled threats
## come from.
static func base_of(rng_seed: int) -> int:
	return rng_seed & ((1 << NULL_BIT) - 1) & ~(STAKE_MASK << FLOOR_BITS)


## The bits above the base: a floor's Null flag (MERGE) and Overwrite's patches, kept in its seed
## so a co-op guest's copy of the floor has them too.
##   NULL_BIT        a Null floor: one more threat, more loot (null_extra, rewards_for)
##   REMOVE_SHIFT    threats a patch removed (one bit per STAKEABLE)
##   PIN_SHIFT       threats pinned here from the floor below
const NULL_BIT := 50
const REMOVE_SHIFT := 51
const PIN_SHIFT := 56
const STAKE_MASK := (1 << STAKE_BITS) - 1


static func _bits_of(rng_seed: int, shift: int) -> PackedStringArray:
	var bits := (rng_seed >> shift) & STAKE_MASK
	var out := PackedStringArray()
	for i in STAKEABLE.size():
		if bits & (1 << i):
			out.append(STAKEABLE[i])
	return out


static func _with_bit(rng_seed: int, shift: int, id: String) -> int:
	var i := STAKEABLE.find(id)
	return rng_seed | (1 << (shift + i)) if i >= 0 else rng_seed


static func is_null_floor(rng_seed: int) -> bool:
	return (rng_seed >> NULL_BIT) & 1 == 1


static func removed_of(rng_seed: int) -> PackedStringArray:
	return _bits_of(rng_seed, REMOVE_SHIFT)


static func pinned_of(rng_seed: int) -> PackedStringArray:
	return _bits_of(rng_seed, PIN_SHIFT)


## The threats staked on a run (from its seed).
static func stakes_of_seed(rng_seed: int) -> PackedStringArray:
	var bits := (rng_seed >> FLOOR_BITS) & ((1 << STAKE_BITS) - 1)
	var out := PackedStringArray()
	for i in STAKEABLE.size():
		if bits & (1 << i):
			out.append(STAKEABLE[i])
	return out


static func with_stakes(rng_seed: int, staked: PackedStringArray) -> int:
	var bits := 0
	for id in staked:
		var i := STAKEABLE.find(id)
		if i >= 0:
			bits |= 1 << i
	return (rng_seed & ~(STAKE_MASK << FLOOR_BITS)) | (bits << FLOOR_BITS)


## The index into LOOKS a seed gives.
static func look_index(rng_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = base_of(rng_seed) ^ 0x70E3
	return rng.randi_range(0, LOOKS.size() - 1)


static func look_of_seed(rng_seed: int) -> Dictionary:
	return LOOKS[look_index(rng_seed)]


static func theme_of_seed(rng_seed: int) -> DungeonTheme:
	return load(str(look_of_seed(rng_seed)["theme"])) as DungeonTheme


## Everything a run fights: the floor's own threats (floor_threats_of_seed), plus the run's stakes.
static func threats_of_seed(rng_seed: int) -> PackedStringArray:
	var out := floor_threats_of_seed(rng_seed)
	for id in stakes_of_seed(rng_seed):
		if not id in out:
			out.append(id)
	return out


## The floor's own threats, before stakes: what it rolled (threat_count, plus an Act V one from
## floor 40), plus a Null floor's extra one and threats pinned from below, minus patched-out ones.
static func floor_threats_of_seed(rng_seed: int) -> PackedStringArray:
	var out := rolled_threats(rng_seed)
	var add := pinned_of(rng_seed)
	if is_null_floor(rng_seed):
		var extra := null_extra(rng_seed)
		if extra != "":
			add.append(extra)
	for id in add:
		if not id in out:
			out.append(id)
	var removed := removed_of(rng_seed)
	return PackedStringArray(Array(out).filter(func(id: String) -> bool: return not id in removed))


## The threat a Null floor adds: one it didn't roll, picked from its seed ("" if it rolled them all).
static func null_extra(rng_seed: int) -> String:
	var rolled := rolled_threats(rng_seed)
	var left: Array = STAKEABLE.filter(func(id: String) -> bool: return not id in rolled)
	if left.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = base_of(rng_seed) ^ 0x4E55
	return left[rng.randi_range(0, left.size() - 1)]


## Whether a roll comes up as a Null floor, for a character who chose MERGE: 1 in NULL_FLOOR_ODDS.
static func null_roll(rng_seed: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = base_of(rng_seed) ^ 0x6E11
	return rng.randi_range(1, NULL_FLOOR_ODDS) == 1


## The threats the floor rolled, without stakes.
static func rolled_threats(rng_seed: int) -> PackedStringArray:
	var floor_n := floor_of_seed(rng_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = base_of(rng_seed) ^ 0x7E8A
	var pool: Array = []
	var fixed: Array = []
	for id in DungeonThreats.INFO:
		if id == DungeonThreats.RANDOM:
			continue
		if DungeonThreats.INFO[id].get("fixed", false):
			fixed.append(id)
		else:
			pool.append(id)
	for i in range(pool.size() - 1, 0, -1):          # shuffled with this rng, not the global one
		var j := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var out := PackedStringArray()
	for i in mini(threat_count(floor_n), pool.size()):
		out.append(pool[i])
	if has_fixed_threat(floor_n) and not fixed.is_empty():
		out.append(fixed[rng.randi_range(0, fixed.size() - 1)])
	return out


# ---------- WHAT THREATS PAY ----------
## The rewards for a set of threats: {quantity, item_level, rarity, top_tier, bonus_rare, stack}.
## quantity is a multiplier (1.0 = as usual); the rest are added. No threats: nothing extra.
## null_floor (MERGE's Null floors) adds NULL_QUANTITY and NULL_RARITY on top.
static func rewards_for(threats: PackedStringArray, null_floor := false) -> Dictionary:
	var stack := 1.0 + STACK_BONUS * maxi(threats.size() - 1, 0)
	var out := {"quantity": 1.0, "item_level": 0, "rarity": 0.0, "top_tier": false, "bonus_rare": false,
			"stack": stack, "null_floor": null_floor}
	if null_floor:
		out["quantity"] += NULL_QUANTITY
		out["rarity"] += NULL_RARITY
	for id in threats:
		var r: Dictionary = REWARDS.get(id, {})
		out["quantity"] += float(r.get("quantity", 0.0)) * stack
		out["item_level"] += roundi(float(r.get("item_level", 0)) * stack)
		out["rarity"] += float(r.get("rarity", 0.0)) * stack
		out["top_tier"] = out["top_tier"] or bool(r.get("top_tier", false))
		out["bonus_rare"] = out["bonus_rare"] or bool(r.get("bonus_rare", false))
	out["rarity"] = minf(out["rarity"], 1.0)
	return out


static func reward_text(id: String) -> String:
	return str(REWARDS.get(id, {}).get("text", ""))


## One line for the map: what a set of threats pays in all.
static func rewards_line(threats: PackedStringArray, null_floor := false) -> String:
	if threats.is_empty() and not null_floor:
		return "Nothing extra."
	var r := rewards_for(threats, null_floor)
	var parts := PackedStringArray()
	if r["quantity"] > 1.0:
		parts.append("+%d%% items" % roundi((r["quantity"] - 1.0) * 100.0))
	if r["item_level"] > 0:
		parts.append("+%d item level" % r["item_level"])
	if r["rarity"] > 0.0:
		parts.append("%d%% raised a rarity" % roundi(r["rarity"] * 100.0))
	if r["top_tier"]:
		parts.append("top-tier modifier on rares")
	if r["bonus_rare"]:
		parts.append("a rare on clearing")
	return "  ·  ".join(parts)


# ---------- STAKES (the next run) ----------
static var _stakes := PackedStringArray()          # threats added to the next run (the map sets them)


## The threats the next run adds: at most MAX_STAKES.
static func set_stakes(staked: PackedStringArray) -> void:
	_stakes = staked.slice(0, MAX_STAKES)


static func stakes() -> PackedStringArray:
	return _stakes


## The threats a floor could have staked on it: the ones it doesn't have.
static func stakeable(floor_n: int) -> PackedStringArray:
	var own := floor_threats_of_seed(seed_of(floor_n))
	var out := PackedStringArray()
	for id in STAKEABLE:
		if not id in own:
			out.append(id)
	return out


# ---------- OVERWRITE: PATCHES ----------
## Overwrite players earn a patch for every PATCH_EVERY floors climbed (first clears), holding
## at most MAX_PATCHES, and spend one on a revealed floor's roll before going in:
##   patch_remove   take one of its threats out (and its reward with it)
##   patch_pin      carry one of its threats up to the next floor (and its reward with it)
##   patch_reroll   a new roll for the floor
## The changes live in the floor's seed until it's cleared (then it rolls again).
const PATCH_EVERY := 5
const MAX_PATCHES := 3


static func can_patch(qm: QuestManager) -> bool:
	return (ending_override if ending_override != "" else Endings.current(qm)) == "overwrite"


static func patches() -> int:
	return clampi(int(_data().get("patches", 0)), 0, MAX_PATCHES)


static func _spend_patch(floor_n: int) -> bool:
	if patches() <= 0 or not is_open(floor_n):
		return false
	_data()["patches"] = patches() - 1
	return true


static func patch_remove(floor_n: int, id: String) -> bool:
	var s := seed_of(floor_n)
	if not id in floor_threats_of_seed(s) or not _spend_patch(floor_n):
		return false
	_data()["seeds"][str(floor_n)] = _with_bit(s, REMOVE_SHIFT, id)
	return true


static func patch_pin(floor_n: int, id: String) -> bool:
	if floor_n >= FLOORS or not id in floor_threats_of_seed(seed_of(floor_n)):
		return false
	var above := seed_of(floor_n + 1)
	if id in floor_threats_of_seed(above) or not _spend_patch(floor_n):
		return false
	_data()["seeds"][str(floor_n + 1)] = _with_bit(above, PIN_SHIFT, id)
	return true


static func patch_reroll(floor_n: int) -> bool:
	if not _spend_patch(floor_n):
		return false
	reroll(floor_n)
	return true


# ---------- MERGE: NULL FLOORS ----------
## For a MERGE character, 1 floor roll in NULL_FLOOR_ODDS is a Null floor: one more threat
## (null_extra), more items and rarer ones. The flag is set when the floor is rolled (_roll).
const NULL_FLOOR_ODDS := 4
const NULL_QUANTITY := 0.5
const NULL_RARITY := 0.2


## The ending of the character climbing (this machine's player). Tests can set ending_override.
static var ending_override := ""


static func _ending() -> String:
	if ending_override != "":
		return ending_override
	var tree := Engine.get_main_loop() as SceneTree
	var player := tree.get_first_node_in_group("players") if tree != null else null
	return Endings.current(player.get("quests") as QuestManager) if player != null else ""


## The seed a new run of the floor gets (WorldState._create): its roll plus the stakes, which are
## spent here.
static func run_seed(floor_n: int) -> int:
	var s := with_stakes(seed_of(floor_n), _stakes)
	_stakes = PackedStringArray()
	return s


# ---------- PROGRESS (this character's save) ----------
## The tower opens at the Core once an ending is chosen.
static func is_unlocked(qm: QuestManager) -> bool:
	return Endings.current(qm) != ""


static func _data() -> Dictionary:
	if SaveManager.party.is_empty():
		return _scratch
	var save := SaveManager.get_data(SaveManager.party[0])
	if not save.has(SAVE_KEY) or not (save[SAVE_KEY] is Dictionary):
		save[SAVE_KEY] = {"cleared": 0, "seeds": {}}
	return save[SAVE_KEY]


static var _scratch := {"cleared": 0, "seeds": {}}   # no character loaded (a scene run on its own)


## The highest floor cleared (0 = none).
static func cleared_top() -> int:
	return clampi(int(_data().get("cleared", 0)), 0, FLOORS)


## The highest floor you can enter: the one above the highest cleared.
## A REBOOTED character sees two floors past it (Reboot.tower_reveal) and may skip one.
static func revealed() -> int:
	return mini(cleared_top() + (reveal_override if reveal_override > 0 else Reboot.tower_reveal()), FLOORS)


## Tests only: how many floors past the highest cleared are open (0 = the character's own rule).
static var reveal_override := 0


static func is_open(floor_n: int) -> bool:
	return floor_n >= 1 and floor_n <= revealed()


static func is_cleared(floor_n: int) -> bool:
	return floor_n >= 1 and floor_n <= cleared_top()


## The floor's saved roll, made now if it has none. A floor never looks the same as the one below
## it, when that one is rolled already.
static func seed_of(floor_n: int) -> int:
	floor_n = clampi(floor_n, 1, FLOORS)
	var seeds: Dictionary = _data()["seeds"]
	var key := str(floor_n)
	if not seeds.has(key):
		seeds[key] = _roll(floor_n)
	return int(seeds[key])


static func _roll(floor_n: int) -> int:
	var seeds: Dictionary = _data()["seeds"]
	var below := str(floor_n - 1)
	var avoid := look_index(int(seeds[below])) if seeds.has(below) else -1
	var s := make_seed(randi(), floor_n)
	for i in 12:
		if look_index(s) != avoid:
			break
		s = make_seed(randi(), floor_n)
	if _ending() == "merge" and null_roll(s):
		s |= 1 << NULL_BIT                      # MERGE: the Null built this one
	return s


## A fresh roll for the floor (after it's cleared: the next run is a new one).
static func reroll(floor_n: int) -> int:
	floor_n = clampi(floor_n, 1, FLOORS)
	var s := _roll(floor_n)
	_data()["seeds"][str(floor_n)] = s
	return s


## A floor's exit opened (TowerFloor). Returns true when this reveals a new floor. Only counts for
## this character's own climb: a co-op guest on a floor above their own revealed one gets nothing
## (no carrying a friend to the top).
static func floor_cleared(floor_n: int) -> bool:
	var d := _data()
	var advanced := false
	var was := cleared_top()
	if floor_n > was and floor_n <= revealed() and floor_n <= FLOORS:
		d["cleared"] = floor_n                   # a REBOOT may skip a floor: it counts as climbed
		advanced = true
		for f in range(was + 1, floor_n + 1):
			if f % PATCH_EVERY == 0 and _ending() == "overwrite":
				d["patches"] = mini(patches() + 1, MAX_PATCHES)  # OVERWRITE: a patch earned
	if floor_n <= cleared_top():
		reroll(floor_n)
	return advanced


# ---------- GOING THERE ----------
## Why `floor_n` can't be entered now, or "".
static func blocked_reason(floor_n: int, tree: SceneTree) -> String:
	var player := tree.get_first_node_in_group("players") if tree != null else null
	var qm = player.get("quests") if player != null else null
	if not is_unlocked(qm):
		return "LOCKED: FINISH THE CAMPAIGN FIRST"
	if not is_open(floor_n):
		return "LOCKED: CLEAR FLOOR %d FIRST" % (floor_n - 1)
	var am := tree.get_first_node_in_group("area_manager") as AreaManager
	if am == null:
		return "NO AREA MANAGER"
	if am.is_busy():
		return "TRAVELLING..."
	if player != null:
		var h = player.get("health")
		if h != null and h.current_health <= 0.0:
			return "YOU ARE DEAD"
	return ""


## Sends the party to a floor: always a fresh run of its saved roll.
static func enter(floor_n: int, tree: SceneTree) -> bool:
	if blocked_reason(floor_n, tree) != "":
		return false
	var am := tree.get_first_node_in_group("area_manager") as AreaManager
	am.go_to(SCENE, SPAWN_IN, floor_n, WorldState.ALWAYS_NEW)
	return true
