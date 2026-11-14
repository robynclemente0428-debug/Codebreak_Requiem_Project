class_name LootPickup
extends Area3D

const PICKUP_ACTION := &"pickup"          # Input Map action bound to F
const PICKUP_LAYER := 16                  # physics layer 5 ("loot"), used only for mouse picking
const GROUP := &"loot_pickups"            # every drop on the ground

const RARITY_COLORS := {
	"normal": Color(0.60, 0.60, 0.62),    # gray, no glow
	"magic": Color(0.30, 0.64, 1.00),     # blue
	"rare": Color(1.00, 0.82, 0.30),      # yellow
	"champion": Color(1.00, 0.45, 0.15),  # orange
	"skill_gem": Color(0.30, 0.95, 0.60),
	"support_gem": Color(0.45, 0.75, 1.0),
}

@export_group("Label")
@export var label_height: float = 0.7     # metres above the pickup (font size lives on LootLabels now)

var item: ItemInstance        # set by the populator before the pickup enters the tree
## Drops picked up since the game started (the loot lesson in TutorialHints ends on the first).
static var taken := 0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var light: OmniLight3D = $OmniLight3D

var _label: Label             # lives in the HUD overlay (LootLabels), not in the 3D world
var _color := Color.WHITE
var _asked := false           # co-op: we already asked the host for this drop

func _ready() -> void:
	add_to_group(GROUP)
	# Nothing walks into this any more: it only needs to be found by the mouse ray
	collision_layer = PICKUP_LAYER
	collision_mask = 0

	var rarity: String = item.rarity if item != null else "normal"
	if item != null and item.definition != null:   # adjust to your ItemInstance field name
		if item.definition.skill_gem != null:
			rarity = "skill_gem"
		elif item.definition.support_gem != null:
			rarity = "support_gem"
	_color = RARITY_COLORS.get(rarity, RARITY_COLORS["normal"])
	var glows := rarity != "normal"

	# Each pickup builds its own material so colours never leak between drops
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color
	mat.emission_enabled = glows
	mat.emission = _color
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat

	light.visible = glows
	light.light_color = _color

	# The name is drawn by the full-resolution overlay so it stays sharp under the pixel filter
	var overlay := get_tree().get_first_node_in_group("loot_labels") as LootLabels
	if overlay != null:
		_label = overlay.add_label(self, item.get_display_name() if item != null else "?", _color)
	else:
		push_warning("LootPickup: no LootLabels overlay found, so this drop has no name label")

	# Gentle bob so drops are easy to spot
	var tw := create_tween().set_loops()
	tw.tween_property(mesh, "position:y", 0.12, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(mesh, "position:y", 0.0, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if item != null:
		print("Loot dropped: %s [%s]" % [item.get_display_name(), item.rarity])

## Called by the PickupController while the mouse is over this drop.
func set_hovered(on: bool) -> void:
	mesh.scale = Vector3.ONE * (1.5 if on else 1.0)
	if _label != null:
		_label.modulate = Color.WHITE if on else _color

## Moves the item into the backpack. Returns false if it could not be taken.
func try_pickup(inventory: InventoryComponent) -> bool:
	if item == null or inventory == null:
		return false
	if Coop.in_game and has_meta(Coop.LOOT_ID):
		# Co-op: the drop is everyone's. Ask the host; the first to ask has it (Coop._l_taken)
		if inventory.is_full():
			print("Inventory full")
			return false
		if not _asked:
			_asked = true
			Coop.loot_take(self)
		return true
	return give_to(inventory)


## Puts the item in the backpack and removes the drop. False if there was no room.
func give_to(inventory: InventoryComponent) -> bool:
	if not inventory.add_item(item):
		print("Inventory full")
		return false
	taken += 1
	queue_free()
	return true
