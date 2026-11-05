class_name HullBreach
extends DockDefense
## A convoy road event: the Null board the deck. Put one in the convoy (a TownArea) per event.
## The first time the player is aboard after `after_stop` is cleared, it starts on its own a
## moment after they arrive: hold the route terminal (the convoy's navigation) while the waves
## come over the rails, then clear the deck. Only once per stop (deed "hull_breach:<stop>").
## Won: credits, and it counts as an area cleared for the script budget (ScriptBudget). The
## route terminal won't plot a course while a breach is on (RouteTerminal checks is_running()).
## Dying calls it off like any DockDefense: it starts again when you come back aboard.
## The waves, enemies and growth are DockDefense's exports.

## The convoy stop whose clearing sets this event off (a Waypoint id, e.g. "act2_scrapline").
@export var after_stop := ""
@export var reward_credits := 150
## Seconds after arriving on deck before the Null board (the area's fade-in, a breath).
@export var arrival_delay := 4.0

const DEED := "hull_breach"


func _ready() -> void:
	start_anywhere = true
	_restart_wait = arrival_delay
	add_to_group("hull_breach")
	super._ready()


## True while the fight is on: the route terminal waits for it.
func is_running() -> bool:
	return state == State.RUNNING or state == State.CLEARING


## The breach is held at the route terminal, not a portal.
func _find_portal() -> Node3D:
	if is_instance_valid(_portal):
		return _portal
	var found := get_parent().find_children("*", "RouteTerminal", true, false)
	_portal = found[0] as Node3D if not found.is_empty() else null
	return _portal


func _wants_to_start() -> bool:
	var qm := _qm()
	if qm == null or after_stop == "" or qm.deed_count(DEED, after_stop) > 0:
		return false
	var stop := _stop()
	if stop == null or not Waypoints.is_cleared(stop):
		return false
	var dialogue := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if dialogue != null and dialogue.is_open():
		return false
	var player := _player()
	if _find_portal() == null or player == null:
		return false
	var hp := player.get("health") as HealthComponent
	if hp != null and hp.current_health <= 0.0:
		return false
	return _restart_wait <= 0.0


func _held() -> void:
	state = State.DONE
	_hud.visible = false
	_set_alert(false)
	GameEvents.report(DEED, after_stop)                          # never again for this stop
	GameEvents.report(ScriptBudget.CLEAR_DEED, "breach_" + after_stop)   # +script points, like a cleared area
	var player := _player()
	var wallet := player.get("currency") as CurrencyComponent if player != null else null
	if wallet != null and reward_credits > 0:
		wallet.add(reward_credits)
	QuestItems.toast(get_tree(), "%s\n+%d CREDITS  //  +1 SCRIPT POINT ON EVERY SKILL" % [
		done_toast, reward_credits], COL_GOOD)


func _stop() -> Waypoint:
	for act in Waypoints.acts():
		var w := act.find(after_stop)
		if w != null:
			return w
	return null
