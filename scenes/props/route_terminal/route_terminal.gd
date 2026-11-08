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
## The convoy's own terminal: DOCKED once Hardfault reaches Checkpoint (Waypoints.is_docked). The
## convoy stays moored, but the terminal still drops the player at the stops on the old route.
@export var docks := false

var _prompt: ConfirmationDialog

## The comms relay (a DeckSystem) must be working to plot a course. By path: see HullBreach.
const DeckSystemScript := preload("res://scenes/map/town/convoy/deck_system.gd")


## False while the comms relay is down (DeckOutages): the screen fills with static, the glow
## goes red and a NO SIGNAL tag hangs over it.
var signal_ok := true
var _static_mat: StandardMaterial3D
var _no_signal_tag: Label3D
var _base_title := ""
var _base_glow := 1.0
var _base_glow_col := Color.WHITE
var _ticker: Node
var _docked_tag: Label3D
var _t := 0.0


func _ready() -> void:
	super._ready()
	face_player = false                           # a console doesn't turn round
	_base_title = info_title
	if docks:
		get_tree().create_timer(0.5, false).timeout.connect(_show_docked)   # once the player's in
	var glow := get_node_or_null("Glow") as OmniLight3D
	if glow != null:
		_base_glow = glow.light_energy
		_base_glow_col = glow.light_color


## The comms relay's state, shown on the console itself (DeckOutages calls it).
func set_signal(ok: bool) -> void:
	signal_ok = ok
	var screen := get_node_or_null("Screen") as MeshInstance3D
	var glow := get_node_or_null("Glow") as OmniLight3D
	if not ok and _static_mat == null:
		_static_mat = StandardMaterial3D.new()
		_static_mat.emission_enabled = true
		_static_mat.albedo_color = Color(0.08, 0.08, 0.09)
		_no_signal_tag = Label3D.new()
		_no_signal_tag.text = "NO SIGNAL"
		_no_signal_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_no_signal_tag.pixel_size = 0.006
		_no_signal_tag.font_size = 40
		_no_signal_tag.outline_size = 10
		_no_signal_tag.modulate = Color(1.0, 0.3, 0.25)
		_no_signal_tag.position = Vector3(0, prompt_height - 0.15, 0.3)
		var font_path := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
		if ResourceLoader.exists(font_path):
			_no_signal_tag.font = load(font_path)
		add_child(_no_signal_tag)
	if screen != null:
		screen.material_override = null if ok else _static_mat
	if glow != null:
		glow.light_color = _base_glow_col if ok else Color(1.0, 0.25, 0.2)
		if ok:
			glow.light_energy = _base_glow
	if _no_signal_tag != null:
		_no_signal_tag.visible = not ok
	info_title = _base_title if ok else "NO SIGNAL"
	prompt_text = "SET COURSE" if ok else "NO SIGNAL"
	if not ok and _ticker == null:
		var tk := _Ticker.new()
		tk.tick = _static_tick
		_ticker = tk
		add_child(tk)
	if _ticker != null:
		_ticker.set_process(not ok)
	_show_docked()


func _is_docked() -> bool:
	var player := get_tree().get_first_node_in_group("players")
	return docks and player != null and Waypoints.is_docked(player.get("quests") as QuestManager)


## Docked at Checkpoint: the plate and the glow say so.
func _show_docked() -> void:
	if not is_inside_tree() or not _is_docked():
		return
	info_title = "DOCKED AT CHECKPOINT"
	info_description = "Hardfault stays moored. Pick a stop on the old route and the terminal drops you at its entrance."
	if signal_ok:
		prompt_text = "DEPLOY"
	var glow := get_node_or_null("Glow") as OmniLight3D
	if glow != null and signal_ok:
		glow.light_color = Color(1.0, 0.72, 0.25)
	if _docked_tag == null:
		_docked_tag = Label3D.new()
		_docked_tag.text = "DOCKED"
		_docked_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_docked_tag.pixel_size = 0.006
		_docked_tag.font_size = 40
		_docked_tag.outline_size = 10
		_docked_tag.modulate = Color(1.0, 0.72, 0.25)
		_docked_tag.position = Vector3(0, prompt_height - 0.15, 0.3)
		add_child(_docked_tag)
	_docked_tag.visible = signal_ok


## No signal: the screen crawls with static and now and then a red flash.
## (Its own ticker: Interactable's _process turns itself off when the console is at rest.)
func _static_tick(delta: float) -> void:
	_t += delta
	if _static_mat == null:
		return
	var n := randf()
	var flash := fposmod(_t, 2.4) < 0.18
	var col := Color(1.0, 0.2, 0.15) if flash else Color(0.55, 0.6, 0.62)
	_static_mat.emission = col
	_static_mat.emission_energy_multiplier = (1.4 if flash else 0.25 + n * 0.9)
	var glow := get_node_or_null("Glow") as OmniLight3D
	if glow != null:
		glow.light_energy = 0.3 + n * 0.4 + (0.8 if flash else 0.0)
	if _no_signal_tag != null:
		_no_signal_tag.modulate.a = 1.0 if fposmod(_t, 1.0) < 0.7 else 0.35


class _Ticker extends Node:
	var tick: Callable

	func _process(delta: float) -> void:
		if tick.is_valid():
			tick.call(delta)


func interact(player: Node3D) -> void:
	var blocked := Waypoints.breach_reason(get_tree())
	if blocked.begins_with("SWEEP") or blocked.begins_with("THE MARKERS"):
		QuestItems.toast(get_tree(), "SWEEP\nThe Collector's markers are in the yard: kill them before you leave.",
				Color(1.0, 0.35, 0.35))
		return
	if blocked != "":
		QuestItems.toast(get_tree(), "HULL BREACH\nThe Null are on the deck: clear it before you plot a course.",
				Color(1.0, 0.35, 0.35))
		return
	var comms = DeckSystemScript.find(get_tree(), "comms")
	if comms != null and comms.is_offline():
		QuestItems.toast(get_tree(), "NO SIGNAL\n%s\n%s" % [comms.offline_text, comms.fix_hint()],
				Color(1.0, 0.35, 0.35))
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
	panel.open_route(act, _is_docked())
