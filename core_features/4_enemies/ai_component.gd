class_name AIComponent
extends Node

enum State { IDLE, CHASE, ATTACK }

signal attack_requested(target: Node3D)
signal state_changed(new_state: State)

@export var aggro_range: float = 15.0
@export var attack_range: float = 2.0
@export var eye_height: float = 1.0
@export var lose_target_time: float = 3.0
@export_flags_3d_physics var wall_mask: int = 1
@export var turn_speed: float = 8.0
@export var slot_radius_factor: float = 0.8
@export var separation_radius: float = 1.1
@export var stop_distance: float = 1.2 
@export var basic_attack_enabled: bool = true
@export var debug_stuck := false
@export var preferred_distance: float = 0.0
@export var flee_distance: float = 0.0
@export var kite_delay_min: float = 0.5
@export var kite_delay_max: float = 1.0
var skill_lock: Callable = Callable()
var _kite_timer := -1.0
var is_retreating := false
var _attack_cooldown := 0.0
var busy_time := 0.0

var _stuck_time := 0.0
var _desired := Vector3.ZERO
var _slot_angle: float = 0.0
var _stalled_time := 0.0
var _hold_time := 0.0

const SCAN_INTERVAL := 0.25

static var _crowd_frame := -1
static var _crowd: PackedVector3Array = []
var _sep_frame := -1
var _sep := Vector3.ZERO

var state: State = State.IDLE:
	set(value):
		if value == state:
			return
		state = value
		state_changed.emit(value)
var target: Node3D = null
var objective: Node3D = null

var _body: CharacterBody3D
var _stats: StatComponent
var _nav: NavigationAgent3D
var _scan_timer: float = 0.0
var _time_since_seen: float = 0.0

func setup(body: CharacterBody3D, stats: StatComponent, nav: NavigationAgent3D) -> void:
	_body = body
	_stats = stats
	_nav = nav
	_scan_timer = randf() * SCAN_INTERVAL
	_slot_angle = randf() * TAU
	_body.add_to_group("enemies")
	_nav.velocity_computed.connect(_on_velocity_computed)

func _physics_process(delta: float) -> void:
	if _body == null:
		return
	
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	busy_time = maxf(busy_time - delta, 0.0)
	
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_update_target()
		if target != null:
			_nav.target_position = target.global_position + _slot_offset()

	var speed := _stats.get_stat(StatTypes.Stat.MOVE_SPEED)
	var move_dir := Vector3.ZERO

	if target == null:
		state = State.IDLE
	else:
		var dist := _body.global_position.distance_to(target.global_position)
		var range_limit := attack_range * (1.25 if state == State.ATTACK else 1.0)
		state = State.ATTACK if dist <= range_limit else State.CHASE

	match state:
		State.CHASE:
			if _hold_time > 0.0:
				_hold_time -= delta
				move_dir = _separation() * 0.15
				_face_direction(target.global_position - _body.global_position, delta)
			else:
				var to_next: Vector3
				if _nav.is_navigation_finished():
					to_next = target.global_position - _body.global_position
				else:
					to_next = _nav.get_next_path_position() - _body.global_position
				to_next.y = 0.0
				move_dir = _steer(to_next.normalized(), 1.2)

				var real := _body.get_real_velocity()
				real.y = 0.0
				if real.length() > 1.0:
					_face_direction(real, delta)
				else:
					_face_direction(target.global_position - _body.global_position, delta)

				if real.length() < 0.5:
					_stalled_time += delta
					if _stalled_time > 0.5:
						_stalled_time = 0.0
						_hold_time = 0.7
				else:
					_stalled_time = 0.0
		State.ATTACK:
			var to_target := target.global_position - _body.global_position
			_face_direction(to_target, delta)
			to_target.y = 0.0
			
			if not basic_attack_enabled and to_target.length() > stop_distance:
				move_dir = (to_target.normalized() + _separation() * 1.2).normalized()
			
			var off := absf(angle_difference(_body.global_rotation.y, atan2(to_target.x, to_target.z)))
			if basic_attack_enabled and off < deg_to_rad(20.0) and _attack_cooldown <= 0.0 and not _is_busy():
				_attack_cooldown = 1.0 / maxf(_stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 0.1)
				attack_requested.emit(target)

	if preferred_distance > 0.0 and target != null:
		var away := _body.global_position - target.global_position
		away.y = 0.0
		var d := away.length()
		_face_direction(-away, delta)

		if is_retreating:
			if d >= preferred_distance:
				is_retreating = false
			else:
				move_dir = (away.normalized() + _separation()).normalized()
		elif d < flee_distance:
			if _kite_timer < 0.0:
				_kite_timer = randf_range(kite_delay_min, kite_delay_max)
			if not _is_busy():
				_kite_timer -= delta
			if _kite_timer <= 0.0:
				is_retreating = true
				_kite_timer = -1.0
			move_dir = _separation() * 0.15
		else:
			_kite_timer = -1.0
			if d > preferred_distance * 1.2:
				var to_next := -away
				if not _nav.is_navigation_finished():
					to_next = _nav.get_next_path_position() - _body.global_position
					to_next.y = 0.0
				move_dir = (to_next.normalized() + _separation()).normalized()
			else:
				move_dir = _separation() * 0.15
	else:
		_kite_timer = -1.0
		is_retreating = false
	if _is_busy():
		move_dir = Vector3.ZERO
	var desired := move_dir * speed
	if debug_stuck:
		_debug_stuck(delta, desired)
	_desired = desired
	if _is_busy():
		_apply_velocity(Vector3.ZERO, delta)
	elif _nav.avoidance_enabled:
		_nav.max_speed = speed
		_nav.velocity = desired
	else:
		_apply_velocity(desired, delta)
	

func halt() -> void:
	set_physics_process(false)
	target = null
	if _nav != null:
		if _nav.velocity_computed.is_connected(_on_velocity_computed):
			_nav.velocity_computed.disconnect(_on_velocity_computed)
		_nav.avoidance_enabled = false
		_nav.velocity = Vector3.ZERO


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if not is_physics_processing():
		return
	_apply_velocity(safe_velocity, get_physics_process_delta_time())
	
func _apply_velocity(v: Vector3, delta: float) -> void:
	_body.velocity.x = v.x
	_body.velocity.z = v.z
	if not _body.is_on_floor():
		_body.velocity.y -= 20.0 * delta
	_body.move_and_slide()

func _debug_stuck(delta: float, desired: Vector3) -> void:
	if state == State.CHASE and _body.get_real_velocity().length() < 0.5:
		_stuck_time += delta
		if _stuck_time > 1.0 and fmod(_stuck_time, 1.0) < delta:
			print("STUCK %s dist=%.1f want=%.1f finished=%s reachable=%s path=%d" % [
				_body.name, _body.global_position.distance_to(target.global_position),
				desired.length(), _nav.is_navigation_finished(),
				_nav.is_target_reachable(), _nav.get_current_navigation_path().size()])
	else:
		_stuck_time = 0.0

func _slot_offset() -> Vector3:
	return Vector3(sin(_slot_angle), 0.0, cos(_slot_angle)) * attack_range * slot_radius_factor

func _update_target() -> void:
	var best := _find_nearest_visible_player()
	if best == null and objective != null:
		if is_instance_valid(objective) and objective.is_inside_tree():
			target = objective
			_time_since_seen = 0.0
			return
		objective = null
	if best != null:
		target = best
		_time_since_seen = 0.0
	elif target != null:
		_time_since_seen += SCAN_INTERVAL
		if _time_since_seen > lose_target_time or not is_instance_valid(target):
			target = null

func _find_nearest_visible_player() -> Node3D:
	var range_sq := aggro_range * aggro_range
	var best: Node3D = null
	var best_sq := INF
	for p in get_tree().get_nodes_in_group("players"):
		var d_sq := _body.global_position.distance_squared_to(p.global_position)
		if d_sq > range_sq or d_sq >= best_sq:
			continue
		if not _has_line_of_sight(p):
			continue
		best = p
		best_sq = d_sq
	return best

func _has_line_of_sight(p: Node3D) -> bool:
	var from := _body.global_position + Vector3.UP * eye_height
	var to := p.global_position + Vector3.UP * eye_height
	var query := PhysicsRayQueryParameters3D.create(from, to, wall_mask)
	query.exclude = [_body.get_rid()]
	return _body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _separation() -> Vector3:
	var frame := Engine.get_physics_frames()
	if _sep_frame == frame:
		return _sep
	_sep_frame = frame
	if _crowd_frame != frame:
		_crowd_frame = frame
		_crowd.clear()
		for e in get_tree().get_nodes_in_group("enemies"):
			_crowd.append((e as Node3D).global_position)
	var here := _body.global_position
	var r_sq := separation_radius * separation_radius
	var push := Vector3.ZERO
	for pos in _crowd:
		var offset := Vector3(here.x - pos.x, 0.0, here.z - pos.z)
		var d_sq := offset.length_squared()
		if d_sq < r_sq and d_sq > 0.000001:
			var d := sqrt(d_sq)
			push += offset / d * (1.0 - d / separation_radius)
	_sep = push.limit_length(1.0)
	return _sep

func _steer(dir: Vector3, crowd: float) -> Vector3:
	var push := _separation() * crowd
	if not _body.is_on_wall():
		return (dir + push).normalized()
	var n := _body.get_wall_normal()
	n.y = 0.0
	n = n.normalized()
	var want := dir + push * 0.35
	var into := want.dot(n)
	if into < 0.0:
		want -= n * into
	return want.normalized() if want.length_squared() > 0.0001 else dir


func _face_direction(dir: Vector3, delta: float) -> void:
	if _is_busy():
		return
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	var target_y := atan2(dir.x, dir.z)
	_body.global_rotation.y = lerp_angle(
		_body.global_rotation.y, target_y, 1.0 - pow(0.001, delta * turn_speed))

func _is_busy() -> bool:
	return busy_time > 0.0 or (skill_lock.is_valid() and skill_lock.call())
