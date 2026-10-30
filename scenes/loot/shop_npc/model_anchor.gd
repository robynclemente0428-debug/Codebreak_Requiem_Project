extends Node3D


@export var idle_animation: StringName = &"player_anims/Idle"
@onready var animation_player: AnimationPlayer = (
	find_child("AnimationPlayer", true, false) as AnimationPlayer
)
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if animation_player == null:
		push_error("NPC Model: AnimationPlayer was not found.")
		return
	
	
	if animation_player.has_animation(idle_animation):
		animation_player.play(idle_animation)
		print("Playing animation: ", idle_animation)
	else:
		push_error(
			"NPC Model: Animation not found: " + str(idle_animation)
		)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
