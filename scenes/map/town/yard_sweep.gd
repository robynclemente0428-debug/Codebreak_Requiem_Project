class_name YardSweep
extends DockDefense
## Act III's road event, in place of hull breaches while the convoy is docked. Put one in the
## Quarantine Yard. Each run through a district owes one (like HullBreach's stops): when you come
## back, an alarm sounds and the Collector's marker drones come for Hardfault's crates.
##
##   1. A drone hangs near its crate and marks it (mark_time seconds, faster with more drones).
##      A fully marked crate is TAGGED, and the drone moves on to the next one.
##   2. Kill every drone before the sweep timer (load_time) ends: the tags come off, nothing lost.
##   3. The timer ends first: every tagged crate is deleted (deed "sweep_lost:<crate>") and the
##      drones leave. Deleted means C-0's deletion queue, in the Sweep, until the Collector falls:
##      it can be brought back from there (YardCrates, QueuedCrate).
## Every crate is someone's (YardCrates: Hex's spare cells, Sudo's archive, the memorial board...),
## named over it, and losing one changes something. Each sweep is an AUDIT the Registrar announces
## as you arrive: one named crate, and the first wave's drones all go for it.
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

const COL_NAME := Color(0.85, 0.9, 0.95, 0.8)
const COL_AUDIT := Color(1.0, 0.55, 0.3)

var _crates: Array[Dictionary] = []      # {"prop": Node3D, "id": String, "marks": 0..1, "tag": Label3D or null}
var _assigned: Dictionary = {}           # drone -> its crate's prop
var _released: Dictionary = {}           # drones that turned on the player
var _audit := ""                         # the crate id this sweep's audit is for ("" = not announced)
var _sent := 0                           # drones spawned this sweep: the first wave goes for the audit


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
	if _crates.is_empty() or not is_due():
		return false
	if _audit == "":
		_announce_audit()                         # as you arrive: the alarm follows arrival_delay later
	if _restart_wait > 0.0:
		return false
	var dialogue := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if dialogue != null and dialogue.is_open():
		return false
	var player := _player()
	if _find_portal() == null or player == null:
		return false
	var hp := player.get("health") as HealthComponent
	return hp == null or hp.current_health > 0.0


## The yard's crates, without the ones an earlier sweep deleted (and that haven't come back from
## C-0's queue). Each wears its name (YardCrates).
func _find_crates() -> void:
	_crates.clear()
	var furniture := get_parent().get_node_or_null("Furniture")
	if furniture == null:
		return
	var qm := _qm()
	for c in furniture.get_children():
		if not (c is Node3D and String(c.name).begins_with(crate_prefix)):
			continue
		var id := String(c.name)
		if YardCrates.is_deleted(qm, id):
			c.queue_free()
			continue
		_crates.append({"prop": c, "id": id, "marks": 0.0, "tag": null})
		if YardCrates.is_crate(id) and c.get_node_or_null("CrateName") == null:
			var plate := Label3D.new()
			plate.name = "CrateName"
			plate.text = YardCrates.name_of(id)
			plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			plate.pixel_size = 0.004
			plate.font_size = 32
			plate.outline_size = 6
			plate.modulate = COL_NAME
			plate.position.y = 1.55
			(c as Node3D).add_child(plate)


## The Registrar names the crate this sweep is auditing; the first wave's drones all go for it.
func _announce_audit() -> void:
	var qm := _qm()
	var present: Array = _crates.map(func(c: Dictionary) -> String: return str(c["id"]))
	_audit = YardCrates.audit_target(qm, qm.deed_count(DEED, DEED_TARGET) if qm != null else 0, present)
	if _audit == "":
		_audit = "-"                              # nothing named left: an ordinary sweep
		return
	QuestItems.toast(get_tree(), "REGISTRAR // AUDIT SCHEDULED\n%s, registered to %s, references the duplicate. C-0 is sending markers." % [
		YardCrates.name_of(_audit), YardCrates.owner_of(_audit)], COL_AUDIT)


func _crate_named(id: String) -> Dictionary:
	for c in _crates:
		if str(c["id"]) == id and is_instance_valid(c["prop"]):
			return c
	return {}


func _start() -> void:
	_find_crates()
	_assigned.clear()
	_released.clear()
	_sent = 0
	if _audit == "":
		_announce_audit()
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
	_sent += 1
	var crate: Node3D = null
	var audited := _crate_named(_audit)
	if _sent <= int(wave_sizes[0] if not wave_sizes.is_empty() else 0) and not audited.is_empty() \
			and float(audited["marks"]) < 1.0:
		crate = audited["prop"]                   # the first wave: all on the audited crate
	if crate == null:
		crate = _pick_crate()
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
	var id := String(prop.name)
	QuestItems.toast(get_tree(), "%s TAGGED\nKill the markers before the sweep, or it's deleted: %s." % [
		YardCrates.name_of(id), YardCrates.loss_of(id)], COL_MARK)
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
	var lost_names: Array = []
	for c in _crates.duplicate():
		if not is_instance_valid(c["prop"]):
			continue
		if swept and float(c["marks"]) >= 1.0:
			GameEvents.report(LOST_DEED, String((c["prop"] as Node).name))
			lost_names.append(YardCrates.name_of(String((c["prop"] as Node).name)))
			(c["prop"] as Node).queue_free()
			_crates.erase(c)
			lost += 1
		else:
			_clear_mark(c)
	_audit = ""                                  # the next sweep announces its own
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
		QuestItems.toast(get_tree(), "SWEEP COMPLETE  //  +%d CREDITS\nDELETED: %s\nIt waits in C-0's deletion queue, in the Sweep. Bring it back before the Collector burns the queue." % [
			credits, ", ".join(PackedStringArray(lost_names))], COL_MARK)
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
