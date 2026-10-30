class_name EnemyModel
extends Node3D

signal death_finished

@export var animation_player: AnimationPlayer
@export var hit_point := 0.5            # 0..1, where in the clip the hit lands

@export var debug_attack_timer := true

@export_group("Animation names")
@export var idle_anim: StringName = &"Monster05_Idle"
@export var move_anim: StringName = &"Monster05_Run"
@export var attack_anim: StringName = &"Monster05_Attack01"
@export var death_anim: StringName = &"Monster05_Die"
@export var backpedal_anim: StringName = &""    # empty = just use move_anim

@export_group("Skill animations")
## Clip to play for each skill key, for THIS model. Example: {"slam": "Monster05_Attack02"}.
## Keys are the gem's animation keys: "slam", "slash_l", "slash_r", "magic".
## A key that isn't listed uses the player's clip if this model carries the player_anims library,
## and otherwise falls back to attack_anim.
@export var skill_anims: Dictionary[String, String] = {}
## Where in each skill clip (0..1) the hit lands. Keys not listed use hit_point (or the player's value).
@export var skill_hit_points: Dictionary[String, float] = {}

const PLAYER_LIB := "player_anims/"
const PLAYER_CLIPS := {
	"slash_l": "Sword_Slash_L",
	"slash_r": "Sword_Slash_R",
	"slam": "Slam_attack01",
	"magic": "Magic_02",
}
const PLAYER_HIT_POINTS := {"slash_l": 0.3, "slash_r": 0.3, "slam": 0.4, "magic": 0.5}

const RUN_ENTER := 1.2    # speed it must exceed to start running
const RUN_EXIT := 1     # speed it must drop below to go idle

var _body: CharacterBody3D
var _chasing := false
var _moving := false
var _speed := 0.0
var _skill_busy_until := 0   # ms: while a skill clip plays, idle/run must not replace it
var _ai: AIComponent
var _backpedaling := false
var _dead := false
func _ready() -> void:
	if animation_player == null:
		animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		push_warning("%s has no AnimationPlayer" % name)
		return

	animation_player.playback_default_blend_time = 0.2
	# Clips inside a named library are addressed as "library/clip" ("player_anims/Idle").
	# Accept either spelling in the Inspector.
	idle_anim = _resolve(idle_anim)
	move_anim = _resolve(move_anim)
	attack_anim = _resolve(attack_anim)
	death_anim = _resolve(death_anim)
	backpedal_anim = _resolve(backpedal_anim)
	if animation_player.has_animation(backpedal_anim):
		animation_player.get_animation(backpedal_anim).loop_mode = Animation.LOOP_LINEAR
	for anim_name in [idle_anim, move_anim]:
		if animation_player.has_animation(anim_name):
			animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		else:
			push_warning("Missing animation: %s (available: %s)" % [anim_name, animation_player.get_animation_list()])
	var found := find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		animation_player = found[0]

## Plays the attack sped up to fit the cooldown. Returns seconds until the hit lands.
func play_attack(fit_duration: float) -> float:
	if animation_player == null or not animation_player.has_animation(attack_anim):
		return 0.0
	var anim := animation_player.get_animation(attack_anim)
	anim.loop_mode = Animation.LOOP_NONE
	var speed := clampf(anim.length / (fit_duration * 0.9), 0.4, 5.0)
	animation_player.play(attack_anim, -1.0, speed)
	animation_player.queue(idle_anim)
	return anim.length * hit_point / speed

## Plays the clip for a skill ("slam", "slash_l", ...) sped up to fit `fit_duration`.
## Returns seconds until the hit lands, or 0 if there is nothing to play.
## Same job as Player.play_skill_animation(), so skill behaviors can't tell the difference.
func play_skill(key: String, fit_duration: float) -> float:
	if animation_player == null or key == "" or fit_duration <= 0.0:
		return 0.0
	var clip := _skill_clip(key)
	if clip == &"":
		return 0.0
	var anim := animation_player.get_animation(clip)
	anim.loop_mode = Animation.LOOP_NONE
	var speed := clampf(anim.length / (fit_duration * 0.9), 0.4, 5.0)

	var hit_at := hit_point
	if skill_hit_points.has(key):
		hit_at = float(skill_hit_points[key])
	elif String(clip).begins_with(PLAYER_LIB):
		hit_at = float(PLAYER_HIT_POINTS.get(key, hit_point))

	_skill_busy_until = Time.get_ticks_msec() + int(anim.length / speed * 1000.0)
	animation_player.play(clip, -1.0, speed)
	animation_player.queue(idle_anim)
	return anim.length * hit_at / speed

func _skill_clip(key: String) -> StringName:
	if skill_anims.has(key):
		var own := _resolve(StringName(skill_anims[key]))
		if animation_player.has_animation(own):
			return own                                              # 1. this model's own clip
	if PLAYER_CLIPS.has(key):
		var shared := StringName(PLAYER_LIB + String(PLAYER_CLIPS[key]))
		if animation_player.has_animation(shared):
			return shared                                           # 2. the player's clip
	if animation_player.has_animation(attack_anim):
		return attack_anim                                          # 3. plain attack
	return &""

## Returns the clip's real name: as given if it exists, otherwise with the player_anims/ prefix.
func _resolve(clip: StringName) -> StringName:
	if animation_player == null or animation_player.has_animation(clip):
		return clip
	var prefixed := StringName(PLAYER_LIB + String(clip))
	if animation_player.has_animation(prefixed):
		return prefixed
	return clip

func _physics_process(delta: float) -> void:
	if _body == null or _dead:
		return
	_speed = lerpf(_speed, _flat_speed(), 1.0 - exp(-delta * 6.0))   # smooth out jitter
	if _moving and _speed < RUN_EXIT:
		_moving = false
	elif not _moving and _speed > RUN_ENTER:
		_moving = true

	var retreating: bool = _ai != null and _ai.is_retreating

	if retreating and _moving:
		_backpedaling = true
		_play(_backpedal_clip())
	elif _backpedaling:
		# retreat just ended (or the enemy was blocked): go back to normal animation
		_backpedaling = false
		_play(move_anim if (_chasing and _moving) else idle_anim)
	elif _chasing:
		_play(move_anim if _moving else idle_anim)

func _backpedal_clip() -> StringName:
	if backpedal_anim != &"" and animation_player.has_animation(backpedal_anim):
		return backpedal_anim
	return move_anim

## Called once by the enemy right after the model is added.
func bind(ai: AIComponent, health: HealthComponent, body: CharacterBody3D) -> void:
	_body = body
	_ai = ai
	ai.skill_lock = is_skill_playing
	ai.state_changed.connect(_on_state_changed)
	health.died.connect(_on_died)
	_play(idle_anim)

func _on_state_changed(new_state: AIComponent.State) -> void:
	_chasing = new_state == AIComponent.State.CHASE
	if _chasing:
		_speed = _flat_speed()
		_moving = _speed > RUN_ENTER
		_play(move_anim if _moving else idle_anim)
	elif new_state == AIComponent.State.IDLE:
		_play(idle_anim)


func _on_died() -> void:
	_dead = true
	_chasing = false                          # stop the speed logic overriding the death clip
	_skill_busy_until = 0                     # death always wins over a skill clip
	if animation_player and animation_player.has_animation(death_anim):
		_play(death_anim)
		await animation_player.animation_finished
	else:
		await get_tree().process_frame
	death_finished.emit()

func _flat_speed() -> float:
	var v := _body.get_real_velocity()
	return Vector2(v.x, v.z).length()

func _play(anim_name: StringName) -> void:
	if animation_player == null or not animation_player.has_animation(anim_name):
		return
	if Time.get_ticks_msec() < _skill_busy_until:
		return                                # a skill clip is playing, don't cut it off
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name)

func is_skill_playing() -> bool:
	return Time.get_ticks_msec() < _skill_busy_until
	
