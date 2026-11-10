class_name PickupController
extends Node
## Child of the player. Hold the pickup key, hover a drop to see its stats,
## left click to take it.
##
## The player lives inside the pixelated SubViewport, so two things are kept apart:
##  - the mouse ray uses THIS node's viewport (the small 3D one), like before;
##  - the tooltip lives in the HUD and is placed with the MAIN window's mouse position,
##    so it is drawn at full resolution and never gets pixelated.

const PICKUP_ACTION := &"pickup"
const PICKUP_MASK := 16                   # physics layer 5 ("loot")
const TOOLTIP_OFFSET := Vector2(24, 24)   # from the mouse pointer

@export var pickup_range: float = 4.0     # metres from the player
@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent # only used for the "REPLACES" line

@export_group("Tooltip")
@export var hud: Node                     # leave empty to use the Hud that holds LootLabels
@export var accent := Color("#00E5FF")
@export var tooltip_font_scale: float = 1.0
@export var tooltip_width: float = 340.0

var _hovered: LootPickup
var _tooltip: ItemTooltip
var _shown_item: ItemInstance

@onready var _player: Node3D = get_parent()

func _ready() -> void:
	if inventory == null:
		inventory = _player.find_child("InventoryComponent", true, false) as InventoryComponent
	if equipment == null:
		equipment = _player.find_child("EquipmentComponent", true, false) as EquipmentComponent
	assert(inventory != null, "PickupController: assign the Inventory export")

	_tooltip = ItemTooltip.new()
	_tooltip.accent = accent
	_tooltip.font_scale = tooltip_font_scale
	_tooltip.tooltip_width = tooltip_width
	_add_tooltip_to_hud.call_deferred()

func _add_tooltip_to_hud() -> void:
	if hud == null:
		var overlay := get_tree().get_first_node_in_group("loot_labels")
		if overlay != null:
			hud = overlay.get_parent()
	if hud == null:
		push_warning("PickupController: no HUD found (assign the Hud export). " \
			+ "Falling back to the 3D viewport, so the tooltip will look pixelated.")
		hud = self
	hud.add_child(_tooltip)

func _process(_delta: float) -> void:
	var target: LootPickup = null
	if Input.is_action_pressed(PICKUP_ACTION):
		target = _pickup_under_mouse()
	if target != _hovered:
		if is_instance_valid(_hovered):
			_hovered.set_hovered(false)
		_hovered = target
		if _hovered != null:
			_hovered.set_hovered(true)
	_update_tooltip()

func _update_tooltip() -> void:
	if not _tooltip.is_inside_tree():
		return                            # still waiting for the deferred add_child
	if not is_instance_valid(_hovered) or _hovered.item == null:
		_shown_item = null
		_tooltip.hide_item()
		return

	if inventory.is_full():
		_tooltip.set_hint("INVENTORY FULL", true)
	elif _too_far(_hovered):
		_tooltip.set_hint("TOO FAR AWAY", true)
	else:
		_tooltip.set_hint("LEFT CLICK TO PICK UP", false)
	_tooltip.show_item(_hovered.item, equipment)
	if _hovered.item != _shown_item:          # only refit when the item changes
		_shown_item = _hovered.item
		_refit_tooltip()
	# Placement uses the tooltip's own viewport (the real window), NOT the small 3D one
	var ui_viewport := _tooltip.get_viewport()
	var mouse := ui_viewport.get_mouse_position()
	var screen := ui_viewport.get_visible_rect().size
	var pos := mouse + TOOLTIP_OFFSET
	if pos.x + _tooltip.size.x > screen.x - 8.0:
		pos.x = mouse.x - TOOLTIP_OFFSET.x - _tooltip.size.x
	pos.y = clampf(pos.y, 8.0, maxf(8.0, screen.y - _tooltip.size.y - 8.0))
	_tooltip.position = pos
	
func _refit_tooltip() -> void:
	_tooltip.size = Vector2(tooltip_width, 0.0)
	await get_tree().process_frame            # labels wrap at the real width
	await get_tree().process_frame
	if is_instance_valid(_tooltip):
		_tooltip.reset_size() 
		
func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(_hovered):
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _too_far(_hovered):
			return
		if _hovered.try_pickup(inventory):
			_hovered = null
			_tooltip.hide_item()

## The drop under the mouse while the pickup key is held, null for none (for the loot lesson).
func hovered() -> LootPickup:
	return _hovered if is_instance_valid(_hovered) else null


func is_too_far(pickup: LootPickup) -> bool:
	return _too_far(pickup)


func _too_far(pickup: LootPickup) -> bool:
	return _player.global_position.distance_to(pickup.global_position) > pickup_range

func _pickup_under_mouse() -> LootPickup:
	# get_viewport() here is the small SubViewport, which is what the camera expects
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to, PICKUP_MASK)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") as LootPickup

func _exit_tree() -> void:
	if _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.queue_free()             # it lives in the HUD, so clean it up with the player
