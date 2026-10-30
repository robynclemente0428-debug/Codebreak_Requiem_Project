class_name DialogueNPC
extends Interactable

@export var npc_id: String = "commander"
@export var npc_name: String = "COMMANDER"
@export var dialogue: DialogueData

func interact(player: Node3D) -> void:
	GameEvents.report("talk", npc_id)
	var panel := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if panel == null:
		push_warning("DialogueNPC: no DialoguePanel in the scene (group dialogue_panel)")
		return
	panel.open_dialogue(self, player)
