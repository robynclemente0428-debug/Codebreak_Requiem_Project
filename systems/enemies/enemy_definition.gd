class_name EnemyDefinition
extends Resource

@export var id: String
@export var display_name: String
@export var allowed_modifier_tags: Array[TagTypes.EnemyTag] = []

@export_group("Scenes")
@export var scene: PackedScene          # enemy_base.tscn
@export var model_scene: PackedScene    # alien_model.tscn

@export_group("Collision")
@export var capsule_radius: float = 0.4   # sizes your collision shape
@export var capsule_height: float = 1.8

@export_group("Stats")
@export var max_health: float = 30.0
@export var armour: float = 5.0
@export var move_speed: float = 4.0

@export_group("AI")
@export var aggro_range: float = 15.0
@export var attack_range: float = 2.0
@export var preferred_distance: float = 0.0   # 0 = melee, approach freely
@export var flee_distance: float = 0.0        # must be smaller than preferred_distance
@export var kite_delay_min: float = 0.5
@export var kite_delay_max: float = 1.0

@export_group("Combat")
@export var min_attack_damage: float = 4.0
@export var max_attack_damage: float = 8.0
@export var attack_speed: float = 0.5  
@export var skills: Array[SkillGemDefinition] = []
@export var skill_flag_overrides: Dictionary = {}
## Support gems for the skills above: the same ones the player sockets (Aftershock, Tremor
## Chain, Many Projectiles, Cleave, Explode on Kill...). Each support links to every skill
## it fits (its allowed tags), exactly like on the player, so Aftershock only goes on Slam.
@export var skill_supports: Array[SupportGemDefinition] = []
## Per-skill supports, on top of skill_supports: skill gem id -> Array of support ids,
## e.g. {"slam": ["aftershock_support"], "blast": ["many_projectiles_support"]}.
@export var skill_support_ids: Dictionary = {}
## FOR loops on the skills above, as a player would script them: skill gem id -> repeats, e.g.
## {"strike": 2} is "for i in range(2)" on Strike (the cast, then 2 repeats).
@export var skill_loops: Dictionary = {}
@export var basic_attack_enabled: bool = true
@export var skill_cooldown: float = 6.0
@export var cooldown_jitter: float = 2.0
@export var cast_lock_fraction: float = 1.0 

@export_group("Progression")
## An act's boss (Glitchling Queen, Gate Guard, Loop Hound Alpha): the first kill gives every
## knob ScriptBudget.STEPS_PER_ACT_BOSS more steps.
@export var act_boss := false

@export_group("Lock")
## EnemyTrait scripts this enemy always has, whatever its modifiers: a boss lock such as
## ChecksumLock (checksum_lock_trait.gd), the puzzle its fight is built round.
@export var innate_traits: Array[Script] = []

@export_group("Pool")
## Rarities this enemy can spawn as when a dungeon picks it from its theme's enemy_pool, e.g.
## ["rare", "champion"] for an elite that never shows up as a plain mob. Empty = any rarity.
## Hand-placed EnemyMarkers ignore this.
@export var pool_rarities: PackedStringArray = []


func allows_rarity(rarity: String) -> bool:
	return pool_rarities.is_empty() or rarity in pool_rarities


## A random enemy from `pool` that can spawn at `rarity` (null if none can).
static func pick(pool: Array, rarity: String, rng: RandomNumberGenerator = null) -> EnemyDefinition:
	var fits := pool.filter(func(d: EnemyDefinition) -> bool: return d != null and d.allows_rarity(rarity))
	if fits.is_empty():
		return null
	return fits[rng.randi() % fits.size() if rng != null else randi() % fits.size()]
