class_name EfficiencyTier
extends Resource
## A bonus for keeping a skill program short. The skill gets the first tier (in the order the
## gem's SkillProgramLimits lists them, smallest max_actions first) whose max_actions is not
## exceeded. A program with no rules gets no tier.
## Tier bonuses may push a value past its knob's max_steps: that's the reward.

@export var display_name: String = "Elegant"
## The program may use at most this many blocks (conditions + effects) for this tier.
@export var max_actions: int = 3
## Applied on top of the skill like a support's stat_modifiers.
@export var modifiers: Array[Modifier] = []
## Added to the gem's flags, like a support's flag_modifiers. e.g. {"pierce": 1.0}
@export var flag_bonus: Dictionary = {}
@export_multiline var description: String = ""
