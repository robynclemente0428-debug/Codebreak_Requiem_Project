class_name TowerTerminal
extends RouteTerminal
## The Core's tower terminal: the way up into The Recursion (Tower). It opens the tower map
## (TowerMap) once an ending is chosen; before that it says what it's waiting for. The same
## console as the convoy's route terminal, in the Core's gold.


func _ready() -> void:
	super._ready()
	required_exam = ""
	_refresh.call_deferred()


## Its plate: locked until the campaign is finished.
func _refresh() -> void:
	var player := get_tree().get_first_node_in_group("players") if is_inside_tree() else null
	var open := player != null and Tower.is_unlocked(player.get("quests") as QuestManager)
	prompt_text = "CLIMB" if open else "LOCKED"
	info_description = ("Fifty floors up from the Core, each rolled once. Cleared %d of %d." % [Tower.cleared_top(), Tower.FLOORS]) \
			if open else "Sealed. It opens once the choice at the Last Log is made."


func interact(player: Node3D) -> void:
	_refresh()
	var qm := player.get("quests") as QuestManager if player != null else null
	if not Tower.is_unlocked(qm):
		QuestItems.toast(get_tree(), "THE RECURSION IS SEALED\nIt opens once the choice at the Last Log is made.",
				Color(1.0, 0.82, 0.30))
		return
	var map := TowerMap.get_or_make(get_tree())
	if map != null:
		map.open()
