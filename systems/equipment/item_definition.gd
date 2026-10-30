class_name ItemDefinition
extends Resource

@export var id: String
@export var display_name: String
@export var icon: Texture2D
@export var mesh: PackedScene            # for 3D equip visuals / pickups
@export var weapon_type: WeaponTypeDefinition        # weapons only
@export var equipment_type: EquipmentTypeDefinition  # everything else
@export var base_stats: Dictionary = {}    # StatTypes.Stat -> float, e.g. weapon base damage
@export var item_level: int = 1
@export var allowed_affix_tags: Array[TagTypes.ItemTag] = []
@export var skill_gem: SkillGemDefinition       # set on skill gem items
@export var support_gem: SupportGemDefinition   # set on support gem items
@export var stim: StimDefinition                 # set on health / mana stim items

@export var base_value: int = 10     # gold value of a normal-rarity copy; gems usually higher

func get_slot() -> int:   # -1 means "no type set"
	# at the top of get_slot():
	if is_gem():
		return -1
	if stim != null:
		return EquipmentSlots.Slot.STIM_1          # EquipmentComponent picks the free stim slot
	if weapon_type != null:
		return EquipmentSlots.Slot.WEAPON
	if equipment_type != null:
		return equipment_type.slot
	push_error("Item '%s' has neither a weapon_type nor an equipment_type" % id)
	return -1

func is_gem() -> bool:
	return skill_gem != null or support_gem != null


func is_stim() -> bool:
	return stim != null

func get_description() -> String:
	if skill_gem != null:
		return skill_gem.description
	if support_gem != null:
		return support_gem.description
	return ""
