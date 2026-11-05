class_name SkillGemDefinition
extends Resource

@export var id: String
@export var display_name: String
@export var behavior_script: Script
## Applied on top of the caster's final stats when the skill is cast, exactly like a support's
## stat_modifiers. Example: Slam = SKILL_DAMAGE_MULT, PERCENT_MULT, 1.0 (100% more damage).
@export var stat_modifiers: Array[Modifier] = []
@export var base_flags: Dictionary = {}     # e.g. {"arc_angle": 90.0, "range": 2.5}
@export var tags: Array[TagTypes.TagGem] = []
@export var animation_keys: Array[String] = []   # cycled in order, e.g. ["slash_l", "slash_r"]
@export var max_support_slots: int = 3
## What players may change on this skill with a SkillProgram. Empty = not programmable.
@export var program_limits: SkillProgramLimits
@export var base_mana_cost: float = 0.0
@export var required_weapon_types: Array[WeaponTypeDefinition] = []   # empty = no requirement
@export_multiline var description: String = ""
