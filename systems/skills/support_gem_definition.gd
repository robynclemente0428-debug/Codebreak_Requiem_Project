class_name SupportGemDefinition
extends Resource

@export var id: String
@export var display_name: String
@export var stat_modifiers: Array[Modifier] = []
@export var flag_modifiers: Dictionary = {}   # e.g. {"arc_angle": 90.0, "max_targets": 4.0}
@export var allowed_tags: Array[TagTypes.TagGem] = []
## Optional. A script extending SupportBehavior, for supports that change what the skill DOES
## (explode on kill, chain, ...). Leave empty for number-only supports.
@export var behavior_script: Script
## Extra knobs players can script while this support is socketed (ids must be unique, e.g.
## "cleave_arc"). They share the skill's point budget and block limit.
@export var program_knobs: Array[SkillKnob] = []
@export var animation_override: String = ""           # e.g. "slam"
## How much more mana the skill costs with this support. 0.3 = 30% more.
@export var mana_cost_increase: float = 0.25
@export_multiline var description: String = ""
