@tool
class_name AffixDefinition
extends Resource

enum AffixShape { SIMPLE, DAMAGE_RANGE, PERCENT_RANGE, PERCENT_MULT_RANGE }

const MIN_WEIGHT_FRACTION := 0.05      # never drop below 5% of the base weight

@export var id: String
@export var display_name: String
@export var affix_type: String = "prefix"
@export var shape: AffixShape = AffixShape.SIMPLE:
	set(value):
		shape = value
		notify_property_list_changed()   # makes the Inspector refresh when the dropdown changes
@export var tags: Array[TagTypes.ItemTag] = []
@export var exclusivity_tags: Array[TagTypes.Group] = []
@export var weight: int = 100
@export var min_item_level: int = 1


# --- SIMPLE shape: a single stat, single op ---
# SIMPLE
@export var stat: StatTypes.Stat
@export var op: Modifier.ModOp
# SIMPLE, PERCENT_RANGE, PERCENT_MULT_RANGE
@export var min_value: float
@export var max_value: float

# --- DAMAGE_RANGE shape: "Adds X-Y Fire Damage" ---
# DAMAGE_RANGE, PERCENT_RANGE, PERCENT_MULT_RANGE
@export var min_stat: StatTypes.Stat
@export var max_stat: StatTypes.Stat
# DAMAGE_RANGE only
@export var added_min_low: float = 0.0
@export var added_min_high: float = 0.0
@export var added_max_low: float = 0.0
@export var added_max_high: float = 0.0

## Item levels above min_item_level for the weight to halve. 0 = no falloff.
@export var level_half_life: float = 5.0

const _SIMPLE_ONLY := ["stat", "op"]
const _RANGE_STATS := ["min_stat", "max_stat"]
const _VALUE_FIELDS := ["min_value", "max_value"]
const _ADDED_FIELDS := ["added_min_low", "added_min_high", "added_max_low", "added_max_high"]

func _validate_property(property: Dictionary) -> void:
	var prop: String = property.name
	var show := true
	match shape:
		AffixShape.SIMPLE:
			show = not (prop in _RANGE_STATS or prop in _ADDED_FIELDS)
		AffixShape.DAMAGE_RANGE:
			show = not (prop in _SIMPLE_ONLY or prop in _VALUE_FIELDS)
		_:   # PERCENT_RANGE and PERCENT_MULT_RANGE
			show = not (prop in _SIMPLE_ONLY or prop in _ADDED_FIELDS)
	if not show:
		property.usage = PROPERTY_USAGE_NO_EDITOR   # hidden in the Inspector, still saved in the file

func get_tier_multiplier(levels_behind: int) -> float:
	if level_half_life <= 0.0 or levels_behind <= 0:
		return 1.0
	return pow(0.5, levels_behind / level_half_life)

func get_effective_op() -> Modifier.ModOp:
	match shape:
		AffixShape.DAMAGE_RANGE:
			return Modifier.ModOp.FLAT_ADD
		AffixShape.PERCENT_RANGE:
			return Modifier.ModOp.PERCENT_ADD
		AffixShape.PERCENT_MULT_RANGE:
			return Modifier.ModOp.PERCENT_MULT
		_:
			return op
