class_name LootChest
extends LootProp
## A chest the player opens with the interact key ([T] OPEN): the lid swings up (the model's
## "Open" animation) and it pays out more than any barrel, with one rare item guaranteed.
## Skills can't break it, and it stays where it is once open, still blocking.
##
## Built on LootProp, so the populator places and remembers it like the other props (an opened
## chest stays open when you come back to the same dungeon instance) and the dungeon cuts it out
## of the navmesh. Credits scale with the dungeon level.

@export_group("Chest")
## Rarity of the one item every chest drops, before the item_rolls ones.
@export var guaranteed_rarity: String = "rare"
## Credits are credits_min..credits_max times (1 + this x dungeon level).
@export var credits_per_level: float = 0.25
@export var interact_radius: float = 1.8

var _opener: Interactable
var _anim: AnimationPlayer


func _ready() -> void:
	super()
	remove_from_group("breakables")          # opened by hand, not by skills
	if _model != null:
		_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_play("Idle_Closed")
	_opener = _Opener.new()
	_opener.name = "Opener"
	_opener.chest = self
	_opener.prompt_text = "OPEN"
	_opener.face_player = false
	_opener.collision_mask = 3               # same as NPCs: finds the player's body
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interact_radius
	shape.shape = sphere
	_opener.add_child(shape)
	add_child(_opener)


## Close enough to open it by clicking (the same reach as the interact key).
func in_reach(player: Node3D) -> bool:
	var d := player.global_position - global_position
	return Vector2(d.x, d.z).length() <= interact_radius + 0.3


func open_chest() -> void:
	if is_open:
		return
	is_open = true
	_close_opener()
	_pay_out()
	opened.emit(self)                        # the populator remembers it for this instance
	_play("Open")
	if _anim != null and _anim.has_animation("Idle_Open"):
		_anim.queue("Idle_Open")


func set_already_open() -> void:
	is_open = true
	_close_opener()
	_play("Idle_Open")


## Open chests stay as solid as closed ones (LootProp lets broken props drop out of the navmesh).
func still_blocks() -> bool:
	return true


func _pay_out() -> void:
	var level := _dungeon_level()
	var keep_min := credits_min
	var keep_max := credits_max
	var mult := 1.0 + credits_per_level * level
	credits_min = roundi(credits_min * mult)
	credits_max = roundi(credits_max * mult)
	super()                                  # credits, then item_rolls at rarity_weights
	credits_min = keep_min
	credits_max = keep_max
	var populator := _populator()
	if populator != null and guaranteed_rarity != "":
		populator.drop_item_at(global_position + global_basis.z * 1.0, guaranteed_rarity)


func _dungeon_level() -> int:
	var populator := _populator()
	return int(populator.get("_level")) if populator != null else 1


func _close_opener() -> void:
	if _opener == null:
		return
	get_tree().call_group("interact_prompt", "hide_prompt", _opener)
	for p in get_tree().get_nodes_in_group("players"):
		if p.has_method("clear_interactable"):
			p.clear_interactable(_opener)
	_opener.queue_free()
	_opener = null


func _play(anim: String) -> void:
	if _anim != null and _anim.has_animation(anim):
		_anim.play(anim)


## The interact area around the chest. Pressing the interact key near it opens the chest.
class _Opener extends Interactable:
	var chest: LootChest

	func interact(_player: Node3D) -> void:
		if chest != null:
			chest.open_chest()
