class_name ConvoyBlackout
extends Node
## Dead in the void: when EVERY deck system (DeckSystem) on the convoy is offline, the convoy
## loses power. Put it in the convoy scene, as a child of the area. While it lasts:
##   the void stops flowing past (ConvoyMotion.stall), the engines sputter out and the wind
##   streaks stop (ConvoyDressing.set_powered), and the deck goes as dark as a dungeon
##   (AreaLighting at dungeon_light, so the players' own lights come on).
## Patching any one system back (PatchPanel -> DeckSystem.repair) restarts it.
## Offline is saved, so arriving on a dead convoy starts dark at once (no wind-down).

## How dark the deck goes, as a share of the normal light (Dungeon.DUNGEON_LIGHT is 0.08).
@export_range(0.0, 1.0, 0.01) var dungeon_light := 0.08
## Seconds to wind down when the last system falls (and to come back up).
@export var wind_down := 3.0
## How bright the stars stay while dead in the void (the backdrop's tint), 1 = unchanged.
@export_range(0.0, 1.0, 0.05) var dead_star_tint := 0.55
@export_multiline var down_text := "ALL SYSTEMS DOWN\nThe convoy is dead in the void. Patch any system to get the power back."
@export_multiline var up_text := "POWER RESTORED\nThe engines catch. The convoy is under way again."

const COL_DOWN := Color(1.0, 0.25, 0.2)
const COL_UP := Color(0.25, 0.95, 1.0)

var dead := false
var _systems: Array = []
var _light := 1.0               # 1 = the area's normal light .. dungeon_light (tweened)
var _base_light := 1.0
var _base_tint := Color.WHITE
var _tween: Tween


func _ready() -> void:
	add_to_group("convoy_blackout")
	_hook.call_deferred()


func _hook() -> void:
	var area := get_parent()
	_base_light = float(area.get("light_scale")) if area.get("light_scale") != null else 1.0
	var mat := area.get("backdrop") as ShaderMaterial
	if mat != null and mat.get_shader_parameter("tint") != null:
		_base_tint = mat.get_shader_parameter("tint")
	for s in get_tree().get_nodes_in_group(DeckSystem.GROUP):
		if not area.is_ancestor_of(s):
			continue
		_systems.append(s)
		s.went_offline.connect(_on_change.unbind(1))
		s.repaired.connect(_on_change.unbind(1))
	_update(false)


func _exit_tree() -> void:
	# The backdrop material is a shared resource: leave its tint as we found it
	_set_tint(1.0)


func _on_change() -> void:
	_update(true)


## True when every deck system here is down (and there is at least one).
func all_down() -> bool:
	if _systems.is_empty():
		return false
	var any := false
	for s in _systems:
		if not is_instance_valid(s) or not s.sabotage_target:
			continue                          # the IFF going down doesn't stall the convoy
		any = true
		if s.is_online():
			return false
	return any


func _update(animate: bool) -> void:
	var down := all_down()
	if down == dead:
		return
	dead = down
	var time := wind_down if animate else 0.0
	var area := get_parent()
	for c in area.get_children():
		if c is ConvoyMotion:
			c.stall(dead, time)
		elif c is ConvoyDressing:
			c.set_powered(not dead, time * 0.8)
	if _tween != null:
		_tween.kill()
	var target := dungeon_light if dead else 1.0
	if time <= 0.0:
		_set_light(target)
	else:
		_tween = create_tween().set_trans(Tween.TRANS_SINE)
		if dead:
			_tween.tween_interval(time * 0.4)        # the engines die first, then the lights
		_tween.tween_method(_set_light, _light, target, time * 0.6)
	if animate:
		QuestItems.toast(get_tree(), down_text if dead else up_text, COL_DOWN if dead else COL_UP)


## 1 = normal .. dungeon_light: the world light, the players' own lights and the stars.
func _set_light(v: float) -> void:
	_light = v
	var area := get_parent()
	if area.get("light_scale") != null:
		area.set("light_scale", _base_light * v)
	AreaLighting.apply(area, _base_light * v)
	var dim := inverse_lerp(1.0, dungeon_light, v) if dungeon_light < 1.0 else 0.0
	_set_tint(lerpf(1.0, dead_star_tint, clampf(dim, 0.0, 1.0)))


func _set_tint(f: float) -> void:
	var mat := get_parent().get("backdrop") as ShaderMaterial if get_parent() != null else null
	if mat != null:
		mat.set_shader_parameter("tint", Color(_base_tint.r * f, _base_tint.g * f, _base_tint.b * f, _base_tint.a))
