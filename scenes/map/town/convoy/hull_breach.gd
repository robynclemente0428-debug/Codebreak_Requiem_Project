class_name HullBreach
extends DockDefense
## A convoy road event: the Null board the deck. Put one in the convoy (a TownArea) per event.
## The first time the player is aboard after `after_stop` is cleared, it starts on its own a
## moment after they arrive: hold the route terminal (the convoy's navigation) while the waves
## come over the rails, then clear the deck. Only once per stop (deed "hull_breach:<stop>").
## Won: credits, and it counts as an area cleared for the script budget (ScriptBudget). The
## convoy can't sail on (route terminal, Waypoints.sail) while a breach is on or due (blocks_route()).
## Dying calls it off like any DockDefense: it starts again when you come back aboard.
## The waves, enemies and growth are DockDefense's exports.
##
## The deck's systems (DeckSystem: power junction, cargo lock, comms relay) are what's at stake.
## Every `saboteur_every`-th boarder of a wave is a SABOTEUR (tagged over its head): it ignores
## you and makes for the working system with the fewest saboteurs on it, and drains it while it
## stands there. It only turns on you once you come within `saboteur_leash` or hurt it. So you
## choose: stay at the terminal (the hold only runs there) or run to save a system. A system
## that falls stays offline after the fight (vendors shut, no cargo bonus, no course plotted)
## until its code is patched (PatchPanel). The breach HUD lists them; a toast says when one is hit, low, or lost.
##
## The mini-boss is their CAPTAIN: it boards once, with the last wave, announced and tagged.
## Drop it and the boarders lose heart: every saboteur leaves its system and comes for you.

## The convoy stop whose clearing sets this event off (a Waypoint id, e.g. "act2_scrapline").
@export var after_stop := ""
@export var reward_credits := 150
## Seconds after arriving on deck before the Null board (the area's fade-in, a breath).
@export var arrival_delay := 4.0
## Every this-many-th boarder of a wave (the first, the fourth...) is a saboteur. 0 = none.
@export var saboteur_every := 4
## Metres: a saboteur turns on a player this close (or one that hurts it).
@export var saboteur_leash := 5.0
## Credits on top of reward_credits when the cargo lock held (the cargo you kept).
@export var cargo_bonus := 150
## Said when the captain (the mini-boss) boards with the last wave. %s = its name.
@export_multiline var captain_text := "THEIR CAPTAIN IS ABOARD: %s\nDrop it and the saboteurs break off."

const DEED := "hull_breach"
## By path, not class name: the editor may not have registered DeckSystem yet.
const DeckSystemScript := preload("res://scenes/map/town/convoy/deck_system.gd")
const COL_SABOTEUR := Color(1.0, 0.45, 0.2)
const COL_HIT := Color(1.0, 0.6, 0.2)
const SHORT_NAMES := {"power": "POWER", "cargo": "CARGO", "comms": "COMMS"}

var _saboteurs: Dictionary = {}          # enemy -> the DeckSystem it's after
var _systems: Array = []                # this deck's DeckSystems
var _sys_labels: Dictionary = {}         # DeckSystem -> its Label on the HUD
var _warned: Dictionary = {}             # DeckSystem -> 0 not yet, 1 hit, 2 below half
var _lost: Array[String] = []            # systems lost this breach


func _ready() -> void:
	start_anywhere = true
	bosses_last_wave_only = true                 # the captain is the climax, not a regular
	_restart_wait = arrival_delay
	add_to_group("hull_breach")
	super._ready()
	_find_systems.call_deferred()


## True while the fight is on.
func is_running() -> bool:
	return state == State.RUNNING or state == State.CLEARING


## True while the convoy can't sail on: the fight is on, or it's due (its stop is cleared and
## it hasn't been won yet: the moments before the Null board, a dialogue holding it back, a
## retry after dying). The route terminal and Waypoints.sail both ask (Waypoints.breach_reason).
func blocks_route() -> bool:
	if is_running():
		return true
	if state != State.WAITING:
		return false
	var qm := _qm()
	if qm == null or after_stop == "" or qm.deed_count(DEED, after_stop) > 0:
		return false
	var stop := _stop()
	return stop != null and Waypoints.is_cleared(stop)


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


# ---------- THE DECK SYSTEMS ----------
func _find_systems() -> void:
	_systems.clear()
	for n in get_parent().find_children("*", "Area3D", true, false):
		if n.get_script() == DeckSystemScript:
			_systems.append(n)
			if not n.went_offline.is_connected(_on_system_down):
				n.went_offline.connect(_on_system_down)
	if _systems.is_empty():
		return
	# A row of them on the breach HUD, under the boarders count
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	_count.get_parent().add_child(row)
	var font: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	for sys in _systems:
		var l := _label("", 15, Color.WHITE, font)
		row.add_child(l)
		_sys_labels[sys] = l


func _start() -> void:
	_saboteurs.clear()
	_warned.clear()
	_lost.clear()
	for sys in _systems:
		if is_instance_valid(sys):
			sys.set_contested(true)
	_update_systems_hud()
	# A route map left open from before they boarded closes: no sailing off mid-breach
	var map := get_tree().get_first_node_in_group("waypoint_panel")
	if map != null and map.has_method("is_route_open") and map.is_route_open():
		map.close()
	super._start()


func _run(delta: float) -> void:
	super._run(delta)
	if state != State.RUNNING and state != State.CLEARING:
		return
	for e in _saboteurs.keys():
		if not is_instance_valid(e) or not (e as Node).is_in_group("enemies"):
			_untag(e)
			_saboteurs.erase(e)
	for sys in _systems:
		if is_instance_valid(sys):
			sys.drain(_alive, delta)
			_warn(sys)
	_update_systems_hud()


## Every saboteur_every-th of a wave goes for a deck system instead of you.
func _spawned(e: Node3D, index: int) -> void:
	if e != null and index < 0:
		_captain_boards(e)
		return
	if e == null or index < 0 or saboteur_every <= 0 or index % saboteur_every != 0:
		return
	var sys = _pick_system()
	if sys == null:
		return
	_saboteurs[e] = sys
	e.get("ai").objective = sys
	e.get("ai").aggro_range = saboteur_leash
	_tag(e, "SABOTEUR", COL_SABOTEUR, 2.6, 34)
	var hp := e.get("health") as HealthComponent
	if hp != null:
		hp.damage_taken.connect(func(_amount: float) -> void: _release(e), CONNECT_ONE_SHOT)


## The mini-boss: a CAPTAIN tag, a toast, and its death sends every saboteur after you.
func _captain_boards(e: Node3D) -> void:
	_tag(e, "CAPTAIN", Color(1.0, 0.82, 0.25), 3.1, 44)
	var name_ := str(e.get("display_name"))
	QuestItems.toast(get_tree(), captain_text % (name_.to_upper() if name_ != "" else "THE CAPTAIN"), COL_WARN)
	var hp := e.get("health") as HealthComponent
	if hp != null:
		hp.died.connect(_on_captain_died, CONNECT_ONE_SHOT)


func _on_captain_died() -> void:
	if state != State.RUNNING and state != State.CLEARING:
		return
	var n := _saboteurs.size()
	for e in _saboteurs.keys():
		_release(e)
	QuestItems.toast(get_tree(), "CAPTAIN DOWN\n%s" % (
		"The saboteurs break off: they're coming for you." if n > 0 else "The rest lose heart."), COL_GOOD)


func _tag(e: Node3D, text: String, col: Color, height: float, size_px: int) -> void:
	var tag := Label3D.new()
	tag.name = text.capitalize() + "Tag"
	tag.text = text
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.pixel_size = 0.005
	tag.font_size = size_px
	tag.outline_size = 8
	tag.modulate = col
	tag.position.y = height
	e.add_child(tag)


## The working system with the fewest saboteurs already after it (null = none left).
func _pick_system():
	var best = null
	var best_n := 1 << 30
	for sys in _systems:
		if not is_instance_valid(sys) or sys.is_offline():
			continue
		var n := 0
		for s in _saboteurs.values():
			if s == sys:
				n += 1
		if n < best_n:
			best_n = n
			best = sys
	return best


## Hurt (or no system left): it forgets the system and comes for you like the rest.
func _release(e: Node3D) -> void:
	if not is_instance_valid(e) or not _saboteurs.has(e):
		return
	_saboteurs.erase(e)
	_untag(e)
	var ai = e.get("ai")
	if ai != null:
		ai.objective = null
		ai.aggro_range = spawn_max * 3.0


func _untag(e: Variant) -> void:
	if is_instance_valid(e):
		var tag := (e as Node).get_node_or_null("SaboteurTag")
		if tag != null:
			tag.queue_free()


## A toast the first time a system is hit in this breach, and again when it's below half.
func _warn(sys) -> void:
	if sys.is_offline():
		return
	var level := int(_warned.get(sys, 0))
	var frac: float = sys.integrity / maxf(sys.max_integrity, 1.0)
	if level < 1 and sys.under_attack:
		_warned[sys] = 1
		QuestItems.toast(get_tree(), "THE NULL ARE AT THE %s\nIf it falls: %s" % [
			String(sys.npc_name).to_upper(), sys.offline_text], COL_HIT)
	elif level < 2 and frac <= 0.5:
		_warned[sys] = 2
		QuestItems.toast(get_tree(), "%s AT %d%%" % [String(sys.npc_name).to_upper(), ceili(frac * 100.0)], COL_WARN)


func _on_system_down(sys) -> void:
	if state != State.RUNNING and state != State.CLEARING:
		return
	var name_ := String(sys.npc_name).to_upper()
	_lost.append(name_)
	QuestItems.toast(get_tree(), "%s OFFLINE\n%s\nThe Null corrupted its code: patch it once the deck is clear." % [
		name_, sys.offline_text], COL_WARN)
	# Its saboteurs move on to the next working system
	for e in _saboteurs.keys():
		if _saboteurs[e] != sys:
			continue
		var next = _pick_system()
		if next == null:
			_release(e)
		else:
			_saboteurs[e] = next
			e.get("ai").objective = next


func _update_systems_hud() -> void:
	for sys in _sys_labels:
		var l := _sys_labels[sys] as Label
		if not is_instance_valid(sys):
			l.visible = false
			continue
		var short: String = SHORT_NAMES.get(sys.system_id, String(sys.npc_name).to_upper())
		var col := Color(0.85, 0.96, 1.0)
		if sys.is_offline():
			l.text = "%s OFFLINE" % short
			col = COL_WARN
		else:
			var pct := ceili(sys.integrity / maxf(sys.max_integrity, 1.0) * 100.0)
			l.text = "%s %d%%%s" % [short, pct, " !" if sys.under_attack else ""]
			if sys.under_attack:
				col = COL_HIT
			elif pct >= 100:
				col = COL_GOOD
		l.add_theme_color_override("font_color", col)


func _end_contest() -> void:
	for e in _saboteurs.keys():
		_untag(e)
	_saboteurs.clear()
	for sys in _systems:
		if is_instance_valid(sys):
			sys.set_contested(false)


func _on_player_died() -> void:
	if state == State.RUNNING or state == State.CLEARING:
		_end_contest()
	super._on_player_died()


func _held() -> void:
	state = State.DONE
	_hud.visible = false
	_set_alert(false)
	_end_contest()
	GameEvents.report(DEED, after_stop)                          # never again for this stop
	GameEvents.report(ScriptBudget.CLEAR_DEED, "breach_" + after_stop)   # +script points, like a cleared area
	var cargo = _system("cargo")
	var kept_cargo: bool = cargo != null and cargo.is_online()
	var credits := reward_credits + (cargo_bonus if kept_cargo else 0)
	var player := _player()
	var wallet := player.get("currency") as CurrencyComponent if player != null else null
	if wallet != null and credits > 0:
		wallet.add(credits)
	var text := "%s\n+%d CREDITS%s  //  +1 SCRIPT POINT ON EVERY SKILL" % [
		done_toast, credits, " (CARGO SAVED)" if kept_cargo else ""]
	if _systems.is_empty():
		pass
	elif _lost.is_empty():
		text += "\nEVERY SYSTEM HELD."
	else:
		text += "\nLOST: %s. Patch their code on deck." % ", ".join(_lost)
	QuestItems.toast(get_tree(), text, COL_GOOD if _lost.is_empty() else COL_HIT)


func _system(id: String):
	for sys in _systems:
		if is_instance_valid(sys) and sys.system_id == id:
			return sys
	return null


func _stop() -> Waypoint:
	for act in Waypoints.acts():
		var w := act.find(after_stop)
		if w != null:
			return w
	return null
