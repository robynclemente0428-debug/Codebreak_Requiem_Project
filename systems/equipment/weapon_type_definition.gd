class_name WeaponTypeDefinition
extends Resource


@export var id: String
@export var display_name: String
@export var tags: Array[TagTypes.ItemTag] = []
@export var base_range: float = 0.3     # meters added on top of the body's reach
@export var attack_behavior_script: Script
@export var animation_set: String = "" 
@export var two_handed: bool = false
## Flat mana added to every cast of a skill that needs a weapon (SkillGemDefinition.required_weapon_types)
## while this weapon type is equipped, after all other cost changes (SkillInstance.get_mana_cost).
## The sniper's +5: Shoot is cheap, and one sniper shot does several rifle shots' work.
@export var skill_mana_cost: float = 0.0
