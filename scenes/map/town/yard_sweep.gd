class_name YardSweep
extends DockDefense
## Act III's road event, in place of hull breaches while the convoy is docked. Put one in the
## Quarantine Yard. Each run through a district owes one (like HullBreach's stops): when you come
## back, an alarm sounds and the Collector's marker drones come for Hardfault's crates.
##
##   1. A drone hangs near its crate and marks it (mark_time seconds, faster with more drones).
##      A fully marked crate is TAGGED, and the drone moves on to the next one.
##   2. Kill every drone before the sweep timer (load_time) ends: the tags come off, nothing lost.
##   3. The timer ends first: every tagged crate is deleted for good (deed "sweep_lost:<crate>")
##      and the drones leave.
## Hurting a drone, or walking close to it, turns it on you, as a saboteur does.
## Paid: reward_credits, plus crate_bonus for each crate left: a breach's cargo bonus in reverse.
## Dying calls it off and it comes again. They stop for good once the Collector falls.

const DEED := "yard_sweep"
const DEED_TARGET := "yard"
const LOST_DEED := "sweep_lost"
const COLLECTOR := "the_collector"
const STOPS_ACT := 3
const COL_MARK := Color(1.0, 0.2, 0.15)

@export var reward_credits := 150
@export var crate_bonus := 40
## Seconds after arriving before the alarm.
@export var arrival_delay := 4.0
## Seconds one drone takes to tag a crate.
@export var mark_time := 9.0
## Metres: a drone this close to its crate is marking it.
@export var mark_range := 8.0
## Metres: a drone turns on a player this close.
@export var leash := 5.0
## Crates are the Furniture props whose names start with this.
@export var crate_prefix := "Cargo"

var _crates: Array[Dictionary] = []      # {"prop": Node3D, "marks": 0..1, "tag": Label3D or null}
var _assigned: Dictionary = {}           # drone -> its crate's prop
var _released: Dictionary = {}           # drones that turned on the player


func _ready() -> void:
	start_anywhere = true
	mini_bosses = []
	_restart_wait = arrival_delay
	add_to_group("hull_breach")               # the route asks the same questions (Waypoints.breach_reason)
	super._ready()
	_find_crates.call_deferred()


func is_running() -> bool:
	return state == State.RUNNING or state == State.CLEARING


func blocks_route() -> bool:
	return is_running() or (state == State.WAITING and is_due() and not _crates.is_empty())


func route_block_text() -> String:
	return "SWEEP: KILL THE MARKERS FIRST" if is_running() else "THE MARKERS ARE COMING: HOLD THE YARD FIRST"


## True while a run through a district hasn't been answered by a sweep yet.
func is_due() -> bool:
	var qm := _qm()
	if qm == null or ScriptBudget.is_boss_killed(qm, COLLECTOR):
		return false
	return _runs_finished(qm) > qm.deed_count(DEED, DEED_TARGET)


func _runs_finished(qm: QuestManager) -> int:
	var n := 0
	for act in Waypoints.acts():
		if act.act_number != STOPS_ACT:
			continue
		for w in act.waypoints:
			n += qm.deed_count(Waypoints.FINISH_DEED, w.id)
	return n


func _find_portal() -> Node3D:
	if is_instance_valid(_portal):
		return _portal
	var found := get_parent().find_children("*", "RouteTerminal", true, false)
	_portal = found[0] as Node3D if not found.is_empty() else null
	return _portal


func _wants_to_start() -> bool:
	if _crates.is_empty() or not is_due() or _restart_wait > 0.0:
		return false
	var dialogue := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if dialogue != null and dialogue.is_open():
		return false
	var player := _player()
	if _find_portal() == null or player == null:
		return false
	var hp := player.get("health") as HealthComponent
	return hp == null or hp.current_health > 0.0


## The yard's crates, without the ones an earlier sweep deleted.
func _find_crates() -> void:
	_crates.clear()
	var furniture := get_parent().get_node_or_null("Furniture")
	if furniture == null:
		return
	var qm := _qm()
	for c in furniture.get_children():
		if not (c is Node3D and String(c.name).begins_with(crate_prefix)):
			continue
		if qm != null and qm.deed_count(LOST_DEED, String(c.name)) > 0:
			c.queue_free()
			continue
		_crates.append({"prop": c, "marks": 0.0, "tag": null})


func _start() -> void:
	_find_crates()
	_assigned.clear()
	_released.clear()
	await super._start()


func _run(delta: float) -> void:
	_alive.assign(_alive.filter(func(e) -> bool: return is_instance_valid(e) and e.is_in_group("enemies")))
	for e in _assigned.keys():
		if not is_instance_valid(e) or not (e as Node).is_in_group("enemies"):
			_assigned.erase(e)
	if state == State.RUNNING and _baked:
		progress = minf(progress + delta / load_time, 1.0)
		_next_wave -= delta
		if _next_wave <= 0.0 and _wave < wave_sizes.size():
			_spawn_wave()
			_next_wave = wave_every
		_mark(delta)
		if _wave >= wave_sizes.size() and _alive.is_empty():
			_end_sweep(false)
			return
		if progress >= 1.0:
			_end_sweep(true)
			return
	_update_hud(true)
	var tagged := _tagged().size()
	if tagged > 0:
		_count.text += "   ·   TAGGED: %d" % tagged


func _spawned(e: Node3D, _index: int) -> void:
	if e == null:
		return
	var crate := _pick_crate()
	if crate == null:
		return
	_assigned[e] = crate
	e.get("ai").objective = crate
	e.get("ai").aggro_range = leash
	var hp := e.get("health") as HealthComponent
	if hp != null:
		hp.damage_taken.connect(func(_amount: float) -> void: _release(e), CONNECT_ONE_SHOT)


## The crate not yet tagged with the fewest drones after it (null = all tagged).
func _pick_crate() -> Node3D:
	var best: Node3D = null
	var best_n := 1 << 30
	for c in _crates:
		if not is_instance_valid(c["prop"]) or float(c["marks"]) >= 1.0:
			continue
		var n := 0
		for prop in _assigned.values():
			if prop == c["prop"]:
				n += 1
		if n < best_n:
			best_n = n
			best = c["prop"]
	return best


func _release(e: Node3D) -> void:
	if not is_instance_valid(e) or not _assigned.has(e):
		return
	_assigned.erase(e)
	_released[e] = true
	e.get("ai").objective = null
	e.get("ai").aggro_range = spawn_max * 3.0


func _mark(delta: float) -> void:
	for c in _crates:
		if not is_instance_valid(c["prop"]) or float(c["marks"]) >= 1.0:
			continue
		var prop: Node3D = c["prop"]
		var at_it := 0
		for e in _assigned.keys():
			if _assigned[e] == prop and (e as Node3D).global_position.distance_to(prop.global_position) <= mark_range:
				at_it += 1
		if at_it == 0:
			continue
		c["marks"] = minf(float(c["marks"]) + at_it * delta / mark_time, 1.0)
		_show_mark(c)
		if float(c["marks"]) >= 1.0:
			_tagged_crate(prop)


func _show_mark(c: Dictionary) -> void:
	if c["tag"] == null:
		var tag := Label3D.new()
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.pixel_size = 0.005
		tag.font_size = 40
		tag.outline_size = 8
		tag.modulate = COL_MARK
		tag.position.y = 2.2
		(c["prop"] as Node3D).add_child(tag)
		c["tag"] = tag
	(c["tag"] as Label3D).text = "TAGGED" if float(c["marks"]) >= 1.0 else "MARKING %d%%" % roundi(float(c["marks"]) * 100.0)


## A crate is tagged: its drones move on to the next.
func _tagged_crate(prop: Node3D) -> void:
	QuestItems.toast(get_tree(), "CRATE TAGGED\nKill the markers before the sweep, or it's deleted.", COL_MARK)
	for e in _assigned.keys():
		if _assigned[e] != prop:
			continue
		_assigned.erase(e)
		var next := _pick_crate()
		if next == null:
			_assigned[e] = prop
			_release(e)
		else:
			_assigned[e] = next
			(e as Node).get("ai").objective = next


func _tagged() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _crates:
		if is_instance_valid(c["prop"]) and float(c["marks"]) >= 1.0:
			out.append(c)
	return out


## `swept`: the timer ran out, so the tagged crates go. Otherwise the drones all died in time.
func _end_sweep(swept: bool) -> void:
	state = State.DONE
	_hud.visible = false
	_set_alert(false)
	var lost := 0
	for c in _crates.duplicate():
		if not is_instance_valid(c["prop"]):
			continue
		if swept and float(c["marks"]) >= 1.0:
			GameEvents.report(LOST_DEED, String((c["prop"] as Node).name))
			(c["prop"] as Node).queue_free()
			_crates.erase(c)
			lost += 1
		else:
			_clear_mark(c)
	for e in _alive:
		if is_instance_valid(e):
			e.queue_free()
	_alive.clear()
	_assigned.clear()
	var qm := _qm()
	if qm != null:                                # every run owed so far is answered by this one
		GameEvents.report(DEED, DEED_TARGET, maxi(_runs_finished(qm) - qm.deed_count(DEED, DEED_TARGET), 1))
	var credits := reward_credits + crate_bonus * _crates.size()
	var player := _player()
	var wallet := player.get("currency") as CurrencyComponent if player != null else null
	if wallet != null:
		wallet.add(credits)
	if lost > 0:
		QuestItems.toast(get_tree(), "SWEEP COMPLETE\n%d CRATE%s DELETED  //  +%d CREDITS" % [lost, "S" if lost != 1 else "", credits], COL_MARK)
	else:
		QuestItems.toast(get_tree(), "%s\n+%d CREDITS  //  EVERY CRATE KEPT" % [done_toast, credits], COL_GOOD)


func _clear_mark(c: Dictionary) -> void:
	c["marks"] = 0.0
	if c["tag"] != null and is_instance_valid(c["tag"]):
		(c["tag"] as Node).queue_free()
	c["tag"] = null


func _on_player_died() -> void:
	if is_running():
		for c in _crates:
			if is_instance_valid(c["prop"]):
				_clear_mark(c)
		_assigned.clear()
	super._on_player_died()
