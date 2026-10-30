@tool
extends EditorScript

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/quests")

	var equip := Objective.new()
	equip.description = "Equip your starting weapon"
	equip.kind = "equip_slot"
	equip.target = str(EquipmentSlots.Slot.WEAPON)

	var socket := Objective.new()
	socket.description = "Socket your skill gem"
	socket.kind = "socket_skill"
	socket.target = ""                       # any gem

	var bind := Objective.new()
	bind.description = "Bind the skill to your attack key"
	bind.kind = "bind_skill"
	bind.target = "attack"

	var q := QuestDefinition.new()
	q.id = "tutorial_gear"
	q.title = "GEAR UP"
	q.description = "Open your backpack (I) and equip your weapon, then socket your gem in the skill panel (K)."
	q.objectives.assign([equip, socket, bind])
	q.reward_credits = 25

	var err := ResourceSaver.save(q, "res://data/quests/tutorial_gear.tres")
	print("Saved tutorial_gear: ", error_string(err))
