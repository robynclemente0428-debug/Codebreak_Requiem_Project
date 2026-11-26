class_name HullBreach
extends DockDefense

@export var after_stop := ""
@export var reward_credits := 150
@export var arrival_delay := 4.0
@export var saboteur_every := 1
@export var saboteur_leash := 5.0
@export var cargo_bonus := 150
@export_multiline var captain_text := "THEIR CAPTAIN IS ABOARD: %s\nDrop it and the saboteurs break off."

const DEED := "hull_breach"
const DeckSystemScript := preload("res://scenes/map/town/convoy/deck_system.gd")
const COL_SABOTEUR := Color(1.0, 0.45, 0.2)
const COL_HIT := Color(1.0, 0.6, 0.2)
const SHORT_NAMES := {"power": "POWER", "cargo": "CARGO", "comms": "COMMS", "iff": "IFF"}

var _saboteurs: Dictionary = {}
var _systems: Array = []
var _sys_labels: Dictionary = {}
var _warned: Dictionary = {}
var _lost: Array[String] = []


func _ready() -> void:
	start_anywhere = true
	bosses_last_wave_only = true
	_restart_wait = arrival_delay
	add_to_group("hull_breach")
	super._ready()
	_find_systems.call_deferred()


func is_running() -> bool:
	return state == State.RUNNING or state == State.CLEARING


func blocks_route() -> bool:
	if is_running():
		return true
	if state != State.WAITING:
		return false
	return _anyone_needs()


func _own_need() -> bool:
	return is_due()


func _state_extra() -> Array:
	var out: Array = []
	for sys in _systems:
		if is_instance_valid(sys):
			out.append([sys.system_id, sys.integrity, sys.is_offline(), sys.under_attack])
	return out


func _apply_extra(extra: Array) -> void:
	if not _is_on():
		return
	for entry in extra:
		if not entry is Array or entry.size() != 4:
			continue
		var sys = _system(str(entry[0]))
		if sys != null:
			sys.show_remote(float(entry[1]), bool(entry[2]), bool(entry[3]))


func _copy_started() -> void:
	_warned.clear()
	_lost.clear()
	for sys in _systems:
		if is_instance_valid(sys):
			sys.set_contested(true)
	var map := get_tree().get_first_node_in_group("waypoint_panel")
	if map != null and map.has_method("is_route_open") and map.is_route_open():
		map.close()
	super._copy_started()


func _copy_stopped() -> void:
	_end_contest()
	super._copy_stopped()


func _copy_run(delta: float) -> void:
	super._copy_run(delta)
	_update_systems_hud()


func _copy_done(args: Array) -> void:
	_pay_out(args.size() == 2 and args[0] == true, args[1] if args.size() == 2 and args[1] is Array else [])


func is_due() -> bool:
	var qm := _qm()
	if qm == null or after_stop == "" or Waypoints.is_docked(qm):
		return false
	return qm.deed_count(Waypoints.FINISH_DEED, after_stop) > qm.deed_count(DEED, after_stop)


func _find_portal() -> Node3D:
	if is_instance_valid(_portal):
		return _portal
	var found := get_parent().find_children("*", "RouteTerminal", true, false)
	_portal = found[0] as Node3D if not found.is_empty() else null
	return _portal


func _wants_to_start() -> bool:
	if not _anyone_needs():
		return false
	for b in get_tree().get_nodes_in_group("hull_breach"):
		if b != self and b.is_running():
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


func _find_systems() -> void:
	_systems.clear()
	for n in get_parent().find_children("*", "Area3D", true, false):
		if n.get_script() == DeckSystemScript:
			_systems.append(n)
			if not n.went_offline.is_connected(_on_system_down):
				n.went_offline.connect(_on_system_down)
	if _systems.is_empty():
		return
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


func _pick_system():
	var best = null
	var best_n := 1 << 30
	for sys in _systems:
		if not is_instance_valid(sys) or sys.is_offline() or not sys.sabotage_target:
			continue
		var n := 0
		for s in _saboteurs.values():
			if s == sys:
				n += 1
		if n < best_n:
			best_n = n
			best = sys
	return best


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
		if not is_instance_valid(sys) or not (sys.sabotage_target or sys.is_offline()):
			l.visible = false
			continue
		l.visible = true
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
	if (state == State.RUNNING or state == State.CLEARING) and not _someone_stands():
		_end_contest()
	super._on_player_died()


func _held() -> void:
	state = State.DONE
	_hud.visible = false
	_set_alert(false)
	_end_contest()
	var cargo = _system("cargo")
	var kept_cargo: bool = cargo != null and cargo.is_online()
	if Coop.in_game:
		_needed_by.clear()
		Coop.event_send(_key(), "done", [kept_cargo, _lost])
	_pay_out(kept_cargo, _lost)


func _pay_out(kept_cargo: bool, lost: Array) -> void:
	var owed := not Coop.in_game or is_due()
	if owed:
		GameEvents.report(DEED, after_stop)
		GameEvents.report(ScriptBudget.CLEAR_DEED, "breach_" + after_stop)
	var credits := reward_credits + (cargo_bonus if kept_cargo else 0)
	var wallet := Coop.own_player(get_tree()).get("currency") as CurrencyComponent \
			if Coop.own_player(get_tree()) != null else null
	if wallet != null and credits > 0:
		wallet.add(credits)
	var text := "%s\n+%d CREDITS%s%s" % [done_toast, credits, " (CARGO SAVED)" if kept_cargo else "",
			"  //  +1 SCRIPT POINT ON EVERY SKILL" if owed else ""]
	if _systems.is_empty():
		pass
	elif lost.is_empty():
		text += "\nEVERY SYSTEM HELD."
	else:
		text += "\nLOST: %s. Patch their code on deck." % ", ".join(PackedStringArray(lost))
	QuestItems.toast(get_tree(), text, COL_GOOD if lost.is_empty() else COL_HIT)


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
