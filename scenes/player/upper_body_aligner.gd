class_name UpperBodyAligner
extends SkeletonModifier3D
## Keeps an upper-body action (shooting, slashing) facing the way the clip was made to face
## while the legs play a jog.
##
## Why it's needed: the AnimationTree layers the action onto the upper body bone by bone, in
## each bone's LOCAL space. The spine's rotation is relative to the hips, but the hips come
## from the jog clip. Firing_Fast was authored with the hips turned ~90 degrees (a rifle stance)
## and the spine twisted back to face the target; on top of a jog whose hips face forward, that
## spine twist rotates the chest and arms sideways, which looks like a broken skeleton.
##
## The fix: after the tree has posed the skeleton, re-aim the spine so the chest ends up where
## the action clip puts it relative to the character, whatever the hips are doing:
##     spine = jog_hips^-1 * clip_hips * clip_spine

@export var hips_bone := "mixamorig_Hips"
@export var spine_bone := "mixamorig_Spine"

var _clip: Animation
var _hips_track := -1
var _time := 0.0
var _speed := 1.0
var _end := 0.0
var _hips_idx := -1
var _spine_idx := -1


## Call when an upper-body action starts. `track_path` is the hips track in the clip,
## e.g. "Armature/Skeleton3D:mixamorig_Hips".
func begin(clip: Animation, track_path: NodePath, speed: float, duration: float) -> void:
	_clip = clip
	_hips_track = clip.find_track(track_path, Animation.TYPE_ROTATION_3D) if clip else -1
	_time = 0.0
	_speed = speed
	_end = duration
	active = _hips_track >= 0


func stop() -> void:
	active = false
	_clip = null


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_hips_idx = -1


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _clip == null:
		return
	if _hips_idx < 0:
		_hips_idx = skel.find_bone(hips_bone)
		_spine_idx = skel.find_bone(spine_bone)
		if _hips_idx < 0 or _spine_idx < 0:
			push_warning("UpperBodyAligner: bones '%s' / '%s' not found" % [hips_bone, spine_bone])
			stop()
			return
	_time += delta
	if _time >= _end:
		stop()
		return
	var clip_time := minf(_time * _speed, _clip.length)
	var clip_hips := _clip.rotation_track_interpolate(_hips_track, clip_time)
	var jog_hips := skel.get_bone_pose_rotation(_hips_idx)
	var spine := skel.get_bone_pose_rotation(_spine_idx)     # already the clip's spine (filtered layer)
	skel.set_bone_pose_rotation(_spine_idx, (jog_hips.inverse() * clip_hips * spine).normalized())
