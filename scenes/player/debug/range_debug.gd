class_name RangeDebug
extends Node3D
## In-game range overlay. Draws the character's body radius (white) and melee reach (red)
## on the ground, and prints the numbers on screen. Add it as a child of the Player.
## Press F3 to hide or show it.

@export var toggle_key: Key = KEY_F3
@export var start_visible := true
@export var ring_height := 0.05          # meters above the player's feet, avoids z-fighting with the floor
@export var ring_thickness := 0.05
@export var segments := 64

var _player: Node3D
var _stats: StatComponent
var _skills: SkillComponent
var _reach_ring := MeshInstance3D.new()
var _body_ring := MeshInstance3D.new()
var _layer := CanvasLayer.new()
var _label := Label.new()
var _last_reach := -1.0
var _last_body := -1.0


func _ready() -> void:
	_player = get_parent() as Node3D
	if _player == null:
		push_error('RangeDebug must be a child of the Player node')
		return

	for c in _player.get_children():
		if c is StatComponent:
			_stats = c
		elif c is SkillComponent:
			_skills = c

	top_level = true                     # don't inherit the player's rotation, we follow its position
	_reach_ring.material_override = _make_material(Color(1.0, 0.25, 0.25, 0.9))
	_body_ring.material_override = _make_material(Color(1.0, 1.0, 1.0, 0.8))
	add_child(_reach_ring)
	add_child(_body_ring)

	_label.add_theme_color_override('font_outline_color', Color.BLACK)
	_label.add_theme_constant_override('outline_size', 6)
	# In co-op, stack one label per player so they don't overlap.
	var seat = _player.get('player_index')
	_label.position = Vector2(16, 16 + 90 * (int(seat) if seat != null else 0))
	_layer.add_child(_label)
	add_child(_layer)

	_set_shown(start_visible)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == toggle_key:
		_set_shown(not visible)


func _set_shown(shown: bool) -> void:
	visible = shown
	_layer.visible = shown


func _process(_delta: float) -> void:
	if not visible or _player == null:
		return
	global_position = _player.global_position + Vector3(0.0, ring_height, 0.0)

	var reach := _current_reach()
	if not is_equal_approx(reach, _last_reach):
		_last_reach = reach
		_reach_ring.mesh = _ring(reach)

	var body := _body_radius()
	if not is_equal_approx(body, _last_body):
		_last_body = body
		_body_ring.mesh = _ring(body)

	_label.text = _describe(reach, body)


## The reach of the skill that is actually used (the first equipped one), the same value
## StrikeBehavior hands to resolve_hits.
func _current_reach() -> float:
	if _stats == null:
		return 0.0
	if _skills != null and not _skills.equipped_skills.is_empty():
		return _skills.equipped_skills[0].get_melee_range(_stats)
	return _stats.get_stat(StatTypes.Stat.ATTACK_RANGE)


func _body_radius() -> float:
	var col := _player.find_child('CollisionShape3D', true, false) as CollisionShape3D
	if col == null or col.shape == null:
		return 0.0
	var r = col.shape.get('radius')       # cylinder, capsule and sphere shapes have one
	return float(r) if r != null else 0.0


func _describe(reach: float, body: float) -> String:
	var stat_range := 0.0
	if _stats != null:
		stat_range = _stats.get_stat(StatTypes.Stat.ATTACK_RANGE)
	var bonus := 0.0
	if _skills != null and not _skills.equipped_skills.is_empty():
		bonus = _skills.equipped_skills[0].get_flag('range_bonus')
	return 'Reach %.2f m (red)\n  ATTACK_RANGE stat %.2f\n  skill bonus %+.2f\nBody radius %.2f m (white)' \
		% [reach, stat_range, bonus, body]


func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true               # visible even where the floor would hide it
	return m


## A flat ring of the given outer radius, lying on the ground.
func _ring(radius: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	if radius <= 0.0:
		return mesh
	var inner := maxf(radius - ring_thickness, 0.0)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segments + 1:
		var a := TAU * i / segments
		var dir := Vector3(cos(a), 0.0, sin(a))
		mesh.surface_add_vertex(dir * radius)
		mesh.surface_add_vertex(dir * inner)
	mesh.surface_end()
	return mesh
