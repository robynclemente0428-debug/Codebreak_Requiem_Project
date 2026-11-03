class_name LoopCharger
extends Node
## Boss trait: charges round the same loop again and again. Used by the Loop Hound Alpha
## ("charges along the same path again and again. Learn the loop, break it"), but works on any
## enemy: put this node anywhere inside the enemy's MODEL scene, like Summoner.
##
## When the boss first notices a player it lays out its loop: `points` corners on a circle
## round where it stands, the same every time. The loop is marked on the floor, faintly.
##   1. TELEGRAPH  the boss stops, the loop lights up red
##   2. CHARGE     it runs the whole loop at charge_speed, hurting anyone it runs into (once
##                 per charge)
##   3. DAZED      it stands still for a moment at the end: the opening
## Then back to fighting normally until the next charge.
##
## Breaking the loop: hit it for break_damage (a fraction of its maximum health) while it
## charges and it stumbles out of the loop, dazed for longer.

@export var interval: float = 7.0              # seconds of normal fighting between charges
@export var first_delay: float = 2.5           # after the boss first notices a player
@export var points: int = 4                    # corners of the loop
@export var loop_radius: float = 6.0           # metres from where it stood
@export var charge_speed: float = 13.0
@export var laps: int = 1
@export var telegraph: float = 1.0
@export var dazed: float = 1.5
@export var broken_dazed: float = 3.5
## Damage while charging that breaks the loop, as a fraction of its maximum health.
@export_range(0.0, 1.0, 0.01) var break_damage: float = 0.08
## Charge damage as a multiple of its basic attack's maximum.
@export var damage_mult: float = 1.5
@export var hit_radius: float = 0.9          # metres past the edge of its body

const COL := Color(1.0, 0.15, 0.2)

enum Phase { WAIT, TELEGRAPH, CHARGE, DAZED }

var _enemy: EnemyBase
var _phase := Phase.WAIT
var _timer := -1.0                             # < 0 = not started (hasn't noticed anyone)
var _loop: Array[Vector3] = []
var _next := 0                                 # corner it runs to next
var _corners_left := 0
var _hit_this_charge: Dictionary = {}          # player -> true
var _taken := 0.0                              # damage taken during this charge
var _last_hp := 0.0
var _stalled := 0.0
var _marks: Array[MeshInstance3D] = []
var _mark_mat: StandardMaterial3D


func _ready() -> void:
	var n := get_parent()
	while n != null and not (n is EnemyBase):
		n = n.get_parent()
	_enemy = n as EnemyBase
	if _enemy == null:
		push_warning("LoopCharger: not inside an enemy, disabled")
		set_physics_process(false)
		return
	_enemy.health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if _enemy == null or _enemy.health.current_health <= 0.0:
		return
	match _phase:
		Phase.WAIT:
			if _timer < 0.0:
				if _enemy.ai.state != AIComponent.State.IDLE:
					_lay_out_loop()
					_timer = first_delay
				return
			_timer -= delta
			if _timer <= 0.0 and not _enemy.ai.busy_time > 0.0:
				_start_telegraph()
		Phase.TELEGRAPH:
			_timer -= delta
			_set_marks(0.35 + 0.55 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)))
			if _timer <= 0.0:
				_start_charge()
		Phase.CHARGE:
			_charge(delta)
		Phase.DAZED:
			_timer -= delta
			if _timer <= 0.0:
				_end_daze()


# ---------- THE LOOP ----------
func _lay_out_loop() -> void:
	var center := _enemy.global_position
	var start := randf() * TAU
	_loop.clear()
	for i in points:
		var a := start + TAU * float(i) / float(points)
		_loop.append(_on_navmesh(center + Vector3(cos(a), 0.0, sin(a)) * loop_radius))
	_build_marks()


## The loop on the floor: a thin red strip per side, faint until it's about to charge.
func _build_marks() -> void:
	var parent := _enemy.get_parent()
	if parent == null:
		return
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_mat.albedo_color = Color(COL, 0.12)
	for i in _loop.size():
		var a := _loop[i]
		var b := _loop[(i + 1) % _loop.size()]
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.35, 0.02, length)
		box.material = _mark_mat
		strip.mesh = box
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(strip)
		var mid := (a + b) * 0.5
		strip.global_position = Vector3(mid.x, maxf(a.y, b.y) + 0.06, mid.z)
		strip.look_at(Vector3(b.x, strip.global_position.y, b.z), Vector3.UP)
		_marks.append(strip)


func _set_marks(alpha: float) -> void:
	if _mark_mat != null:
		_mark_mat.albedo_color = Color(COL, alpha)


# ---------- PHASES ----------
func _start_telegraph() -> void:
	_phase = Phase.TELEGRAPH
	_timer = telegraph
	_pause_ai(true)
	# Starts from the corner nearest to it, so the loop is always run the same way round
	var best := 0
	for i in _loop.size():
		if _loop[i].distance_to(_enemy.global_position) < _loop[best].distance_to(_enemy.global_position):
			best = i
	_next = best
	_pop("LOOP", COL)


func _start_charge() -> void:
	_phase = Phase.CHARGE
	_corners_left = _loop.size() * laps + 1          # to the first corner, then round
	_hit_this_charge.clear()
	_taken = 0.0
	_last_hp = _enemy.health.current_health
	_stalled = 0.0
	_set_marks(0.7)
	_pass_through_players(true)                      # it runs through you, not round you
	if _enemy.model and _enemy.model.animation_player:
		_enemy.model.animation_player.speed_scale = 1.8


func _charge(delta: float) -> void:
	# Damage taken while charging: enough of it breaks the loop
	var hp := _enemy.health.current_health
	if hp < _last_hp:
		_taken += _last_hp - hp
	_last_hp = hp
	if _taken >= _enemy.stats.get_stat(StatTypes.Stat.MAX_HEALTH) * break_damage:
		_pop("LOOP BROKEN", Color(0.3, 1.0, 0.6))
		_start_daze(broken_dazed)
		return

	var body := _enemy as CharacterBody3D
	var goal := _loop[_next]
	var to := Vector3(goal.x - body.global_position.x, 0.0, goal.z - body.global_position.z)
	if to.length() < 0.6:
		_corners_left -= 1
		if _corners_left <= 0:
			_start_daze(dazed)
			return
		_next = (_next + 1) % _loop.size()
		return
	var dir := to.normalized()
	body.velocity = Vector3(dir.x * charge_speed, body.velocity.y - 20.0 * delta, dir.z * charge_speed)
	if body.is_on_floor():
		body.velocity.y = 0.0
	body.move_and_slide()
	body.global_rotation.y = atan2(dir.x, dir.z)       # +Z is forward
	# Pinned against something: skip to the next corner instead of grinding
	if body.get_real_velocity().length() < charge_speed * 0.2:
		_stalled += delta
		if _stalled > 0.4:
			_stalled = 0.0
			_next = (_next + 1) % _loop.size()
			_corners_left -= 1
	else:
		_stalled = 0.0
	_hit_players()


func _hit_players() -> void:
	var dmg := _enemy.stats.get_stat(StatTypes.Stat.MAX_ATTACK_DAMAGE) * damage_mult
	for p in _enemy.get_tree().get_nodes_in_group("players"):
		var player := p as Node3D
		if player == null or _hit_this_charge.has(player):
			continue
		var d := player.global_position - _enemy.global_position
		if Vector2(d.x, d.z).length() <= hit_radius + _body_radius():
			_hit_this_charge[player] = true
			var h = player.get("health")
			if h != null:
				h.take_damage(dmg)


func _start_daze(time: float) -> void:
	_phase = Phase.DAZED
	_timer = time
	_set_marks(0.12)
	_pass_through_players(false)
	var body := _enemy as CharacterBody3D
	body.velocity = Vector3.ZERO
	if _enemy.model and _enemy.model.animation_player:
		_enemy.model.animation_player.speed_scale = 1.0
		_enemy.model.animation_player.play(_enemy.model.idle_anim)


func _end_daze() -> void:
	_phase = Phase.WAIT
	_timer = interval
	_pause_ai(false)


## The AI stops steering while the loop runs (this moves the body instead), and picks up again
## after.
func _pause_ai(on: bool) -> void:
	_enemy.ai.set_physics_process(not on)
	_enemy.velocity = Vector3.ZERO
	if _enemy.nav != null:
		_enemy.nav.velocity = Vector3.ZERO


func _pass_through_players(on: bool) -> void:
	for p in _enemy.get_tree().get_nodes_in_group("players"):
		if p is PhysicsBody3D:
			if on:
				_enemy.add_collision_exception_with(p)
			else:
				_enemy.remove_collision_exception_with(p)


func _body_radius() -> float:
	var shape := _enemy.collision.shape as CylinderShape3D
	return shape.radius if shape else 0.5


func _on_died() -> void:
	set_physics_process(false)
	for m in _marks:
		if is_instance_valid(m):
			m.queue_free()
	_marks.clear()


func _pop(text: String, col: Color) -> void:
	var numbers := _enemy.get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers:
		numbers.pop_text(_enemy.global_position + Vector3.UP * 2.0, text, col, 1.3)


## Pulls a point onto the navmesh so the loop never runs through a wall.
func _on_navmesh(pos: Vector3) -> Vector3:
	var map := _enemy.nav.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return pos
	var p := NavigationServer3D.map_get_closest_point(map, pos)
	return p if p != Vector3.ZERO else pos
