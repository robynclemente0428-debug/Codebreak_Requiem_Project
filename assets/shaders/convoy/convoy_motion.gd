class_name ConvoyMotion
extends Node
## Makes a town look like it's travelling through space: the camp stands still and the void
## behind it (the area's backdrop, convoy_void.gdshader in screen_space mode) flows past.
## Put it in the convoy town scene. Same controls as ConvoyVoid, for a backdrop instead of a plane:
##   speed       how fast the void flows (tween it for docking or leaving)
##   warp(on)    stretches the stars into streaks and speeds up, for jumps between nodes
##   dock(on)    slows to a stop, or back to cruising
## Arriving plays a short drop out of warp.
##
## `heading` is the way the bow points, in the town's own space. The void flows the other way
## on screen, worked out from the camera, so it always runs along the ship.

@export var heading := Vector3(1.0, 0.0, 0.0)
@export var cruise_speed := 0.06     # screen heights per second, near layer
@export var warp_speed := 1.2
@export var warp_time := 0.8         # seconds to spin up or down
@export var arrive_from_warp := true

var speed := 0.0
var _travel := 0.0
var _stretch := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	var area := get_parent()
	_mat = area.get("backdrop") as ShaderMaterial
	if _mat == null:
		push_warning("ConvoyMotion: the area's backdrop should be a ShaderMaterial using convoy_void.gdshader")
		return
	if _mat.get_shader_parameter("far_tex") == null:
		_mat.set_shader_parameter("far_tex", ConvoyStars.far())
	if _mat.get_shader_parameter("near_tex") == null:
		_mat.set_shader_parameter("near_tex", ConvoyStars.near())
	speed = cruise_speed
	if arrive_from_warp:
		speed = warp_speed
		_stretch = 1.0
		var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
		t.tween_property(self, "speed", cruise_speed, warp_time * 2.0).set_delay(0.4)
		t.tween_property(self, "_stretch", 0.0, warp_time * 2.0).set_delay(0.4)


func _process(delta: float) -> void:
	if _mat == null:
		return
	_travel += speed * delta
	_mat.set_shader_parameter("travel", _travel)
	_mat.set_shader_parameter("stretch", _stretch)
	var flow := -screen_heading()
	if flow != Vector2.ZERO:
		_mat.set_shader_parameter("direction", flow)


## The bow's direction on screen (y down), or ZERO without a camera.
func screen_heading() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	var area := get_parent() as Node3D
	if cam == null or area == null:
		return Vector2.ZERO
	var h := area.global_basis * heading
	var v := Vector2(h.dot(cam.global_basis.x), -h.dot(cam.global_basis.y))
	return v.normalized() if v.length() > 0.01 else Vector2.ZERO


## Jump on / off: speeds up and streaks the stars, or settles back to cruising.
func warp(on: bool) -> void:
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "speed", warp_speed if on else cruise_speed, warp_time)
	t.tween_property(self, "_stretch", 1.0 if on else 0.0, warp_time)


## Docked: slow to a stop (or back to cruising when `docked` is false).
func dock(docked: bool) -> void:
	create_tween().set_trans(Tween.TRANS_SINE).tween_property(self, "speed",
		0.0 if docked else cruise_speed, warp_time * 2.0)
