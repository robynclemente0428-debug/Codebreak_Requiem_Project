extends Node
## Runs a real Sweep in the Quarantine Yard, twice, with NO character slot loaded (nothing is saved):
## once letting the timer run out, once killing the drones. Then checks they stop once the Collector
## is dead, that enemy health follows the act, and the docked terminal. Writes sweep_test_results.txt.

const MAIN := "res://scenes/map/main.tscn"
const YARD := "res://scenes/map/town/act_3_quarantine_yard.tscn"
const RESULTS := "res://tools/act3/sweep_test_results.txt"

var _lines := PackedStringArray()
var _failed := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var main: Node = load(MAIN).instantiate()
	for n in main.find_children("*", "", true, false):
		if n is AreaManager:
			n.start_area = YARD
	reparent(get_tree().root)
	var old := get_tree().current_scene
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	if old != null and old != self:
		old.queue_free()
	while not (_player() != null and _am() != null and _am().current_area != null and _am().can_go()):
		await get_tree().process_frame
	await get_tree().create_timer(1.0, true).timeout
	var yard := _am().current_area
	var qm: QuestManager = _player().get("quests")
	var sweep := yard.get_node("YardSweep") as YardSweep
	_check("the yard has a sweep, not yet due", sweep != null and not sweep.is_due())
	_check("the yard's crates are found (%d)" % sweep._crates.size(), sweep._crates.size() == 6)
	sweep.load_time = 9.0
	sweep.mark_time = 6.0
	sweep.mark_range = 60.0

	# --- The timer runs out ---
	GameEvents.report(Waypoints.FINISH_DEED, "act3_registry")
	_check("a finished district makes one due", sweep.is_due())
	_check("the route waits for it (%s)" % Waypoints.breach_reason(get_tree()), Waypoints.breach_reason(get_tree()).contains("MARKERS"))
	_player().global_position = yard.get_node("Furniture/CargoE").global_position + Vector3(30, 0, 0)
	await _until(func() -> bool: return sweep.is_running() and not sweep._alive.is_empty(), 15.0)
	_check("the alarm sounds and drones come", sweep.is_running() and not sweep._alive.is_empty())
	var def_hp := 38.0 * (1.0 + 0.15 * (sweep.enemy_level - 1) + 0.006 * pow(sweep.enemy_level - 1, 2))
	var drone: Node3D = sweep._alive[0]
	var hp: float = drone.get("stats").get_stat(StatTypes.Stat.MAX_HEALTH)
	_check("a drone in Act III has double health (%.0f, level alone %.0f)" % [hp, def_hp], is_equal_approx(hp, def_hp * 2.0))
	await _until(func() -> bool: return not sweep._tagged().is_empty(), 12.0)
	_check("a drone tags a crate", not sweep._tagged().is_empty())
	var tagged_names := PackedStringArray()
	await _until(func() -> bool:
		if sweep.state != DockDefense.State.DONE:
			tagged_names.clear()
			for c in sweep._tagged():
				tagged_names.append(String((c["prop"] as Node).name))
		return sweep.state == DockDefense.State.DONE, 25.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("the timer ends it", sweep.state == DockDefense.State.DONE)
	_check("the tagged crates are deleted (%s)" % ", ".join(tagged_names),
		not tagged_names.is_empty() and yard.get_node_or_null("Furniture/" + tagged_names[0]) == null
		and qm.deed_count(YardSweep.LOST_DEED, tagged_names[0]) == 1)
	_check("the drones leave", sweep._alive.is_empty())
	_check("it's paid off", not sweep.is_due())
	_check("the rest of the crates are still there (%d)" % sweep._crates.size(), sweep._crates.size() == 6 - tagged_names.size() and sweep._crates.size() > 0)
	var left_after_first := sweep._crates.size()

	# --- The drones die in time ---
	sweep.state = DockDefense.State.WAITING
	sweep._restart_wait = 0.0
	sweep.load_time = 60.0
	sweep.wave_sizes = [2] as Array[int]
	GameEvents.report(Waypoints.FINISH_DEED, "act3_heap")
	_player().global_position = yard.get_node("Furniture/CargoE").global_position + Vector3(30, 0, 0) if yard.has_node("Furniture/CargoE") else _player().global_position
	await _until(func() -> bool: return sweep.is_running() and not sweep._alive.is_empty(), 10.0)
	sweep.mark_time = 3.0
	await _until(func() -> bool: return not sweep._tagged().is_empty(), 12.0)
	var had_tag := not sweep._tagged().is_empty()
	for e in sweep._alive.duplicate():
		if is_instance_valid(e):
			(e.get("health") as HealthComponent).take_damage(1000000.0, true)
	await _until(func() -> bool: return sweep.state == DockDefense.State.DONE, 8.0)
	_check("killing the drones ends it", sweep.state == DockDefense.State.DONE and had_tag)
	_check("and no crate is lost (%d)" % sweep._crates.size(), sweep._crates.size() == left_after_first)
	_check("and the tags come off", sweep._tagged().is_empty())

	# --- The Collector ---
	GameEvents.report(Waypoints.FINISH_DEED, "act3_heap")
	_check("another run owes another", sweep.is_due())
	GameEvents.report(ScriptBudget.BOSS_DEED, YardSweep.COLLECTOR)
	_check("the Collector's death ends them", not sweep.is_due())

	# --- Act scaling ---
	_check("Act I enemies aren't scaled", is_equal_approx(EnemySpawner.act_multiplier_of_scene("res://scenes/map/dungeon/act_1_spillway.tscn"), 1.0))
	_check("Act II is +50%", is_equal_approx(EnemySpawner.act_multiplier_of_scene("res://scenes/map/town/act_2_convoy.tscn"), 1.5))
	_check("Act III is +100%", is_equal_approx(EnemySpawner.act_multiplier_of_scene(YARD), 2.0))
	_check("the exam isn't scaled", is_equal_approx(EnemySpawner.act_multiplier_of_scene(ExamChamber.SCENE), 1.0))
	var armour_check := EnemySpawner.spawn_enemy(load("res://data/enemies/marker_drone.tres"), "normal", yard, _player().global_position + Vector3(25, 0.1, 0), 1, [])
	_check("armour doubles too (%.0f)" % armour_check.stats.get_stat(StatTypes.Stat.ARMOUR), is_equal_approx(armour_check.stats.get_stat(StatTypes.Stat.ARMOUR), 50.0))
	_check("and health starts full", is_equal_approx((armour_check.get("health") as HealthComponent).current_health, 76.0))
	armour_check.queue_free()

	# --- The convoy's terminal ---
	var convoy: Node = load("res://scenes/map/town/act_2_convoy.tscn").instantiate()
	var terminal := convoy.get_node("RouteTerminal") as RouteTerminal
	_check("the convoy's terminal knows it can dock", terminal.docks)
	_check("not docked yet", not Waypoints.is_docked(qm))
	qm.completed_ids.append("q04c_the_last_mile")
	_check("docked after The Last Mile", Waypoints.is_docked(qm))
	convoy.free()

	# --- Hex ---
	var hex := yard.get_node("TinkerHex") as ShopNPC
	var plain_max := 0
	hex.restock()
	for item in hex.stock:
		plain_max = maxi(plain_max, item.definition.item_level)
	_check("before Copied Stock, nothing above the act's level (%d), no copies" % plain_max,
		plain_max <= hex.stock_level and hex.stock.all(func(i: ItemInstance) -> bool: return not i.copied))
	qm.completed_ids.append("copied_stock")
	var tier_seen := false
	var copies := 0
	for _i in 20:
		hex.restock()
		copies = 0
		for item in hex.stock:
			tier_seen = tier_seen or item.definition.item_level > hex.stock_level
			if item.copied:
				copies += 1
	_check("after it, a new tier is on sale", tier_seen)
	_check("and %d COPY OF items" % copies, copies == hex.copy_slots)
	var copy_item: ItemInstance = hex.stock.filter(func(i: ItemInstance) -> bool: return i.copied)[0]
	_check("named so (%s)" % copy_item.get_display_name(), copy_item.get_display_name().begins_with("COPY OF"))
	var saved_copy := ItemInstance.from_dict(copy_item.to_dict())
	_check("and it saves", saved_copy.copied)
	var original := ItemInstance.from_dict(copy_item.to_dict())
	original.copied = false
	_check("a copy is half price", ItemPricing.value_of(copy_item) == maxi(roundi(ItemPricing.value_of(original) * 0.5), 1)
		or abs(ItemPricing.value_of(copy_item) - ItemPricing.value_of(original) * 0.5) <= 1.0)

	# --- The flat damage modifiers ---
	var flat: AffixDefinition = load("res://data/affixes/attack_damage/damage_flat_1.tres")
	_check("flat damage is halved", is_equal_approx(flat.added_min_low, 3.0) and is_equal_approx(flat.added_max_high, 10.0))

	_lines.append("%s" % ("ALL PASSED" if _failed == 0 else "%d FAILED" % _failed))
	var f := FileAccess.open(RESULTS, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\nDONE\n")


func _process(_delta: float) -> void:
	if _player() != null:
		_player().get("health").heal(100000.0)


func _check(what: String, ok: bool) -> void:
	_lines.append("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed += 1


func _until(cond: Callable, timeout: float) -> void:
	var left := timeout
	while left > 0.0 and not cond.call():
		await get_tree().process_frame
		left -= get_process_delta_time()


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


func _am() -> AreaManager:
	return get_tree().get_first_node_in_group("area_manager") as AreaManager
