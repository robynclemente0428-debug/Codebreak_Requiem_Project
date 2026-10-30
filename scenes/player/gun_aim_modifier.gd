class_name GunAimModifier
extends SkeletonModifier3D
## Points the held gun's barrel (level) at the player's aim point (Player.get_aim_point(): ahead
## of the player, as far as the cursor) while aiming / firing, so the barrel lines up with the
## cursor even though the gun sits at the shoulder. Rotates the right hand bone so the gun attached to it lines up; the clip's
## arm and body pose stay as they are. Its `influence` is driven by the model (0 = off, 1 = on),
## so it eases in and out with the aim hold.
##
## Set `model` (player/model.gd). The barrel direction comes from model.get_barrel_local(),
## measured from the gun's own geometry.

@export var hand_bone := "mixamorig_RightHand"
var model: Node3D                 # the player's model node (model.gd)

var _hand := -1


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_hand = -1


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or model == null or not is_instance_valid(model):
		return
	var held: Node3D = model.get("_held_main")
	var grip: Node3D = model.get("_grip_r")
	if held == null or not is_instance_valid(held) or grip == null or not is_instance_valid(grip):
		return
	if _hand < 0:
		_hand = skel.find_bone(hand_bone)
		if _hand < 0:
			return
	# The gun hangs rigidly off the hand: find its barrel in the hand bone's space.
	var socket := _attachment_of(grip)
	if socket == null:
		return
	var gun_in_hand: Basis = (socket.global_transform.affine_inverse() * held.global_transform).basis.orthonormalized()
	var barrel_in_hand: Vector3 = gun_in_hand * (model.call("get_barrel_local") as Vector3)

	var hand_pose := skel.get_bone_global_pose(_hand)
	var barrel: Vector3 = (hand_pose.basis.orthonormalized() * barrel_in_hand).normalized()
	# Toward the aim point (or straight ahead), flat, in skeleton space
	var owner_3d: Node3D = model.get_parent() as Node3D
	var dir_world := owner_3d.global_basis.z
	if owner_3d.has_method("get_aim_point"):
		var hand_world: Vector3 = skel.global_transform * hand_pose.origin
		dir_world = (owner_3d.get_aim_point() as Vector3) - hand_world
	dir_world.y = 0.0
	if dir_world.length() < 0.01:
		return
	var want: Vector3 = (skel.global_basis.orthonormalized().inverse() * dir_world.normalized()).normalized()
	if barrel.dot(want) > 0.99999:
		return
	var turn := Quaternion(barrel, want)
	var new_global := Basis(turn) * hand_pose.basis.orthonormalized()
	var parent := skel.get_bone_parent(_hand)
	var parent_basis := skel.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	skel.set_bone_pose_rotation(_hand, (parent_basis.inverse() * new_global).get_rotation_quaternion())


## The BoneAttachment3D (weapon socket) above the grip.
static func _attachment_of(n: Node) -> Node3D:
	while n != null:
		if n is BoneAttachment3D:
			return n
		n = n.get_parent()
	return null
