class_name RouteTerminal
extends Interactable
## The convoy's route terminal. Act II's dungeons are stops on the convoy's route, not places
## on the waypoint map: use the terminal (walk up and press the interact key, or click it from
## anywhere on deck) to open the route map (WaypointPanel.open_route), then click a stop to be
## dropped at its entrance. Both of a stop's portals lead back to the convoy; reaching its exit
## opens the next stop (Waypoints.clear_stop).

## The name on its plate and hover tag (NpcNameplates, NpcInfoPanel read npc_name).
@export var npc_name: String = "Route Terminal"
## The act whose stops it lists. Empty = the act of the area it stands in (Waypoints).
@export var route_act: WaypointAct
## The rank exam the player should pass before taking the road (its stops are built round what
## it unlocks: the Architect exam's loops). Until then the route stays locked. "" = no exam.
@export var required_exam := "exam_architect"

var _prompt: ConfirmationDialog


func _ready() -> void:
	super._ready()
	face_player = false                           # a console doesn't turn round


func interact(player: Node3D) -> void:
	for b in get_tree().get_nodes_in_group("hull_breach"):
		if (b as HullBreach).is_running():
			QuestItems.toast(get_tree(), "HULL BREACH\nClear the deck before you plot a course.", Color(1.0, 0.35, 0.35))
			return
	var why := exam_needed(player)
	if why != "":
		_ask(why)
		return
	_open_route()


## What the player still has to do for required_exam ("" = done, or none needed).
func exam_needed(player: Node3D) -> String:
	if required_exam == "" or player == null:
		return ""
	var qm := player.get("quests") as QuestManager
	if qm == null or qm.is_completed(required_exam):
		return ""
	var rank := _exam_rank()
	var s: QuestState = qm.get_state(required_exam)
	if s != null and s.status == QuestState.Status.READY_TO_TURN_IN:
		return "You passed the %s exam. Report to Examiner Sudo for your rank before you go." % rank
	if s != null:
		return "Finish the %s exam in Sudo's sandbox before you go." % rank
	return "Examiner Sudo hasn't ranked you %s yet. Sit the exam before you go." % rank


## The rank required_exam gives ("ARCHITECT").
func _exam_rank() -> String:
	for r in Ranks.LADDER:
		if r["exam"] == required_exam:
			return r["name"]
	return "next"


## The route stays locked: why, and what the exam unlocks. One button, it only closes.
func _ask(why: String) -> void:
	if _prompt == null:
		_prompt = ConfirmationDialog.new()
		CyberDialog.style(_prompt)
		_prompt.ok_button_text = "OK"
		_prompt.get_cancel_button().visible = false
		add_child(_prompt)
	var idx := Ranks.LADDER.map(func(r: Dictionary) -> String: return r["exam"]).find(required_exam)
	var unlocks := ", ".join(Ranks.unlock_lines(idx)) if idx > 0 else ""
	_prompt.dialog_text = "ROUTE LOCKED

%s

The stops ahead are built for what it unlocks%s." % [
		why, (": " + unlocks.to_lower()) if unlocks != "" else ""]
	_prompt.popup_centered()


func _open_route() -> void:
	var panel := get_tree().get_first_node_in_group("waypoint_panel") as WaypointPanel
	if panel == null:
		return
	var act := route_act
	if act == null:
		var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
		act = Waypoints.act_of_scene(am.current_scene_path()) if am != null else null
	if act == null:
		push_warning("RouteTerminal: no route act for this area")
		return
	panel.open_route(act)
