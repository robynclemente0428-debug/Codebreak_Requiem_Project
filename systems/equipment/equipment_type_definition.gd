class_name EquipmentTypeDefinition
extends Resource

@export var id: String
@export var display_name: String
@export var slot: EquipmentSlots.Slot = EquipmentSlots.Slot.HEAD   # not WEAPON; weapons use WeaponTypeDefinition
@export var tags: Array[TagTypes.ItemTag] = []                      # which affixes items of this type can roll
