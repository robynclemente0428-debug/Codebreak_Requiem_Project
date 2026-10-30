class_name QuestGiverNPC
extends Interactable

@export var npc_id: String = "commander"
@export var offers: Array[QuestDefinition] = []

func interact(player: Node3D) -> void:
	engage(player)                              # turn to face whoever hands in / picks up
	GameEvents.report("talk", npc_id)
	var qm: QuestManager = player.get("quests")
	if qm == null:
		return
	for s in qm.ready_to_turn_in():
		if s.def in offers:
			var err := qm.turn_in(s.def.id)
			if err != "":
				print(err)              # later: show it in the dialogue window
			return
	for q in offers:
		if qm.can_start(q):
			qm.start(q)
			return
