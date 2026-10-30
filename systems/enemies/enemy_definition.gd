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
@export var basic_attack_enabled: bool = true
@export var skill_cooldown: float = 6.0
@export var cooldown_jitter: float = 2.0
@export var cast_lock_fraction: float = 1.0 
