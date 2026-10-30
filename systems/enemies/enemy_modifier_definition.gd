class_name EnemyModifierDefinition
extends Resource

@export var id: String                     # "enrage", "molten", "fast", "extra_health"
@export var display_name_prefix: String    # "Molten" -> prepended to enemy name
@export var stat_modifiers: Array[Modifier] = []
@export var tags: Array[TagTypes.EnemyTag] = []    # must match/overlap allowed_modifier_tags
@export var on_spawn_script: Script         # optional: attach extra behavior (e.g. spawns fire pools)
@export var weight: int = 100               # for weighted random rolls
@export var min_rarity: String = "magic"    # "normal" never gets mods, "magic"=1, "rare"=2-3, "champion"=3-4
