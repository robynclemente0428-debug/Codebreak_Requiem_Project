class_name ShopDefinition
extends Resource

@export var id: String
@export var display_name: String = "VENDOR"
@export_multiline var greeting: String = "Credits first. Questions later."

## Always on sale, normal rarity (gems come as gems).
@export var fixed_stock: Array[ItemDefinition] = []
## Random picks from this pool, with rolled affixes.
@export var random_pool: Array[ItemDefinition] = []
@export var random_slots: int = 6
@export_range(0.0, 1.0) var magic_chance: float = 0.30
@export_range(0.0, 1.0) var rare_chance: float = 0.10

@export var buy_markup: float = 1.5       # the player pays value x this
@export var sell_ratio: float = 0.4       # the player receives value x this
@export var infinite_fixed: bool = true   # fixed stock is replaced after each purchase

@export_group("Random stock from the item catalog")
@export var use_catalog: bool = true
## Only items under these folders. Empty = every item the catalog finds.
@export_dir var catalog_folders: PackedStringArray = []
@export var include_gems: bool = false
## Items from (stock_level - window) up to stock_level can appear.
@export var level_window: int = 20
## 0 = every eligible item is equally likely. Higher = favour higher-level items.
@export_range(0.0, 3.0) var level_bias: float = 0.5
## Never sold, even if the catalog finds them (test items, quest items...).
@export var excluded_items: Array[ItemDefinition] = []

@export_group("Reroll")
## Shows a REROLL button that replaces the random (catalog) stock for credits.
## Fixed stock stays. Only works on shops with use_catalog on, or a random_pool.
@export var allow_reroll: bool = true
## Price of the first reroll: base + per_level x the shop's stock_level.
@export var reroll_base_cost: int = 40
@export var reroll_cost_per_level: int = 10
## Each reroll in a row costs this much more than the last (1.5 = +50%). The count resets
## whenever the shop restocks on its own (the town is loaded again).
@export var reroll_cost_growth: float = 1.5
