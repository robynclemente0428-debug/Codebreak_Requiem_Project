class_name CameraRig
extends Node3D

@onready var offset_rig = $OffsetRig
@onready var camera = $OffsetRig/Camera3D
@onready var camera_debug = $CameraDebug
@onready var utils = $CameraUtils

@export var player: Player
@export var enabled: bool = false	
@export var enable_cursor_shift: bool = true
@export var cursor_shift_weapon_types: Array[String] = ["sniper"]
@export var cursor_shift_speed: float = 1.5

@export_group("Camera to cursor")
@export_range(0, 100)
var near_radius: int = 10
@export var near_shift = 0.5

@export_range(0, 100)
var far_radius: int = 30
@export var far_shift = 6.0

@export_group("Zoom")
@export var zoom_enabled: bool = true
@export var zoom_min_size: float = 4.0
@export var zoom_max_size: float = 10.0
@export var zoom_step: float = 0.5
@export var zoom_speed: float = 10.0

@export_group("Camera follow")
@export var follow_duration: float = 100

var _offset = Vector3.ZERO
var _lookahead: Vector3 = Vector3.ZERO

func _calc_offset():
	if not player:
		printerr("Player is no assigned")
		return	
	var offset_x = global_position.x - player.position.x
	var offset_z = global_position.z - player.position.z
	_offset = Vector3(offset_x, 0, offset_z)

var _zoom_target := 0.0

func _ready():
	_calc_offset()
	_zoom_target = camera.size
	var saved := float(Settings.get_value("camera", "zoom"))
	if saved > 0.0:
		_zoom_target = clampf(saved, zoom_min_size, zoom_max_size)
		camera.size = _zoom_target


func _unhandled_input(event: InputEvent) -> void:
	if not zoom_enabled or not (event is InputEventMouseButton) or not event.pressed:
		return
	if player and player.get("input_locked"):
		return
	var dir := 0
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		dir = -1
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		dir = 1
	if dir == 0:
		return
	var amount: float = zoom_step * (event.factor if event.factor > 0.0 else 1.0)
	_zoom_target = clampf(_zoom_target + dir * amount, zoom_min_size, zoom_max_size)
	Settings.set_value("camera", "zoom", _zoom_target)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if camera and not is_equal_approx(camera.size, _zoom_target):
		camera.size = lerpf(camera.size, _zoom_target, 1.0 - exp(-zoom_speed * delta))
		if absf(camera.size - _zoom_target) < 0.005:
			camera.size = _zoom_target

func _physics_process(delta):
	if not player || not enabled:
		return

	var base_pos := global_position
	base_pos.x = player.global_position.x + _offset.x
	base_pos.z = player.global_position.z + _offset.z
	base_pos.y = player.global_position.y + _offset.y
	
	global_position = base_pos + _lookahead

	var target_shift := _add_cursor_offset() if _shift_allowed() else Vector3.ZERO
	_lookahead = _lookahead.lerp(target_shift, 1.0 - exp(-cursor_shift_speed * delta))


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

func _add_cursor_offset() -> Vector3:
	var viewport = get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	var center_pos = viewport.get_visible_rect().size / 2

	var offset_vector = mouse_pos - center_pos
	var offset_rate = utils.pixel_to_rate(round(offset_vector.length()))
	
	var shift = remap(offset_rate, near_radius, far_radius, near_shift, far_shift)

	var step_shift = step(shift, near_shift, far_shift) 
	var shift_vector = step_shift * offset_vector.normalized();
	return Vector3(shift_vector.x, 0, shift_vector.y)

func step(value, min_value, max_value):
	if value < min_value:
		return 0
	if value > max_value:
		return max_value
	return value
