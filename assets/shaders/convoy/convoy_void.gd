class_name ConvoyVoid
extends MeshInstance3D
## The scrolling void under the convoy barge. Put this on a big PlaneMesh below and around the
## ship with convoy_void.gdshader as its material. The ship stays still; the void moves.
##
##   speed       how fast the barge travels (tween it for docking or leaving)
##   warp(on)    stretches the stars into streaks and speeds up, for jumps between nodes

@export var speed := 0.05            # UV units per second
@export var cruise_speed := 0.05
@export var warp_speed := 0.9
@export var warp_time := 0.8         # seconds to spin up or down

var _travel := 0.0
var _stretch := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	_mat = (material_override if material_override != null else get_active_material(0)) as ShaderMaterial
	if _mat == null:
		push_warning("ConvoyVoid: give the mesh a ShaderMaterial using convoy_void.gdshader")


func _process(delta: float) -> void:
	if _mat == null:
		return
	_travel += speed * delta
	_mat.set_shader_parameter("travel", _travel)
	_mat.set_shader_parameter("stretch", _stretch)


## Jump on / off: speeds up and streaks the stars, or settles back to cruising.
func warp(on: bool) -> void:
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "speed", warp_speed if on else cruise_speed, warp_time)
	t.tween_property(self, "_stretch", 1.0 if on else 0.0, warp_time)


## Docked: slow to a stop (or back to cruising when `docked` is false).
func dock(docked: bool) -> void:
	create_tween().set_trans(Tween.TRANS_SINE).tween_property(self, "speed",
		0.0 if docked else cruise_speed, warp_time * 2.0)
