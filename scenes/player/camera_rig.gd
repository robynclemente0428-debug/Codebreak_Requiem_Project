class_name CameraRig
extends Node3D

## The shifting part of the camera rig
## that is moving toward cursor
@onready var offset_rig = $OffsetRig
## Active camera
@onready var camera = $OffsetRig/Camera3D
## Camera debug overlay
@onready var camera_debug = $CameraDebug
## Camera utils
@onready var utils = $CameraUtils

## Camera target to focus on
@export var player: Player
## Enable following to the target
@export var enabled: bool = false	
## Enable camera cursor shift
@export var enable_cursor_shift: bool = true
## The shift only follows the cursor with these weapon types equipped (WeaponTypeDefinition.id).
## Empty = every weapon. With another weapon the camera eases back to centre.
@export var cursor_shift_weapon_types: PackedStringArray = ["sniper"]
## How quickly the camera slides toward the cursor (and back). Higher = faster.
## The old tween felt like about 4.
@export var cursor_shift_speed: float = 1.5

@export_group("Camera to cursor")
## Near radius from which the shift starts to work
## Measured in viewport width rate units (similar to vw in CSS)
@export_range(0, 100)
var near_radius: int = 10
## Shift power at the minimal radius
@export var near_shift = 0.5

## Far radius where shift reaches maximum power
## Measured in viewport width rate units (similar to vw in CSS)
@export_range(0, 100)
var far_radius: int = 30
## Shift power at the maximum radius
@export var far_shift = 6.0

@export_group("Zoom")
## Scroll the mouse wheel to zoom. The camera is orthographic, so zoom is its size (metres of
## world shown vertically): smaller = closer.
@export var zoom_enabled: bool = true
@export var zoom_min_size: float = 4.0        # closest
@export var zoom_max_size: float = 10.0       # farthest
## How much one wheel notch changes the size.
@export var zoom_step: float = 0.5
## How quickly the camera eases to the new zoom. Higher = snappier.
@export var zoom_speed: float = 10.0

@export_group("Camera follow")
## Camera follow duration time in seconds
## Smaller the duration, faster the camera follow speed
@export var follow_duration: float = 100

## Hold the base camera offset from the target
var _offset = Vector3.ZERO
## Hold the value of lookahead shift to cursor
var _lookahead: Vector3 = Vector3.ZERO

## Calculare the base camera offset from the target
func _calc_offset():
	if not player:
		printerr("Player is no assigned")
		return	
	var offset_x = global_position.x - player.position.x
	var offset_z = global_position.z - player.position.z
	_offset = Vector3(offset_x, 0, offset_z)

## The size the camera is easing toward (the scene's size until the wheel moves it).
var _zoom_target := 0.0

func _ready():
	_calc_offset()
	_zoom_target = camera.size
	# Start at the zoom the player left it at last time (saved in user://settings.cfg)
	var saved := float(Settings.get_value("camera", "zoom"))
	if saved > 0.0:
		_zoom_target = clampf(saved, zoom_min_size, zoom_max_size)
		camera.size = _zoom_target


## Mouse wheel zoom. Unhandled only, so lists and panels that scroll keep the wheel to themselves.
func _unhandled_input(event: InputEvent) -> void:
	if not zoom_enabled or not (event is InputEventMouseButton) or not event.pressed:
		return
	if player and player.get("input_locked"):
		return                                   # a shop or dialogue is open
	var dir := 0
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		dir = -1                                 # wheel up: zoom in (smaller size)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		dir = 1
	if dir == 0:
		return
	# Trackpads send fractional wheel steps in `factor`
	var amount: float = zoom_step * (event.factor if event.factor > 0.0 else 1.0)
	_zoom_target = clampf(_zoom_target + dir * amount, zoom_min_size, zoom_max_size)
	Settings.set_value("camera", "zoom", _zoom_target)    # remembered (saved a moment later)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if camera and not is_equal_approx(camera.size, _zoom_target):
		camera.size = lerpf(camera.size, _zoom_target, 1.0 - exp(-zoom_speed * delta))
		if absf(camera.size - _zoom_target) < 0.005:
			camera.size = _zoom_target

func _physics_process(delta):
	if not player || not enabled:
		return

	# Pass 1: take player position + base camera offset
	# This is no ease movement
	var base_pos := global_position
	base_pos.x = player.global_position.x + _offset.x
	base_pos.z = player.global_position.z + _offset.z
	base_pos.y = player.global_position.y + _offset.y
	
	# Pass 2: add lookahead component
	# lookahead eases toward the cursor shift (or back to zero when the shift is off for the
	# current weapon), so swapping weapons never snaps the camera
	global_position = base_pos + _lookahead

	# Recalculate lookahead value for the next iteration
	var target_shift := _add_cursor_offset() if _shift_allowed() else Vector3.ZERO
	_lookahead = _lookahead.lerp(target_shift, 1.0 - exp(-cursor_shift_speed * delta))


## Cursor shift is on, and the player holds one of the weapon types that use it.
func _shift_allowed() -> bool:
	if not enable_cursor_shift:
		return false
	if cursor_shift_weapon_types.is_empty():
		return true
	var equipment = player.get("equipment")
	if not equipment is EquipmentComponent:
		return false
	var weapon: ItemInstance = (equipment as EquipmentComponent).get_equipped(EquipmentSlots.Slot.WEAPON)
	if weapon == null or weapon.definition == null or weapon.definition.weapon_type == null:
		return false
	return weapon.definition.weapon_type.id in cursor_shift_weapon_types

## Returns a new position considering shift to cursor
func _add_cursor_offset() -> Vector3:
	var viewport = get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	var center_pos = viewport.get_visible_rect().size / 2

	#
	# Calculate direction vector from center of screen to cursor
	# and convert it to the viewport width rate (to make it work on all resolutions)
	#
	var offset_vector = mouse_pos - center_pos
	var offset_rate = utils.pixel_to_rate(round(offset_vector.length()))
	
	#
	# Map a value from shift radius range to a shift power range
	#
	var shift = remap(offset_rate, near_radius, far_radius, near_shift, far_shift)

	#
	# Clamp lower value and fix the maximum value
	# translate into vector space to calculate final shift
	#
	var step_shift = step(shift, near_shift, far_shift) 
	var shift_vector = step_shift * offset_vector.normalized();
	return Vector3(shift_vector.x, 0, shift_vector.y)

func step(value, min_value, max_value):
	if value < min_value:
		return 0
	if value > max_value:
		return max_value
	return value
