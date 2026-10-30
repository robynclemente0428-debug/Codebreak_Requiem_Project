class_name Interactable
extends Area3D

@export var prompt_text: String = "TALK"
@export var prompt_height: float = 2.4

@export_group("Facing")
## Turn to face the player while they talk, trade or hand in quests, then turn back.
@export var face_player: bool = true
## How quickly the model turns (higher = snappier).
@export var turn_speed: float = 7.0
## Degrees to add if this NPC's model was made facing another way than +Z (its front ends up
## pointing beside the player instead of at them).
@export var model_forward_offset_deg: float = 0.0

@export_group("Info card")
## Shown when the player clicks this NPC (NpcInfoPanel). Leave empty for just name and services.
@export var info_title: String = ""                 # e.g. "Warden of Hardfault"
@export_multiline var info_description: String = ""

## The node that turns: ModelAnchor when the NPC has one (so its collision and prompt stay put).
var _turner: Node3D
var _rest_yaw := 0.0              # global yaw it stood at before anyone talked to it
var _engaged: Node3D              # the player it is facing
var _keep_distance := 0.0         # keeps facing them while they're closer than this


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_turner = get_node_or_null("ModelAnchor") as Node3D
	if _turner == null:
		_turner = self
	_rest_yaw = _turner.global_rotation.y
	set_process(false)


## The player started talking, trading or handing in a quest: turn to face them.
## DialoguePanel.open_dialogue, ShopPanel.open_shop and QuestGiverNPC.interact call this.
## Keeps facing them through the conversation (they may stand a little further off when it was
## opened from the NPC card) and turns back once they walk away.
func engage(player: Node3D) -> void:
	if not face_player or player == null:
		return
	_engaged = player
	_keep_distance = maxf(_flat_distance(player) + 1.5, 4.0)
	set_process(true)


func _process(delta: float) -> void:
	var target_yaw := _rest_yaw
	if _engaged != null and is_instance_valid(_engaged):
		if _flat_distance(_engaged) <= _keep_distance:
			var to := _engaged.global_position - _turner.global_position
			if Vector2(to.x, to.z).length() > 0.05:
				target_yaw = atan2(to.x, to.z) + deg_to_rad(model_forward_offset_deg)
		else:
			_engaged = null                       # walked off: turn back
	else:
		_engaged = null
	var yaw := _turner.global_rotation.y
	var new_yaw := lerp_angle(yaw, target_yaw, 1.0 - exp(-turn_speed * delta))
	_turner.global_rotation.y = new_yaw
	if _engaged == null and absf(angle_difference(new_yaw, _rest_yaw)) < 0.01:
		_turner.global_rotation.y = _rest_yaw
		set_process(false)                        # back at rest: stop ticking


func _flat_distance(n: Node3D) -> float:
	var d := n.global_position - global_position
	return Vector2(d.x, d.z).length()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("players") and body.has_method("set_interactable"):
		body.set_interactable(self)
		get_tree().call_group("interact_prompt", "show_prompt", self)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("players") and body.has_method("clear_interactable"):
		body.clear_interactable(self)
		get_tree().call_group("interact_prompt", "hide_prompt", self)

## Override in subclasses (shop, dialogue, stash...).
func interact(_player: Node3D) -> void:
	pass

## The key currently bound to "interact", as text (e.g. "T"). Used by prompts and hints.
static func key_name() -> String:
	for ev in InputMap.action_get_events("interact"):
		if ev is InputEventKey:
			if ev.keycode != KEY_NONE:
				return ev.as_text_keycode()
			return ev.as_text_physical_keycode()
	return "E"
