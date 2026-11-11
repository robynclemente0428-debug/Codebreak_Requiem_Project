class_name RegistryMarkers
extends Node
## Shows which enemies are in the Registry (ScriptRegisters): a pulsing ring at a registered
## enemy's feet, with the hotkey of the skill whose registry holds it underneath ("LMB", or
## "LMB Q" when two skills registered it). Each skill's script keeps its own registry, so the key
## says which `target in registry` rules will see it.
##
## The player adds one as a child (player.gd). It reads the registries of the active script set
## REFRESH times a second; the registries are never changed here. An enemy leaves the ring when
## it leaves the set: removed, dead, or the fight is over (no hit landed or taken for
## ScriptRegisters.CLEAR_AFTER seconds, the same rule that clears the set on the next cast).
## At the feet, so it never covers the BREAKPOINT marker over the head.

const REFRESH := 10.0                      # checks a second
const NODE_NAME := &"RegistryMark"
const COLOR := Color(0.45, 0.82, 1.0)      # the editor's colour for knobs and the registry
const RING_RADIUS := 0.75                  # metres
const PULSE_SPEED := 4.0

static var _mesh: TorusMesh
static var _mat: StandardMaterial3D

var _skills: SkillComponent
var _health: HealthComponent
## Enemy instance id -> its marker (Node3D). A marker is the enemy's child, so it can be freed with
## the enemy (left the area, the exam cleared its wave...) while still listed here: always check
## is_instance_valid() before giving one a type, or Godot stops on the freed instance.
var _marked: Dictionary = {}
var _wait := 0.0
var _time := 0.0


func _ready() -> void:
	var owner_node := get_parent()
	_skills = owner_node.get("skills") as SkillComponent
	_health = owner_node.get("health") as HealthComponent
	_make_shared()


func _process(delta: float) -> void:
	_time += delta
	if _mat != null:                       # one shared material: every ring pulses together
		_mat.albedo_color.a = 0.55 + 0.35 * sin(_time * PULSE_SPEED)
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 1.0 / REFRESH
	_refresh()


## Enemy instance id -> the hotkeys of the skills whose registry holds it.
func registered() -> Dictionary:
	var out := {}
	if _skills == null:
		return out
	for i in _skills.sockets.size():
		var program := _skills.get_program(i)
		if program == null or program.registers.is_empty() or _stale(program):
			continue
		var key := _key_of(i)
		for id in program.registers:
			var keys: Array = out.get(id, [])
			if not key in keys:
				keys.append(key)
			out[id] = keys
	return out


## The fight is over for this program: its registry will be cleared on the next cast
## (ProgramSupport._clear_stale_registers), so it already counts as empty here.
func _stale(program: SkillProgram) -> bool:
	var active := program.last_active_msec
	if _health != null:
		active = maxi(active, _health.last_damaged_msec)
	return active >= 0 and Time.get_ticks_msec() - active > int(ScriptRegisters.CLEAR_AFTER * 1000.0)


func _key_of(socket: int) -> String:
	var action := _skills.action_of(socket)
	return GemText.key_label(action) if action != &"" else "-"


func _refresh() -> void:
	var now := registered()
	for id in _marked.keys():
		if not now.has(id):
			var gone: Variant = _marked[id]           # untyped: it may already be freed
			if is_instance_valid(gone):
				(gone as Node).queue_free()
			_marked.erase(id)
	for id in now:
		var enemy := instance_from_id(id) as Node3D if id is int else null
		if enemy == null or not enemy.is_inside_tree() or SkillBehavior.is_dead(enemy):
			continue
		var held: Variant = _marked.get(id)            # untyped: freed with an earlier enemy?
		var m: Node3D = held as Node3D if is_instance_valid(held) else null
		if m == null:
			m = _make_marker(enemy)
			_marked[id] = m
		(m.get_node("Key") as Label3D).text = " ".join(now[id])


func _make_marker(enemy: Node3D) -> Node3D:
	var m := Node3D.new()
	m.name = NODE_NAME
	var ring := MeshInstance3D.new()
	ring.mesh = _mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.06                 # just above the floor so it doesn't flicker
	ring.scale = Vector3(RING_RADIUS, 1.0, RING_RADIUS)
	m.add_child(ring)
	var key := Label3D.new()
	key.name = "Key"
	key.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	key.no_depth_test = true
	key.fixed_size = true
	key.pixel_size = 0.0009
	key.font_size = 24
	key.outline_size = 8
	key.outline_modulate = Color(0, 0, 0, 0.9)
	key.modulate = COLOR
	key.position = Vector3(0.0, 0.1, 0.0)  # at the feet, drawn over the body (no depth test)
	m.add_child(key)
	enemy.add_child(m)
	return m


static func _make_shared() -> void:
	if _mesh != null:
		return
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(COLOR.r * 1.6, COLOR.g * 1.6, COLOR.b * 1.6, 0.8)   # past white: the glow picks it up
	_mesh = TorusMesh.new()                 # lies flat on the ground
	_mesh.inner_radius = 0.9
	_mesh.outer_radius = 1.0
	_mesh.rings = 32
	_mesh.ring_segments = 4
	_mesh.material = _mat


func _exit_tree() -> void:
	for id in _marked:
		var held: Variant = _marked[id]
		if is_instance_valid(held):
			(held as Node).queue_free()
	_marked.clear()
