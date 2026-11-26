class_name DialogueNPC
extends Interactable

@export var npc_id: String = "commander"
@export var npc_name: String = "COMMANDER"
@export var dialogue: DialogueData

## Doesn't exist for the player until this quest is turned in (Vesper, out of quarantine).
@export var shown_after_quest := ""
## Gone while this is the ending the world shows (Endings.current): Vesper in the Core after MERGE,
## whose voice is the Last Log's from then on.
@export var hidden_by_ending := ""        # "merge", "overwrite" or "terminate"


func _ready() -> void:
	super()
	if shown_after_quest == "" and hidden_by_ending == "":
		return
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_check_shown)
	add_child(timer)
	timer.start()
	_check_shown()


func _check_shown() -> void:
	var player := get_tree().get_first_node_in_group("players")
	var qm = player.get("quests") if player != null else null
	var shown: bool = qm != null and (shown_after_quest == "" or qm.is_completed(shown_after_quest))
	if hidden_by_ending != "" and Endings.current(qm) == hidden_by_ending:
		shown = false
	if shown == visible and monitoring == shown:
		return                                   # nothing changed (checked twice a second)
	visible = shown
	monitoring = shown
	monitorable = shown
	var shape := get_node_or_null("Body/CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.disabled = not shown


func interact(player: Node3D) -> void:
	GameEvents.report("talk", npc_id)
	var panel := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if panel == null:
		push_warning("DialogueNPC: no DialoguePanel in the scene (group dialogue_panel)")
		return
	panel.open_dialogue(self, player)
