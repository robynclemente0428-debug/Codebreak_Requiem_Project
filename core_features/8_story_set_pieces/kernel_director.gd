class_name KernelDirector
extends Node

const SPOT_RANGE := 14.0
const SCAN_EVERY := 0.25
const HISTORY := 5.0
const DRAIN_GAP := 8.0
const ENTRY_BARRIER := 0.2
const ENTRY_BARRIER_SECONDS := 8.0

var _player: Node3D
var _started := false
var _scan := 0.0
var _history: Array = []
var _rolled := false
var _drained_at := -100.0
var _strip: KernelStrip
var _scheduling := false
var _scheduled := ""
var _schedule_left := 0.0
var _schedule_index := -1
var _mine := false
var _in_act5 := false
var _card: PullRequestCard


func _ready() -> void:
	GameEvents.happened.connect(_on_event)
	Coop.event_register("kernel", self)
	_begin.call_deferred()


func _exit_tree() -> void:
	if GameEvents.happened.is_connected(_on_event):
		GameEvents.happened.disconnect(_on_event)
	if is_instance_valid(_strip):
		_strip.queue_free()
	if is_instance_valid(_card):
		_card.queue_free()
	_set_answering(false)


func _begin() -> void:
	for i in 120:
		_player = get_tree().get_first_node_in_group("players") as Node3D
		if _player != null and _player.is_inside_tree():
			break
		await get_tree().process_frame
	var qm := _qm()
	if _player == null:
		queue_free()
		return
	_in_act5 = KernelScript.is_zone(get_parent().scene_file_path)
	_mine = KernelScript.unlocked(qm) and (_in_act5 or Endings.runs_everywhere(qm))
	if not _mine:
		if Coop.in_game and Coop.is_host():
			_started = true
		else:
			queue_free()
		return
	_build_strip()
	var zone_line := KernelScript.null_line_of(get_parent().scene_file_path)
	if zone_line != "" and KernelScript.answer_of(qm, zone_line) == "" and not Coop.visiting:
		if not KernelScript.is_inserted(qm, zone_line):
			GameEvents.report(KernelScript.NULL_DEED, zone_line)
		await get_tree().create_timer(0.6).timeout
		if not is_instance_valid(_player) or not is_inside_tree() or KernelScript.answer_of(qm, zone_line) != "":
			return
		var ids: Array = KernelScript.NULL_LINES.keys()
		var w := Waypoints.for_scene(get_parent().scene_file_path)
		_card = PullRequestCard.open(get_tree(), zone_line, w.display_name if w != null else "",
			ids.find(zone_line) + 1, ids.size(), _lines())
		_set_answering(true)
		var reply: Array = await _card.answered
		_set_answering(false)
		answer(zone_line, str(reply[0]), str(reply[1]))
	if "barrier_on_entry" in _lines():
		var hp := _hp()
		if hp != null:
			hp.add_barrier(_max_life() * ENTRY_BARRIER, ENTRY_BARRIER_SECONDS)
			_pop("barrier(20%)", KernelScript.COL_ROOT)
	_scheduling = get_parent().scene_file_path.get_file().get_basename() == KernelScript.SCHEDULE_ZONE
	if _scheduling:
		_next_schedule()
	_started = true


func _set_answering(on: bool) -> void:
	Coop.answering = on and Coop.in_game
	var hp := _hp()
	if hp != null:
		hp.untouchable = on and Coop.in_game


func _process(delta: float) -> void:
	if not _started or not is_instance_valid(_player):
		return
	if not _mine:
		_scan -= delta
		if _scan <= 0.0:
			_scan = SCAN_EVERY
			_scan_enemies()
		return
	if _scheduling:
		_schedule_left -= delta
		if _schedule_left <= 0.0:
			_next_schedule()
	_update_strip()
	var hp := _hp()
	if hp == null or hp.current_health <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_history.append([now, hp.current_health])
	while not _history.is_empty() and now - float(_history[0][0]) > HISTORY:
		_history.pop_front()
	var top := _max_life()
	var frac := hp.current_health / top if top > 0.0 else 1.0
	if frac < 0.3 and not _rolled and "rollback" in _lines():
		var best := hp.current_health
		for h in _history:
			best = maxf(best, float(h[1]))
		if best > hp.current_health:
			_rolled = true
			hp.heal(best - hp.current_health)
			_pop("stack.rollback(5s)", KernelScript.COL_ROOT)
	if frac < 0.5 and now - _drained_at >= DRAIN_GAP and "null_drain" in _running():
		var mana := _player.get("mana") as ManaComponent
		if mana != null and mana.current_mana > 0.0:
			_drained_at = now
			var take := minf(mana.get_max_mana() * 0.25, mana.current_mana)
			mana.spend(take)
			_pop("mana.drain(25%%)  -%d" % roundi(take), KernelScript.COL_NULL)
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_EVERY
		_scan_enemies()


func _scan_enemies() -> void:
	var at := _player.global_position
	var lines := _lines() if _mine else []
	var real := not Coop.in_game or Coop.is_host()
	var party := Coop.party_kernel(_player if _mine else null, not _in_act5)
	var enemy_lines: Array = party.lines
	var enemy_null: Array = party.merged.duplicate()
	if _scheduled != "" and not _scheduled in enemy_null:
		enemy_null.append(_scheduled)
	var players := get_tree().get_nodes_in_group("players")
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var body := e as Node3D
		if body == null or SkillBehavior.is_dead(body):
			continue
		if _mine and not body.has_meta(&"kernel_spotted") and body.global_position.distance_to(at) <= SPOT_RANGE:
			body.set_meta(&"kernel_spotted", true)
			_spotted(body, lines)
		if not body.has_meta(&"kernel_marked") and _near_any(body, players):
			body.set_meta(&"kernel_marked", true)
			_mark(body, enemy_lines, enemy_null, real)


func _near_any(body: Node3D, players: Array) -> bool:
	for p in players:
		if is_instance_valid(p) and (p as Node3D).global_position.distance_to(body.global_position) <= SPOT_RANGE:
			return true
	return false


func _spotted(e: Node3D, lines: Array) -> void:
	if "registry_add" in lines:
		var sk := _player.get("skills") as SkillComponent
		var key: Variant = ScriptRegisters.entry_key(e)
		if sk != null and key != null:
			for s in sk.sockets:
				if s.program != null:
					s.program.state().registers[key] = true


func _mark(e: Node3D, lines: Array, running: Array, real: bool) -> void:
	if "defragment" in lines and "traits" in e:
		for t in (e.get("traits") as Array).duplicate():
			if t is FragmentLock:
				(e.get("traits") as Array).erase(t)
				(t as Node).queue_free()
	if not real:
		return
	var stats := e.get("stats") as StatComponent
	var hp := e.get("health") as HealthComponent
	if stats != null:
		if "weaken" in lines:
			_mod(stats, StatTypes.Stat.MAX_HEALTH, -0.15, "kernel_weaken")
		if "slow" in lines:
			_mod(stats, StatTypes.Stat.MOVE_SPEED, -0.25, "kernel_slow")
		if "null_armour" in running:
			_mod(stats, StatTypes.Stat.ARMOUR, 0.4, "kernel_null_armour")
		if "null_regrow" in running:
			var before := stats.get_stat(StatTypes.Stat.MAX_HEALTH)
			_mod(stats, StatTypes.Stat.MAX_HEALTH, 0.2, "kernel_null_regrow")
			if hp != null:
				hp.heal(stats.get_stat(StatTypes.Stat.MAX_HEALTH) - before)
	if hp != null and stats != null:
		hp.current_health = minf(hp.current_health, stats.get_stat(StatTypes.Stat.MAX_HEALTH))


static func _mod(stats: StatComponent, stat: int, value: float, source: String) -> void:
	var m := Modifier.new()
	m.stat = stat
	m.op = Modifier.ModOp.PERCENT_MULT
	m.value = value
	m.source_id = source
	stats.add_modifier(m)


func _on_event(kind: String, _target: String, _amount: int) -> void:
	if kind != "kill" or not _started or not is_instance_valid(_player):
		return
	var lines := _lines()
	if "heal_on_kill" in lines:
		var hp := _hp()
		if hp != null and hp.current_health > 0.0:
			hp.heal(_max_life() * 0.04)
	if "mana_on_kill" in lines:
		var mana := _player.get("mana") as ManaComponent
		if mana != null:
			mana.restore(mana.get_max_mana() * 0.10)
	if "null_swap" in _running():
		var sk := _player.get("skills") as SkillComponent
		if sk != null:
			for s in sk.sockets:
				if s.program != null:
					s.program.state().registers.clear()
			_pop("registry.clear()", KernelScript.COL_NULL)


func answer(null_id: String, how: String, pick := "") -> void:
	var sk := _player.get("skills") as SkillComponent if is_instance_valid(_player) else null
	if sk == null:
		return
	KernelScript.answer(_qm(), sk.kernel, null_id, how, pick)
	Coop.kernel_changed()
	match how:
		"merge":
			QuestItems.toast(get_tree(), "MERGED: the Null's line runs\nYours too: %s" % KernelScript.code_of(
				str(KernelScript.NULL_LINES[null_id]["gift"])), KernelScript.COL_NULL)
		"overwrite":
			QuestItems.toast(get_tree(), "OVERWRITTEN: your line runs instead\n%s" % KernelScript.code_of(pick),
				KernelScript.COL_ROOT)
		"terminate":
			QuestItems.toast(get_tree(), "TERMINATED: the process fights its shutdown", KernelScript.COL_TERMINATE)
			if Coop.in_game and not Coop.is_host():
				Coop.event_send("kernel", "defend", [_player.global_position])
			else:
				_spawn_defender(_player.global_position)
	_update_strip()


func coop_message(what: String, args: Array, _from: int) -> void:
	if what == "defend" and Coop.is_host() and args.size() == 1 and args[0] is Vector3 and (args[0] as Vector3).is_finite():
		_spawn_defender(args[0])


func _spawn_defender(near: Vector3) -> Node3D:
	var d := get_parent()
	var director = d.get("director")
	var pool: Array = director.dungeon_theme.enemy_pool if director != null and director.get("dungeon_theme") != null else []
	var root := d.get_node_or_null("Enemies")
	var def := EnemyDefinition.pick(pool, "champion") if not pool.is_empty() else null
	if def == null or root == null or not is_instance_valid(_player):
		return null
	var level := int(d.get("dungeon_level")) if d.get("dungeon_level") != null else 1
	var at := near + Vector3(9.0, 0.0, 0.0).rotated(Vector3.UP, randf() * TAU)
	var nav := _player.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav) > 0:
		at = NavigationServer3D.map_get_closest_point(nav, at)
	var e := EnemySpawner.spawn_enemy(def, "champion", root, at + Vector3.UP * 0.1, level, null)
	if e == null:
		return null
	e.set_meta(&"kernel_defender", true)
	if e.get("ai") != null:
		e.ai.aggro_range = SPOT_RANGE * 3.0
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers:
		numbers.track(e.health)
	return e


func _running() -> Array:
	var out := KernelScript.null_running(_qm())
	if _scheduled != "" and not (_scheduled in out):
		out.append(_scheduled)
	return out


func _next_schedule() -> void:
	var qm := _qm()
	var ids: Array = KernelScript.NULL_LINES.keys().filter(func(id: String) -> bool:
		var a := KernelScript.answer_of(qm, id)
		return a != "" and a != "merge" and Endings.current(qm) != "overwrite")
	if ids.is_empty():
		_scheduled = ""
		_schedule_left = KernelScript.SCHEDULE_SECONDS
		return
	_schedule_index = (_schedule_index + 1) % ids.size()
	_scheduled = ids[_schedule_index]
	_schedule_left = KernelScript.SCHEDULE_SECONDS
	QuestItems.toast(get_tree(), "THE NULL SCHEDULED A LINE (%ds)
%s
%s" % [roundi(KernelScript.SCHEDULE_SECONDS),
		KernelScript.code_of(_scheduled), KernelScript.NULL_LINES[_scheduled]["tip"]], KernelScript.COL_NULL)


func _build_strip() -> void:
	_strip = KernelStrip.new()
	_strip.name = "KernelStrip"
	var hud := get_tree().root.find_child("StimLayer", true, false)
	if hud != null:
		hud.add_child(_strip)
	else:
		add_child(_strip)
	_update_strip()


func _update_strip() -> void:
	if not is_instance_valid(_strip):
		return
	var qm := _qm()
	var lines := _lines()
	var sched := KernelScript.code_of(_scheduled) if _scheduling and _scheduled != "" else ""
	var answers: Array = KernelScript.NULL_LINES.keys().map(func(id: String) -> String: return KernelScript.answer_of(qm, id))
	_strip.show_state(answers, KernelScript.lean(qm), lines.size(), KernelScript.null_running(qm).size(),
		sched, _schedule_left, Coop.party_answers())


func _qm() -> QuestManager:
	return _player.get("quests") as QuestManager if is_instance_valid(_player) else null


func _lines() -> Array:
	var sk := _player.get("skills") as SkillComponent if is_instance_valid(_player) else null
	return Array(sk.kernel) if sk != null else []


func _hp() -> HealthComponent:
	return _player.get("health") as HealthComponent if is_instance_valid(_player) else null


func _max_life() -> float:
	var stats := _player.get("stats") as StatComponent if is_instance_valid(_player) else null
	return stats.get_stat(StatTypes.Stat.MAX_HEALTH) if stats != null else 0.0


func _pop(text: String, col: Color) -> void:
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers != null and is_instance_valid(_player):
		numbers.pop_text(_player.global_position + Vector3.UP * 2.4, text, col, 1.0, 1.6)
