class_name KernelDirector
extends Node
## Runs kernel.gd (KernelScript) in an Act V zone: Dungeon adds one when its scene is one of
## KernelScript.ZONES. Your root lines and the Null's lines both run here, on the zone itself:
##   area_entered       once, when you arrive
##   enemy_spotted      once per enemy, the first time it's within SPOT_RANGE of you (summons too)
##   enemy_killed       each kill (the populator's "kill" event)
##   life_below(n%)     while your life is under it (rollback: once per zone; the Null's drain:
##                      every DRAIN_GAP seconds at most)
## The first time you enter a zone, the Null writes its line into kernel.gd (a kernel_null deed),
## and a strip at the top of the screen shows CORE STABILITY while you're here.

const SPOT_RANGE := 14.0
const SCAN_EVERY := 0.25
const HISTORY := 5.0
const DRAIN_GAP := 8.0
const ENTRY_BARRIER := 0.2
const ENTRY_BARRIER_SECONDS := 8.0

var _player: Node3D
var _started := false
var _scan := 0.0
var _history: Array = []                 # [[seconds, life], ...] for stack.rollback
var _rolled := false
var _drained_at := -100.0
var _strip: PanelContainer
var _strip_label: Label
var _scheduling := false                 # the Scheduler: the Null runs one of its lines at a time
var _scheduled := ""
var _schedule_left := 0.0
var _schedule_index := -1


func _ready() -> void:
	GameEvents.happened.connect(_on_event)
	_begin.call_deferred()


func _exit_tree() -> void:
	if GameEvents.happened.is_connected(_on_event):
		GameEvents.happened.disconnect(_on_event)
	if is_instance_valid(_strip):
		_strip.queue_free()


func _begin() -> void:
	for i in 120:                           # the player is placed a few frames after the area loads
		_player = get_tree().get_first_node_in_group("players") as Node3D
		if _player != null and _player.is_inside_tree():
			break
		await get_tree().process_frame
	var qm := _qm()
	if _player == null or not KernelScript.unlocked(qm):
		return
	var zone_line := KernelScript.null_line_of(get_parent().scene_file_path)
	if zone_line != "" and not KernelScript.is_inserted(qm, zone_line):
		GameEvents.report(KernelScript.NULL_DEED, zone_line)
		QuestItems.toast(get_tree(), "THE NULL WROTE TO %s\n%s\n%s Overwrite it in %s for %d root points." % [
			KernelScript.FILE_NAME, KernelScript.code_of(zone_line), KernelScript.NULL_LINES[zone_line]["tip"],
			KernelScript.FILE_NAME, KernelScript.OVERWRITE_COST], KernelScript.COL_NULL)
	if "barrier_on_entry" in _lines():
		var hp := _hp()
		if hp != null:
			hp.add_barrier(_max_life() * ENTRY_BARRIER, ENTRY_BARRIER_SECONDS)
			_pop("barrier(20%)", KernelScript.COL_ROOT)
	_scheduling = get_parent().scene_file_path.get_file().get_basename() == KernelScript.SCHEDULE_ZONE
	if _scheduling:
		_next_schedule()
	_build_strip()
	_started = true


func _process(delta: float) -> void:
	if not _started or not is_instance_valid(_player):
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
			var take := minf(mana.get_max_mana() * 0.25 * _scale(), mana.current_mana)
			mana.spend(take)
			_pop("mana.drain(25%%)  -%d" % roundi(take), KernelScript.COL_NULL)
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_EVERY
		_scan_enemies()


# ---------- enemy_spotted ----------
func _scan_enemies() -> void:
	var at := _player.global_position
	var lines := _lines()
	var running := _running()
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var body := e as Node3D
		if body == null or body.has_meta(&"kernel_spotted") or SkillBehavior.is_dead(body):
			continue
		if body.global_position.distance_to(at) > SPOT_RANGE:
			continue
		body.set_meta(&"kernel_spotted", true)
		_spotted(body, lines, running)


func _spotted(e: Node3D, lines: Array, running: Array) -> void:
	var stats := e.get("stats") as StatComponent
	var hp := e.get("health") as HealthComponent
	if "registry_add" in lines:
		var sk := _player.get("skills") as SkillComponent
		var key: Variant = ScriptRegisters.entry_key(e)
		if sk != null and key != null:
			for s in sk.sockets:
				if s.program != null:
					s.program.state().registers[key] = true
	if "defragment" in lines and "traits" in e:
		for t in (e.get("traits") as Array).duplicate():
			if t is FragmentLock:
				(e.get("traits") as Array).erase(t)
				(t as Node).queue_free()
	if stats != null:
		if "weaken" in lines:
			_mod(stats, StatTypes.Stat.MAX_HEALTH, -0.15, "kernel_weaken")
		if "slow" in lines:
			_mod(stats, StatTypes.Stat.MOVE_SPEED, -0.25, "kernel_slow")
		if "null_armour" in running:
			_mod(stats, StatTypes.Stat.ARMOUR, 0.4 * _scale(), "kernel_null_armour")
		if "null_regrow" in running:
			var before := stats.get_stat(StatTypes.Stat.MAX_HEALTH)
			_mod(stats, StatTypes.Stat.MAX_HEALTH, 0.2 * _scale(), "kernel_null_regrow")
			if hp != null:
				hp.heal(stats.get_stat(StatTypes.Stat.MAX_HEALTH) - before)
	if hp != null and stats != null:                # less maximum life: what's left can't be over it
		hp.current_health = minf(hp.current_health, stats.get_stat(StatTypes.Stat.MAX_HEALTH))


static func _mod(stats: StatComponent, stat: int, value: float, source: String) -> void:
	var m := Modifier.new()
	m.stat = stat
	m.op = Modifier.ModOp.PERCENT_MULT
	m.value = value
	m.source_id = source
	stats.add_modifier(m)


# ---------- enemy_killed ----------
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
	if "null_swap" in _running():                 # the Page File: every kill empties your registries
		var sk := _player.get("skills") as SkillComponent
		if sk != null:
			for s in sk.sockets:
				if s.program != null:
					s.program.state().registers.clear()
			_pop("registry.clear()", KernelScript.COL_NULL)


# ---------- THE SCHEDULER ----------
## The Null's lines that run here now: the ones it wrote, and the one it has scheduled.
func _running() -> Array:
	var out := KernelScript.null_running(_qm())
	if _scheduled != "" and not (_scheduled in out):
		out.append(_scheduled)
	return out


func _next_schedule() -> void:
	var ids: Array = KernelScript.NULL_LINES.keys()
	_schedule_index = (_schedule_index + 1) % ids.size()
	_scheduled = ids[_schedule_index]
	_schedule_left = KernelScript.SCHEDULE_SECONDS
	QuestItems.toast(get_tree(), "THE NULL SCHEDULED A LINE (%ds)
%s
%s" % [roundi(KernelScript.SCHEDULE_SECONDS),
		KernelScript.code_of(_scheduled), KernelScript.NULL_LINES[_scheduled]["tip"]], KernelScript.COL_NULL)


# ---------- THE STRIP ----------
## kernel.gd  //  CORE STABILITY 60%  //  1 NULL LINE: top of the screen, on the HUD.
func _build_strip() -> void:
	_strip = PanelContainer.new()
	_strip.name = "KernelStrip"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.06, 0.72)
	sb.border_color = Color(KernelScript.COL_ROOT, 0.6)
	sb.border_width_bottom = 2
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	_strip.add_theme_stylebox_override("panel", sb)
	_strip_label = Label.new()
	_strip_label.add_theme_font_size_override("font_size", 15)
	_strip_label.add_theme_color_override("font_color", KernelScript.COL_ROOT)
	_strip.add_child(_strip_label)
	var hud := get_tree().root.find_child("StimLayer", true, false)
	if hud != null:
		hud.add_child(_strip)
	else:
		add_child(_strip)
	_strip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_strip.position.y = 6.0
	_update_strip()


func _update_strip() -> void:
	if not is_instance_valid(_strip_label):
		return
	var qm := _qm()
	var lines := _lines()
	var running := KernelScript.null_running(qm).size()
	var text := "%s  //  CORE STABILITY %d%%  //  %d ROOT LINE%s" % [KernelScript.FILE_NAME,
		roundi(KernelScript.stability(lines, qm) * 100.0), lines.size(), "" if lines.size() == 1 else "S"]
	if running > 0:
		text += "  //  %d NULL LINE%s x%.1f" % [running, "" if running == 1 else "S", _scale()]
	if _scheduling and _scheduled != "":
		text += "  //  SCHEDULED: %s (%ds)" % [KernelScript.NULL_LINES[_scheduled]["code"], ceili(_schedule_left)]
	if _strip_label.text != text:
		_strip_label.text = text
		_strip.reset_size()


# ---------- HELPERS ----------
func _qm() -> QuestManager:
	return _player.get("quests") as QuestManager if is_instance_valid(_player) else null


func _lines() -> Array:
	var sk := _player.get("skills") as SkillComponent if is_instance_valid(_player) else null
	return Array(sk.kernel) if sk != null else []


func _scale() -> float:
	return KernelScript.null_scale(_lines(), _qm())


func _hp() -> HealthComponent:
	return _player.get("health") as HealthComponent if is_instance_valid(_player) else null


func _max_life() -> float:
	var stats := _player.get("stats") as StatComponent if is_instance_valid(_player) else null
	return stats.get_stat(StatTypes.Stat.MAX_HEALTH) if stats != null else 0.0


func _pop(text: String, col: Color) -> void:
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers != null and is_instance_valid(_player):
		numbers.pop_text(_player.global_position + Vector3.UP * 2.4, text, col, 1.0, 1.6)
