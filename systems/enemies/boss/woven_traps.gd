class_name WovenTraps
extends Node
## Boss trait: weaves traps across the floor in patterns (Null Weaver Prime: "weaves traps in
## patterns. Read the pattern and step through the gaps"). Put this node anywhere inside the
## enemy's MODEL scene, like Summoner.
##
## Every `interval` seconds once it has noticed a player, it lays a weave round that player:
##   1. TELEGRAPH  `strands` parallel strands across the floor, one of them missing (the gap),
##                 brightening for `telegraph` seconds
##   2. SNAP       every strand flashes; anyone standing on one is hurt. The gap, and anywhere
##                 off the weave, is safe
## Below `cross_below` of its life it weaves two at once, crossed: the safe spot is where the
## two gaps meet.

@export var interval: float = 7.0
@export var first_delay: float = 4.0
@export var telegraph: float = 1.5
@export var strands: int = 7
@export var strand_width: float = 2.0
@export var length: float = 26.0
## Damage as a multiple of its basic attack's maximum.
@export var damage_mult: float = 1.8
@export_range(0.0, 1.0, 0.05) var cross_below: float = 0.5

const COL := Color(0.72, 0.25, 1.0)
const COL_SNAP := Color(0.95, 0.85, 1.0)
const SNAP_TIME := 0.25

enum Phase { WAIT, TELEGRAPH, SNAP }

var _enemy: EnemyBase
var _phase := Phase.WAIT
var _timer := -1.0                             # < 0 = not started (hasn't noticed anyone)
var _weaves: Array = []                        # {origin: Vector3, along: Vector3, across: Vector3, gap: int}
var _strips: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D


func _ready() -> void:
	var n := get_parent()
	while n != null and not (n is EnemyBase):
		n = n.get_parent()
	_enemy = n as EnemyBase
	if _enemy == null:
		push_warning("WovenTraps: not inside an enemy, disabled")
		set_physics_process(false)
		return
	_enemy.health.died.connect(_clear)


func _physics_process(delta: float) -> void:
	if _enemy == null or _enemy.health.current_health <= 0.0:
		return
	match _phase:
		Phase.WAIT:
			if _timer < 0.0:
				if _enemy.ai.state != AIComponent.State.IDLE:
					_timer = first_delay
				return
			_timer -= delta
			if _timer <= 0.0:
				_weave()
		Phase.TELEGRAPH:
			_timer -= delta
			var k := 1.0 - clampf(_timer / telegraph, 0.0, 1.0)
			_set_alpha(0.08 + 0.45 * k + (0.12 * absf(sin(Time.get_ticks_msec() * 0.025)) if k > 0.7 else 0.0), COL)
			if _timer <= 0.0:
				_snap()
		Phase.SNAP:
			_timer -= delta
			if _timer <= 0.0:
				_clear()
				_phase = Phase.WAIT
				_timer = interval


func _weave() -> void:
	var player := _enemy.get_tree().get_first_node_in_group("players") as Node3D
	if player == null:
		_timer = interval
		return
	var centre := Vector3(player.global_position.x, _enemy.global_position.y + 0.06, player.global_position.z)
	var angle := randf() * TAU
	_weaves.clear()
	_add_weave(centre, angle)
	var max_hp := _enemy.stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	if max_hp > 0.0 and _enemy.health.current_health / max_hp < cross_below:
		_add_weave(centre, angle + PI * 0.5)
	_build_strips()
	_phase = Phase.TELEGRAPH
	_timer = telegraph


func _add_weave(centre: Vector3, angle: float) -> void:
	var along := Vector3(cos(angle), 0.0, sin(angle))
	var across := Vector3(-along.z, 0.0, along.x)
	# the gap is never the middle strand, so standing still is never safe
	var gap := randi() % (strands - 1)
	if gap >= strands / 2:
		gap += 1
	_weaves.append({"origin": centre, "along": along, "across": across, "gap": gap})


func _build_strips() -> void:
	_clear()
	var parent := _enemy.get_parent()
	if parent == null:
		return
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(COL, 0.08)
	for w in _weaves:
		for i in strands:
			if i == w["gap"]:
				continue
			var strip := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(strand_width * 0.9, 0.02, length)
			box.material = _mat
			strip.mesh = box
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(strip)
			var offset: float = (float(i) - float(strands - 1) * 0.5) * strand_width
			var at: Vector3 = w["origin"] + w["across"] * offset
			strip.global_position = at
			strip.look_at(at + w["along"], Vector3.UP)
			_strips.append(strip)


func _snap() -> void:
	_set_alpha(0.85, COL_SNAP)
	_phase = Phase.SNAP
	_timer = SNAP_TIME
	var dmg := _enemy.stats.get_stat(StatTypes.Stat.MAX_ATTACK_DAMAGE) * damage_mult
	for p in _enemy.get_tree().get_nodes_in_group("players"):
		var player := p as Node3D
		if player != null and _on_a_strand(player.global_position):
			var h = player.get("health")
			if h != null:
				h.take_damage(dmg)


## True when `pos` is on a strand of any weave (not in its gap, not off its ends or sides).
func _on_a_strand(pos: Vector3) -> bool:
	for w in _weaves:
		var d: Vector3 = pos - w["origin"]
		d.y = 0.0
		if absf(d.dot(w["along"])) > length * 0.5:
			continue
		var x: float = d.dot(w["across"]) / strand_width + float(strands) * 0.5
		if x < 0.0 or x >= float(strands):
			continue
		if int(floor(x)) != int(w["gap"]):
			return true
	return false


func _set_alpha(a: float, col: Color) -> void:
	if _mat != null:
		_mat.albedo_color = Color(col, a)


func _clear() -> void:
	for s in _strips:
		if is_instance_valid(s):
			s.queue_free()
	_strips.clear()
