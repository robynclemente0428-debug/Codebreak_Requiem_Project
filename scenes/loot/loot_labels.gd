class_name LootLabels
extends Control
## Draws loot names at full screen resolution.
##
## The world is rendered in a SubViewport at 1/3 resolution (the pixelated look), so a Label3D
## inside it is drawn with a third of the pixels and comes out blurry. These labels are normal
## 2D controls in the HUD, so they stay sharp. Each frame the overlay projects every pickup's
## position through the world camera and moves its label there.
##
## Setup: add a plain Control as the FIRST child of the Hud CanvasLayer, attach this script.

const SHOW_ACTION := &"pickup"        # hold F to show names
const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"

@export var container: SubViewportContainer   # leave empty to find "SubViewportContainer" automatically
@export var font: Font
@export var font_size: int = 18
@export var outline_size: int = 5

## Settings (Gameplay tab): show names without holding the key, and hide low-rarity names.
var always_show := false
## "hold" or "always" (the setting's value). Sets always_show.
var item_labels := "hold":
	set(value):
		item_labels = str(value)
		always_show = item_labels == "always"
var loot_filter := "all"           # "all", "magic" or "rare"
const _FILTER_HIDES := {"all": [], "magic": ["normal"], "rare": ["normal", "magic"]}

var _viewport: SubViewport
var _labels: Dictionary = {}                  # LootPickup -> Label


func _enter_tree() -> void:
	add_to_group("loot_labels")


func _ready() -> void:
	Settings.bind_to(self, &"loot_filter", "gameplay", "loot_filter")
	Settings.bind_to(self, &"item_labels", "gameplay", "item_labels")
	mouse_filter = Control.MOUSE_FILTER_IGNORE    # never block clicks: the pickup raycast needs them
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	if font == null and ResourceLoader.exists(DEFAULT_FONT):
		font = load(DEFAULT_FONT)
	if container == null:
		container = get_tree().current_scene.find_child("SubViewportContainer", true, false) as SubViewportContainer
	if container == null:
		push_warning("LootLabels: no SubViewportContainer found, assign the Container export")
		return
	for child in container.get_children():
		if child is SubViewport:
			_viewport = child
			break


## Called by each LootPickup when it appears. Returns the label so the pickup can recolour it.
func add_label(pickup: LootPickup, text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", outline_size)
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	add_child(label)
	_labels[pickup] = label
	return label


func _process(_delta: float) -> void:
	var showing := always_show or Input.is_action_pressed(SHOW_ACTION)
	visible = showing
	if not showing or _viewport == null or container == null:
		return
	var cam := _viewport.get_camera_3d()
	if cam == null:
		return

	# The container stretches the small viewport image up to the real screen size
	var ratio := container.size / Vector2(_viewport.size)

	for pickup in _labels.keys():
		var label: Label = _labels[pickup]
		if not is_instance_valid(pickup):          # the drop was picked up
			label.queue_free()
			_labels.erase(pickup)
			continue
		if _filtered(pickup):
			label.visible = false
			continue
		var world_pos: Vector3 = pickup.global_position + Vector3.UP * pickup.label_height
		if cam.is_position_behind(world_pos):
			label.visible = false
			continue
		var screen_pos := cam.unproject_position(world_pos) * ratio + container.global_position
		# Whole pixels only, so the text doesn't shimmer as the camera moves
		label.position = (screen_pos - label.get_combined_minimum_size() * 0.5).round()
		label.visible = true


## True when the loot filter hides this drop's name. Gems are never hidden.
func _filtered(pickup: LootPickup) -> bool:
	var item := pickup.item
	if item == null or item.definition == null or item.definition.is_gem():
		return false
	return item.rarity in _FILTER_HIDES.get(loot_filter, [])
