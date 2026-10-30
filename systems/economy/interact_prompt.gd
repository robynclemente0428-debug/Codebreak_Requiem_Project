class_name InteractPrompt
extends Label

## Same SubViewportContainer you pass to LootLabels.
@export var container: SubViewportContainer
@export var screen_offset := Vector2(0, -6)

var _target: Interactable
var _viewport: SubViewport

func _ready() -> void:
	add_to_group("interact_prompt")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in container.get_children():
		if c is SubViewport:
			_viewport = c
			break

func show_prompt(target: Interactable) -> void:
	_target = target
	text = "[T] %s" % target.prompt_text
	reset_size()
	visible = true

func hide_prompt(target: Interactable) -> void:
	# Only hide if it's the one currently shown (handles overlapping areas)
	if _target == target:
		_target = null
		visible = false

func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = null
		visible = false
		return

	var cam := _viewport.get_camera_3d()
	if cam == null:
		return

	var world_pos := _target.global_position + Vector3.UP * _target.prompt_height
	if cam.is_position_behind(world_pos):
		visible = false
		return
	visible = true

	# Position inside the (small) SubViewport -> position on the real screen
	var p := cam.unproject_position(world_pos)
	p *= Vector2(container.size) / Vector2(_viewport.size)

	# Anchor the label's bottom-center to the point
	position = p - Vector2(size.x * 0.5, size.y) + screen_offset
