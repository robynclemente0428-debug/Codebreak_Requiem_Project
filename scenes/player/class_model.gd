class_name ClassModel
extends RefCounted
## Puts the right 3D model on the Player for a class.
## The Player scene keeps an empty Node3D called 'model' as the slot. The chosen model
## is instanced under it and renamed 'Body', so scripts can always use $model/Body.

const SLOT_PATH := 'model'
const BODY_NAME := 'Body'

# Save the Rogue's AnimationLibrary here once (see the steps). Models that don't ship their
# own animations get this library, so every class plays the same Idle01 / Walk_F / ... set.
const SHARED_ANIMS_PATH := 'res://scenes/player/animations/player_anims.res'


static func apply(player: Node, class_data: ClassData) -> void:
	if class_data == null or class_data.model_scene == null:
		push_warning('ClassModel: no class or model_scene, leaving the model slot as it is')
		return

	var slot := player.get_node(SLOT_PATH) as Node3D
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()

	var body := class_data.model_scene.instantiate() as Node3D
	body.name = BODY_NAME
	body.scale *= class_data.model_scale
	body.position += class_data.model_offset
	slot.add_child(body)
	_ensure_animations(body)


static func _ensure_animations(body: Node) -> void:
	var ap := body.find_child('AnimationPlayer', true, false) as AnimationPlayer
	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = 'AnimationPlayer'
		body.add_child(ap)                 # root_node defaults to '..', which is the model root
	if ap.has_animation('Idle01'):
		return                             # this model brought its own animations
	if ResourceLoader.exists(SHARED_ANIMS_PATH):
		var lib := load(SHARED_ANIMS_PATH) as AnimationLibrary
		if lib != null:
			ap.add_animation_library('', lib)
	else:
		push_warning('ClassModel: shared animation library not found at %s' % SHARED_ANIMS_PATH)
