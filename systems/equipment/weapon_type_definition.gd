class_name WeaponTypeDefinition
extends Resource


@export var id: String
@export var display_name: String
@export var tags: Array[TagTypes.ItemTag] = []
@export var base_range: float = 0.3     # meters added on top of the body's reach
@export var attack_behavior_script: Script
@export var animation_set: String = "" 
@export var two_handed: bool = false
