class_name CoreEnding
extends Node
## The Core after the ending (Endings.current): it relights the hub, the moment the ending is
## chosen. Sits in act_5_core.tscn; everything it changes in
## the world (the sun, the environment's ambient light) is put back when the Core is left.
##   merge      the Null's violet everywhere: its glow lights up, the light turns violet
##   overwrite  the Architects' white and gold: the Null's glow goes out, warm light comes back
##   terminate  dark: the Null's glow and most of the light go out; only the Last Log's terminal
##              still glows
## Vesper's part (gone after MERGE) is DialogueNPC.hidden_by_ending, on her node in the Core.

const CHECK_EVERY := 0.5                    # seconds between looks at Endings.current
const COL_MERGE := Color(0.72, 0.35, 1.0)
const COL_PATCH := Color(1.0, 0.88, 0.62)
const COL_TERMINAL := Color(0.75, 0.9, 1.0)
## Where the Last Log's terminal stands in the Core (its node's position, a little up).
const TERMINAL_OFFSET := Vector3(0.0, 2.2, 0.0)

var shown := "-"                            # the ending the Core shows now ("" = none yet)
var _check := 0.0
var _orig := {}                             # what was changed, to put back
var _extra: Array[Node] = []                # lights added for the ending


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_EVERY
	var player := get_tree().get_first_node_in_group("players")
	var qm: QuestManager = player.get("quests") if player != null else null
	var id := Endings.current(qm)
	if id != shown:
		_apply(id)


func _exit_tree() -> void:
	_restore()


func _apply(id: String) -> void:
	_restore()
	shown = id
	if id == "":
		return
	var sun := _sun()
	var env := _env()
	_remember(sun, ["light_energy", "light_color"])
	_remember(env, ["ambient_light_energy", "ambient_light_color"])
	for glow in _glows():
		_remember(glow, ["light_energy", "omni_range"])
	match id:
		"merge":
			for glow in _glows():
				glow.light_energy = 6.0
				glow.omni_range = 24.0
			_light(Vector3(36, 5, 33), COL_MERGE, 4.0, 22.0)
			if sun != null:
				sun.light_color = sun.light_color.lerp(COL_MERGE, 0.45)
			if env != null:
				env.ambient_light_color = env.ambient_light_color.lerp(COL_MERGE, 0.5)
		"overwrite":
			for glow in _glows():
				glow.light_energy = 0.0
			_light(Vector3(32, 5, 30), COL_PATCH, 3.0, 20.0)
			_light(Vector3(42, 5, 35), COL_PATCH, 3.0, 20.0)
			if sun != null:
				sun.light_energy *= 1.2
				sun.light_color = sun.light_color.lerp(COL_PATCH, 0.35)
			if env != null:
				env.ambient_light_color = env.ambient_light_color.lerp(COL_PATCH, 0.4)
		"terminate":
			for glow in _glows():
				glow.light_energy = 0.0
			if sun != null:
				sun.light_energy *= 0.1
			if env != null:
				env.ambient_light_energy *= 0.15
			var log := get_parent().get_node_or_null("LastLog") as Node3D
			if log != null:
				_light(log.position + TERMINAL_OFFSET, COL_TERMINAL, 2.5, 7.0)


## Puts back everything the last ending changed, and takes its lights away.
func _restore() -> void:
	for obj in _orig:
		if is_instance_valid(obj):
			for prop in _orig[obj]:
				obj.set(prop, _orig[obj][prop])
	_orig.clear()
	for n in _extra:
		if is_instance_valid(n):
			n.queue_free()
	_extra.clear()


func _remember(obj: Object, props: Array) -> void:
	if obj == null:
		return
	var saved: Dictionary = _orig.get(obj, {})
	for p in props:
		if not saved.has(p):
			saved[p] = obj.get(p)
	_orig[obj] = saved


func _light(at: Vector3, col: Color, energy: float, reach: float) -> void:
	var l := OmniLight3D.new()
	l.name = "EndingLight"
	l.light_color = col
	l.light_energy = energy
	l.omni_range = reach
	get_parent().add_child(l)
	l.position = at
	_extra.append(l)


func _glows() -> Array:
	var out: Array = []
	for n in ["NullGlowW", "NullGlowE"]:
		var g := get_parent().get_node_or_null(n) as OmniLight3D
		if g != null:
			out.append(g)
	return out


## The world's sun and environment (in main.tscn, around the area).
func _sun() -> DirectionalLight3D:
	return get_tree().root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D


func _env() -> Environment:
	var w := get_parent().get_viewport().find_world_3d() if get_parent() != null else null
	return w.environment if w != null else null
