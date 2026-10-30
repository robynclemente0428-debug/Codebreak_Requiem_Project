class_name Scepter
extends Node3D
## One-handed casting scepter. The model's origin is the centre of the grip, +Y runs
## along the shaft toward the orb. Swap orbs at runtime with equip_orb().

signal orb_changed(orb: Node3D)

## Orb scene to mount on _ready (e.g. orb.tscn / orb02.tscn). Optional.
@export var default_orb: PackedScene
## Your orb scenes are ~0.5 m wide (root scale 0.5 on a 1 m sphere). The cradle is sized
## for a 0.14 m orb, so the socket scales the orb by this factor.
@export var orb_scale := 0.28

@onready var orb_socket: Marker3D = $OrbSocket

var current_orb: Node3D

func _ready() -> void:
	orb_socket.scale = Vector3.ONE * orb_scale
	if default_orb:
		equip_orb(default_orb)

func equip_orb(scene: PackedScene) -> Node3D:
	unequip_orb()
	current_orb = scene.instantiate() as Node3D
	orb_socket.add_child(current_orb)
	orb_changed.emit(current_orb)
	return current_orb

func unequip_orb() -> void:
	if current_orb:
		current_orb.queue_free()
		current_orb = null
		orb_changed.emit(null)

## Colours + material of the mounted orb, for skill effects. Same result as
## SkillStyle.from_held([scepter]): the scepter's own meshes use plain materials and are skipped,
## so the orb's ShaderMaterial is the one that gets read.
func get_effect_style() -> Dictionary:
	return SkillStyle.from_held([self])

## World-space point projectiles should spawn from (the orb centre).
func get_cast_position() -> Vector3:
	return orb_socket.global_position
