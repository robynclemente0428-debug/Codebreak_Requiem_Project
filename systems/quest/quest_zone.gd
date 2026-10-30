class_name QuestZone
extends Area3D

@export var zone_id: String = "docks_gate"
@export var once: bool = true
var _fired := false

func _ready() -> void:
	body_entered.connect(func(b: Node3D) -> void:
		if b.is_in_group("player") and not (once and _fired):
			_fired = true
			GameEvents.report("enter_area", zone_id))
