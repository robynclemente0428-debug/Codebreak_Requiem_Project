extends Node3D
## Drives the character model's animations from the player's movement.
## Finds the AnimationPlayer itself, so it works with any class model that
## carries the shared "player_anims" library.

@onready var player: Player = get_parent()
@export var max_action_speed := 8.0
## Slowest a skill clip may play. Below 1.0 short clips (Firing_Fast is 0.3 s) get dragged out
## to fill slow attacks and look like slow motion. 1.0 = never slower than authored.
@export var min_action_speed := 1.0
var _dead := false
## Clips that live in a named library are addressed as "library/clip".
const LIB := "player_anims/"

## 8 movement sectors, 45 degrees apart, starting at "forward" and turning toward
## the character's left: f, forward-left, left, back-left, back, back-right, right, forward-right.
const DIRS := ["f", "f_l", "l", "b_l", "b", "b_r", "r", "f_r"]

## Logical name -> clip name inside the AnimationPlayer.
## To use another clip later, add a line here and call play_action("your_key").
var clips := {
	"idle": LIB + "Idle",
	"f": LIB + "Jog_F",
	"f_l": LIB + "Jog_D_F_L",
	"l": LIB + "Jog_S_L",
	"b_l": LIB + "Jog_D_B_L",
	"b": LIB + "Jog_B",
	"b_r": LIB + "Jog_D_B_R",
	"r": LIB + "Jog_S_R",
	"f_r": LIB + "Jog_D_F_R",
	"slash_l": LIB + "Sword_Slash_L",
	"slash_r": LIB + "Sword_Slash_R",
	"magic": LIB + "Magic_02",
	"slam": LIB + "Slam_attack01",
	"death": LIB + "Death_small_impact",
	"shoot": LIB + "Firing_Fast"
}

## Extra clip sets, picked by WeaponTypeDefinition.animation_set.
var clip_sets := {
	"rifle": {
		"idle": LIB + "Rifle_Idle1",
		"f": LIB + "Forward_Rifle",
		"f_l": LIB + "L_Forward_Dia_Rifle",
		"l": LIB + "L_Strafe_Rifle",
		"b_l": LIB + "L_Backward_Dia_Rifle",
		"b": LIB + "Backward_Rifle",
		"b_r": LIB + "R_Backward_Dia_Rifle",
		"r": LIB + "R_Strafe_Rifle",
		"f_r": LIB + "R_Forward_Dia_Rifle",
		
	},
}

var _clip_set := ""

## Where in each clip (0..1) the hit should land. Tune these by scrubbing the clip.
var hit_points := {
	"slash_l": 0.3,
	"slash_r": 0.3,
	"slam": 0.4,
	"magic": 0.5,
	"shoot": 0.5,
}

## Every one-shot clip a skill can play. A key used by a skill gem's animation_keys must be
## listed here too, or the AnimationTree has no slot for it and play_action() refuses it.
const ACTIONS := ["slash_l", "slash_r", "slam", "magic", "shoot"]

## Aim hold: Firing_Fast is a shoulder-aim clip while the rifle idle/walk clips hold the gun
## at the hip. Snapping between the two on every shot looks like the gun is being twisted, so
## after a shot the upper body stays in the clip's first (shouldered) pose while you keep firing
## and only lowers AIM_HOLD seconds after the last shot.
const AIM_ACTION := "shoot"
const AIM_HOLD := 0.5             # seconds the gun stays up after the last shot ends
const AIM_RAISE := 0.12           # seconds to raise it (first shot of a burst)
const AIM_LOWER := 0.3            # seconds to lower it again
const FIRST_SHOT_FADE := 0.1      # the first shot of a burst blends in this slowly instead of snapping

const SOCKET_R := "WeaponSocket_R"
const SOCKET_L := "WeaponSocket_L"

@export var right_hand_bone := "mixamorig_RightHand"
@export var left_hand_bone := "mixamorig_LeftHand"
@export var upper_body_root := "mixamorig_Spine"

var _grip_r: Node3D
var _grip_l: Node3D
var _held_main: Node3D
var _held_off: Node3D
var _want_main: PackedScene
var _want_off: PackedScene

var _tree: AnimationTree
var _aligner: UpperBodyAligner      # keeps upper-body actions facing forward over a jog
var _gun_aim: GunAimModifier        # levels the gun barrel while aiming (after the aligner)
var _muzzle_for: Node3D             # the held item the barrel below was measured on
var _muzzle_local := Vector3.ZERO   # muzzle point, in the held item's space
var _barrel_local := Vector3.UP     # barrel direction (toward the muzzle), in the held item's space
var _hips_track_path := NodePath()
var _shot: AnimationNodeOneShot
var _shot_full: AnimationNodeOneShot
var _aim_node: AnimationNodeBlend2
var _aim := 0.0                   # 0 = gun at the hip, 1 = shouldered (aim hold)
var _aim_hold := 0.0              # seconds left before it lowers
var _aim_walking := false         # which filter the aim layer has (upper body while moving)

var _action_id := 0

# Extra degrees the current direction is favoured, so diagonals don't flicker
const HYSTERESIS_DEG := 10.0

var animation_player: AnimationPlayer
var _model: Node3D
var _current := ""
var _dir_index := -1
var _action_playing := false
var _slash_left := true

func _clip(key: String) -> String:
	var set_clips: Dictionary = clip_sets.get(_clip_set, {})
	return set_clips.get(key, clips[key])

func _ready() -> void:
	# If a model was placed under this node by hand in the editor, use it.
	for child in get_children():
		if child is Node3D:
			_attach(child)
			break


func _build_tree() -> void:
	if _tree:
		_tree.active = false
		_tree.queue_free()
		_tree = null
		
	var root := AnimationNodeBlendTree.new()
	
	# Locomotion: idle + 8 jog directions, switched by name
	var loco_keys: Array = ["idle"] + DIRS
	var loco := AnimationNodeTransition.new()
	loco.input_count = loco_keys.size()
	loco.xfade_time = 0.15
	root.add_node("loco", loco)
	for i in loco_keys.size():
		var key: String = loco_keys[i]
		loco.set_input_name(i, key)
		var a := AnimationNodeAnimation.new()
		a.animation = _clip(key)      # in the locomotion loop
		root.add_node("loco_" + key, a)
		root.connect_node("loco", i, "loco_" + key)
		
	# Actions: built twice, once per OneShot, since a node can only have one parent
	for suffix in ["", "_full"]:
		var action := AnimationNodeTransition.new()
		action.input_count = ACTIONS.size()
		action.xfade_time = 0.0
		root.add_node("action" + suffix, action)
		for i in ACTIONS.size():
			var key: String = ACTIONS[i]
			action.set_input_name(i, key)
			var a := AnimationNodeAnimation.new()
			a.animation = _clip(key)      # in the actions loop
			root.add_node("act_" + key + suffix, a)
			root.connect_node("action" + suffix, i, "act_" + key + suffix)
		var speed_node := AnimationNodeTimeScale.new()
		root.add_node("action_speed" + suffix, speed_node)
		root.connect_node("action_speed" + suffix, 0, "action" + suffix)
	
	# Aim hold: the shoot clip frozen on its first frame, blended over locomotion while firing
	var aim_clip := AnimationNodeAnimation.new()
	aim_clip.animation = _clip(AIM_ACTION)
	root.add_node("aim_clip", aim_clip)
	var aim_freeze := AnimationNodeTimeScale.new()
	root.add_node("aim_freeze", aim_freeze)
	root.connect_node("aim_freeze", 0, "aim_clip")
	_aim_node = AnimationNodeBlend2.new()
	_aim_node.filter_enabled = false
	root.add_node("aim", _aim_node)
	root.connect_node("aim", 0, "loco")
	root.connect_node("aim", 1, "aim_freeze")
	_aim = 0.0
	_aim_hold = 0.0
	_aim_walking = false

	# Shot 1: upper body only, layered over locomotion (used while moving)
	_shot = AnimationNodeOneShot.new()
	_shot.fadein_time = 0.02
	_shot.fadeout_time = 0.02
	_shot.filter_enabled = true
	root.add_node("shot", _shot)
	root.connect_node("shot", 0, "aim")
	root.connect_node("shot", 1, "action_speed")
	
	# Shot 2: whole body, layered on top of shot 1 (used while standing still)
	_shot_full = AnimationNodeOneShot.new()
	_shot_full.fadein_time = 0.02
	_shot_full.fadeout_time = 0.02
	_shot_full.filter_enabled = false
	root.add_node("shot_full", _shot_full)
	root.connect_node("shot_full", 0, "shot")
	root.connect_node("shot_full", 1, "action_speed_full")
	root.connect_node("output", 0, "shot_full")
	
	_filter_upper_body()
	
	_tree = AnimationTree.new()
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(animation_player)
	_tree.tree_root = root
	_tree.active = true
	_tree.set("parameters/aim_freeze/scale", 0.0)       # hold the first frame
	_tree.set("parameters/aim/blend_amount", 0.0)

func _filter_upper_body() -> void:
	var skels := _model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		push_warning("No Skeleton3D found, upper-body filter skipped")
		return
	var skel: Skeleton3D = skels[0]
	_add_aligner(skel)
	
	# Uncomment once to see your bone names:
	# for i in skel.get_bone_count(): print(skel.get_bone_name(i))
	
	var start := skel.find_bone(upper_body_root)
	if start == -1:
		push_warning("Bone '%s' not found, check upper_body_root" % upper_body_root)
		return
		
	# Track paths are relative to the AnimationPlayer's root node
	var anim_root := animation_player.get_node(animation_player.root_node)
	var skel_path := String(anim_root.get_path_to(skel))
	
	_hips_track_path = NodePath("%s:%s" % [skel_path, _aligner.hips_bone])

	for i in skel.get_bone_count():
		var b := i
		while b != -1 and b != start:
			b = skel.get_bone_parent(b)
		if b == start:   # bone i is the upper-body root or one of its descendants
			var path := NodePath("%s:%s" % [skel_path, skel.get_bone_name(i)])
			_shot.set_filter_path(path, true)
			_aim_node.set_filter_path(path, true)        # only used while moving

## Re-aims the spine during upper-body actions (see UpperBodyAligner for why).
func _add_aligner(skel: Skeleton3D) -> void:
	if _aligner and is_instance_valid(_aligner):
		_aligner.queue_free()
	_aligner = UpperBodyAligner.new()
	_aligner.name = "UpperBodyAligner"
	_aligner.spine_bone = upper_body_root
	_aligner.active = false
	skel.add_child(_aligner)
	if _gun_aim and is_instance_valid(_gun_aim):
		_gun_aim.queue_free()
	_gun_aim = GunAimModifier.new()
	_gun_aim.name = "GunAimModifier"
	_gun_aim.hand_bone = right_hand_bone
	_gun_aim.model = self
	_gun_aim.influence = 0.0
	skel.add_child(_gun_aim)                # after the aligner: runs on the corrected spine

## Instances a model under this node. Call it when the player's class is known.
func set_model(scene: PackedScene, model_scale := 1.0, offset := Vector3.ZERO) -> void:
	if _model:
		_model.queue_free()
		_model = null
	if scene == null:
		return
	var m := scene.instantiate() as Node3D
	add_child(m)
	m.scale = Vector3.ONE * model_scale
	m.position = offset
	_attach(m)


func _attach(m: Node3D) -> void:
	_build_sockets(m)
	_model = m
	_current = ""
	_dir_index = -1
	_action_playing = false
	animation_player = null

	var found := m.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		push_warning("Model has no AnimationPlayer")
		return
	animation_player = found[0]
	animation_player.playback_default_blend_time = 0.2

	# Idle and jog loop; slashes, magic and slam play once
	_apply_loop_modes()
	_build_tree()

func _apply_loop_modes() -> void:
	var looping: Array = ["idle"] + DIRS
	var all_sets: Array = [clips]
	all_sets.append_array(clip_sets.values())
	for d: Dictionary in all_sets:
		for key in d:
			var clip: String = d[key]
			if not animation_player.has_animation(clip):
				push_warning("Missing animation '%s'. Available: %s" % [clip, animation_player.get_animation_list()])
				continue
			animation_player.get_animation(clip).loop_mode = \
				Animation.LOOP_LINEAR if key in looping else Animation.LOOP_NONE

func set_animation_set(set_name: String) -> void:
	if set_name == _clip_set:
		return
	_clip_set = set_name
	if animation_player == null or _dead:
		return
	_apply_loop_modes()
	_current = ""          # makes _process request the right state again
	_dir_index = -1
	_build_tree()

func _process(delta: float) -> void:
	if _tree == null or _dead:
		return
	_update_aim(delta)
	var key := "idle"
	if player.walking:
		key = _pick_direction()
	else:
		_dir_index = -1
	if key == _current:
		return
	_current = key
	_tree.set("parameters/loco/transition_request", key)


func _play_loop(key: String) -> void:
	if key == _current:
		return                      # already playing it, don't restart every frame
	_current = key
	var clip: String = clips[key]
	if animation_player.has_animation(clip):
		animation_player.play(clip)
	else:
		animation_player.stop()

func get_clip_length(action: StringName) -> float:
	var clip := String(clips.get(String(action), String(action)))
	if animation_player and animation_player.has_animation(clip):
		return animation_player.get_animation(clip).length
	return 0.0

## Plays an action sped up so it finishes inside `fit_duration`, and returns
## how many seconds until the hit should land (0 if nothing played).
func play_fitted_action(action: StringName, fit_duration: float) -> float:
	var length := get_clip_length(action)
	if animation_player == null or length <= 0.0 or fit_duration <= 0.0 or _action_playing:
		return 0.0
	var interval := fit_duration * 0.9
	var speed := clampf(length / interval, min_action_speed, max_action_speed)
	play_action(action, speed, interval)
	return length * float(hit_points.get(String(action), 0.5)) / speed

## Picks one of the 8 jog directions from the player's velocity, relative to where it faces.
func _pick_direction() -> String:
	var world_vel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var local_vel := player.global_transform.basis.inverse() * world_vel

	# 0 deg = forward, 90 = left (+x), 180 = backward, -90 = right
	var angle := rad_to_deg(atan2(local_vel.x, local_vel.z))
	var idx := posmod(roundi(angle / 45.0), 8)

	# Stay on the current direction until the angle is clearly past the boundary
	if _dir_index >= 0 and idx != _dir_index:
		var center := _dir_index * 45.0
		if absf(wrapf(angle - center, -180.0, 180.0)) < 22.5 + HYSTERESIS_DEG:
			idx = _dir_index
	_dir_index = idx
	return DIRS[idx]


## Raises / holds / lowers the shouldered pose (see AIM_HOLD).
func _update_aim(delta: float) -> void:
	if _aim_node == null:
		return
	if _aim_hold > 0.0:
		_aim_hold -= delta
		_aim = move_toward(_aim, 1.0, delta / AIM_RAISE)
	else:
		_aim = move_toward(_aim, 0.0, delta / AIM_LOWER)
	_tree.set("parameters/aim/blend_amount", _aim)
	if _gun_aim and is_instance_valid(_gun_aim):
		_gun_aim.influence = _aim
		_gun_aim.active = _aim > 0.0
	# Moving: upper body only, legs keep walking. Standing: the whole stance.
	if player.walking != _aim_walking:
		_aim_walking = player.walking
		_aim_node.filter_enabled = _aim_walking
	# While moving, the spine needs the same fix as an upper-body shot (UpperBodyAligner),
	# here for the clip's first frame. During a shot play_action() drives the aligner itself.
	if _aligner == null or not is_instance_valid(_aligner) or _action_playing:
		return
	if _aim > 0.0 and player.walking:
		if not _aligner.active:
			_aligner.begin(animation_player.get_animation(_clip(AIM_ACTION)), _hips_track_path, 0.0, INF)
		_aligner.influence = _aim
	elif _aligner.active:
		_aligner.stop()
		_aligner.influence = 1.0


## One-shot animation. Pass a key from `clips` ("slam", "magic", "slash_l", ...)
## or a full clip name. Walking and idle pause until it finishes.
func play_action(action: StringName, speed := 1.0, max_lock := -1.0) -> void:
	if _tree == null or _action_playing:
		return
	var key := String(action)
	if key not in ACTIONS:
		push_warning("Unknown action: %s" % key)
		return
	_action_playing = true

	# Standing still -> full body. Moving -> upper body over the jog.
	var suffix := "" if player.walking else "_full"
	var shot_name := "shot" if player.walking else "shot_full"
	var play_len := get_clip_length(key) / speed
	if key == AIM_ACTION and _aim_node != null:
		# First shot of a burst: blend up instead of snapping; later shots start from the
		# shouldered pose already, so they can cut in quickly.
		var fade := FIRST_SHOT_FADE if _aim < 0.5 else 0.02
		_shot.fadein_time = fade
		_shot_full.fadein_time = fade
		_aim_hold = play_len + AIM_HOLD
	else:
		_shot.fadein_time = 0.02
		_shot_full.fadein_time = 0.02
	_tree.set("parameters/action%s/transition_request" % suffix, key)
	_tree.set("parameters/action_speed%s/scale" % suffix, speed)
	_tree.set("parameters/%s/request" % shot_name, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	var play_time := get_clip_length(key) / speed
	if _aligner and is_instance_valid(_aligner):
		_aligner.influence = 1.0
		if player.walking:
			_aligner.begin(animation_player.get_animation(_clip(key)), _hips_track_path, speed, play_time)
		else:
			_aligner.stop()
	if max_lock > 0.0:
		play_time = minf(play_time, max_lock)
	await get_tree().create_timer(play_time).timeout
	_action_playing = false

## Plays the death clip once and locks the model on its final pose.
func play_death() -> void:
	if animation_player == null or _dead:
		return
	var clip: String = clips["death"]
	if not animation_player.has_animation(clip):
		push_warning("Missing death animation: %s" % clip)
		return
	_dead = true
	_tree.active = false
	animation_player.play(clips["death"])

## Undo play_death(): back to idle/walk control.
func revive() -> void:
	if not _dead:
		return
	_dead = false
	_action_playing = false
	_current = ""
	_dir_index = -1
	animation_player.stop()
	_apply_loop_modes()
	_build_tree()        # makes a fresh, active tree; also picks up any weapon-set change made while dead

## Basic attack that alternates left and right slashes.
func attack_combo() -> void:
	if _action_playing:
		return
	play_action("slash_l" if _slash_left else "slash_r")
	_slash_left = not _slash_left

## Where a shot leaves the gun: the muzzle of the held main-hand item. null when nothing is
## held. Shoot uses this so bullets come out of the barrel.
func get_muzzle_point() -> Variant:
	if not _measure_held():
		return null
	return _held_main.global_transform * _muzzle_local


## The barrel direction (toward the muzzle) in the held item's own space. GunAimModifier
## levels this line.
func get_barrel_local() -> Vector3:
	_measure_held()
	return _barrel_local


func _measure_held() -> bool:
	if _held_main == null or not is_instance_valid(_held_main):
		return false
	if _muzzle_for != _held_main:
		_muzzle_for = _held_main
		_measure_barrel(_held_main)
	return true


## Finds the barrel from the gun's geometry, however the model is rotated inside its scene:
## the longest side of its biggest mesh is the barrel, and the end farther from the grip (the
## item's origin, which sits in the hand) is the muzzle.
func _measure_barrel(item: Node3D) -> void:
	_muzzle_local = Vector3.ZERO
	_barrel_local = Vector3.UP
	var best: MeshInstance3D = null
	var best_vol := -1.0
	for mi in item.find_children("*", "MeshInstance3D", true, false):
		var v := (mi as MeshInstance3D).get_aabb().get_volume()
		if v > best_vol:
			best_vol = v
			best = mi
	if best == null:
		return
	var box := best.get_aabb()
	var k := 0                                   # longest axis of the mesh's own box
	for i in 3:
		if box.size[i] > box.size[k]:
			k = i
	var c := box.get_center()
	var a := c
	var b := c
	a[k] = box.position[k]
	b[k] = box.end[k]
	var to_item: Transform3D = item.global_transform.affine_inverse() * best.global_transform
	var end_a: Vector3 = to_item * a
	var end_b: Vector3 = to_item * b
	if end_a.length() > end_b.length():
		_muzzle_local = end_a
		_barrel_local = (end_a - end_b).normalized()
	else:
		_muzzle_local = end_b
		_barrel_local = (end_b - end_a).normalized()


## Call whenever the equipped weapon or off-hand changes. null empties that hand.
func set_held_items(main_hand: PackedScene, off_hand: PackedScene) -> void:
	_want_main = main_hand
	_want_off = off_hand
	_apply_held_items()

func _apply_held_items() -> void:
	_held_main = _swap_held(_grip_r, _held_main, _want_main)
	_held_off = _swap_held(_grip_l, _held_off, _want_off)

func _swap_held(grip: Node3D, current: Node3D, scene: PackedScene) -> Node3D:
	if current != null and is_instance_valid(current):
		current.queue_free()
	if grip == null or scene == null:
		return null
	var held := scene.instantiate() as Node3D
	grip.add_child(held)
	return held
	
func _build_sockets(m: Node3D) -> void:
	_grip_r = null
	_grip_l = null
	_held_main = null
	_held_off = null
	var skeletons := m.find_children("*", "Skeleton3D", true, false)
	var skeleton: Skeleton3D = skeletons[0] if not skeletons.is_empty() else null
	_grip_r = _find_grip(m, skeleton, SOCKET_R, right_hand_bone)
	_grip_l = _find_grip(m, skeleton, SOCKET_L, left_hand_bone)
	_apply_held_items()

func _find_grip(m: Node3D, skeleton: Skeleton3D, socket_name: String, bone: String) -> Node3D:
	# A socket you placed in the model scene wins. Its "Grip" child holds the tuned transform.
	var socket := m.find_child(socket_name, true, false)
	if socket != null:
		var existing := socket.get_node_or_null("Grip") as Node3D
		return existing if existing != null else socket as Node3D

	# Otherwise build one on the hand bone
	if skeleton == null or skeleton.find_bone(bone) < 0:
		push_warning("No %s in the model and no bone '%s' to build one on" % [socket_name, bone])
		return null
	var attach := BoneAttachment3D.new()
	attach.name = socket_name
	skeleton.add_child(attach)
	attach.bone_name = bone
	var grip := Node3D.new()
	grip.name = "Grip"
	attach.add_child(grip)
	# Cancel the rig's own scale (the Raider's Armature is scaled 1.88) so weapons keep their authored size
	var rig_scale := skeleton.global_transform.basis.get_scale() / m.global_transform.basis.get_scale()
	grip.scale = Vector3.ONE / rig_scale
	grip.rotation_degrees = Vector3(0, 0, 0)   # tune once, then leave it
	grip.position = Vector3(0, 0, 0)           # tune once, then leave it
	return grip

## The nodes currently held in the hands, main hand first.
func get_held_items() -> Array:
	var out: Array = []
	for n in [_held_main, _held_off]:
		if n != null and is_instance_valid(n):
			out.append(n)
	return out
