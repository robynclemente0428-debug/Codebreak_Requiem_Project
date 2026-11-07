extends Node
## Tests Act III's districts, locks and quests. Run this scene from the editor (F6). Boots main.tscn
## in the Quarantine Yard with NO character slot loaded (nothing is saved).
##   1. every quest loads, with its prerequisites in place, and the districts open in order
##   2. every district generates, with a way from its entrance to its boss and its exit
##   3. REFCOUNT, DIFF and GENERATIONS do what their quests say, with real hits
##   4. the Strategist exam: refuses a set with no script, fails one set, passes three
##   5. the whole quest chain turns in, up to Root Access
## Prints [ACT3] lines; "ALL PASSED" at the end, or the FAILs.

const MAIN := "res://scenes/map/main.tscn"
const YARD := "res://scenes/map/town/act_3_quarantine_yard.tscn"
const DISTRICTS := {
	"act3_registry": "", "act3_heap": "the_leak", "act3_mirror_dock": "the_mimic",
	"act3_dangling_quarter": "", "act3_mark_yards": "", "act3_sweep": "the_collector",
}
const QUESTS := ["q05_the_leak", "q06_the_mimic", "exam_strategist", "q06b_the_collector",
		"q06c_root_access", "memory_shards", "copied_stock"]

## Also writes the [ACT3] lines here, without the rest of the game's log. Empty = no file.
@export var result_file := "res://tools/act3/act3_test_results.txt"

var _fails := 0
var _keep_alive := false
var _logged := false


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
	await _until(_settled.bind(YARD), 30.0)
	_keep_alive = true
	var qm := _qm()
	_check("booted in the yard", _player() != null and qm != null)
	if qm == null:
		return _done()

	await _quests_and_gates(qm)
	await _districts()
	await _refcount()
	await _diff()
	await _generations()
	await _variables()
	await _exam(qm)
	await _chain(qm)
	_done()


# ---------- 1. QUESTS AND GATES ----------
func _quests_and_gates(qm: QuestManager) -> void:
	for id in QUESTS:
		_check("quest %s loads" % id, qm.get_def(id) != null)
	_check("q07 waits for Root Access", "q06c_root_access" in qm.get_def("q07_null_weaver_prime").prerequisite_quest_ids)
	var act := Waypoints.act_of_scene(YARD)
	for id in ["act3_registry", "act3_heap", "act3_mirror_dock", "act3_dangling_quarter", "act3_mark_yards", "act3_sweep"]:
		_check("%s starts shut" % id, not Waypoints.route_key_ok(act.find(id)))
	_complete(qm, "q04c_the_last_mile")
	_check("Sudo's exam can start on docking", qm.can_start(qm.get_def("exam_strategist")))
	_complete(qm, "exam_strategist")
	_check("the Registry opens after the exam", Waypoints.route_open(act.find("act3_registry")))
	_check("the Heap opens after the exam", Waypoints.route_open(act.find("act3_heap")))
	_check("Mirror Dock still shut", not Waypoints.route_open(act.find("act3_mirror_dock")))
	_complete(qm, "q05_the_leak")
	_check("Mirror Dock opens after The Leak", Waypoints.route_open(act.find("act3_mirror_dock")))
	_check("the Dangling Quarter opens after The Leak", Waypoints.route_open(act.find("act3_dangling_quarter")))
	_check("Mark Yards still shut", not Waypoints.route_open(act.find("act3_mark_yards")))
	_check("the Sweep still shut", not Waypoints.route_open(act.find("act3_sweep")))
	_complete(qm, "q06_the_mimic")
	_check("Mark Yards open after the Mimic", Waypoints.route_open(act.find("act3_mark_yards")))
	_check("the Sweep opens after the Mimic", Waypoints.route_open(act.find("act3_sweep")))
	_check("the District Gate stands in the yard", _route_terminal() != null)
	var why := Waypoints.route_blocked_reason(act.find("act3_registry"), get_tree())
	_check("the District Gate can send you (%s)" % why, why == "")
	# Back to the start of the act for the chain at the end
	for id in ["q05_the_leak", "exam_strategist", "q06_the_mimic"]:
		qm.completed_ids.erase(id)


func _route_terminal() -> Node:
	for n in _am().current_area.find_children("*", "", true, false):
		if n is RouteTerminal:
			return n
	return null


# ---------- 2. DISTRICTS ----------
func _districts() -> void:
	var act := Waypoints.act_of_scene(YARD)
	for id in DISTRICTS:
		var w: Waypoint = act.find(id)
		_am().go_to(w.scene, w.spawn_id, w.dungeon_level)
		await _until(_settled.bind(w.scene), 60.0)
		await _wait(0.5)
		_check("%s generates" % id, _settled(w.scene))
		var area := _am().current_area
		var from: Vector3 = _player().global_position
		var boss_id: String = DISTRICTS[id]
		if boss_id != "":
			var boss := _enemy(boss_id)
			_check("%s has %s" % [id, boss_id], boss != null)
			if boss != null:
				_check("%s: a path reaches the boss" % id, _reaches(from, boss.global_position))
		var out := _exit_portal(area)
		_check("%s has its exit" % id, out != null)
		if out != null:
			_check("%s: a path reaches the exit" % id, _reaches(from, out.global_position))
		var enemies := get_tree().get_nodes_in_group("enemies").size()
		_check("%s has enemies (%d)" % [id, enemies], enemies > 0)
		if id == "act3_mirror_dock":
			var carriers := 0
			for e in get_tree().get_nodes_in_group("enemies"):
				if str(e.get_meta(&"enemy_id", "")) == "mirror_husk":
					carriers += 1
			_check("Mirror Dock has its 4 crate carriers (%d)" % carriers, carriers >= 4)
		_log("SHOT %s" % id)
		await _wait(0.2)


func _exit_portal(area: Node) -> Portal:
	for p in area.find_children("*", "Portal", true, false):
		if (p as Portal).clears_stop != "":
			return p
	return null


func _reaches(from: Vector3, to: Vector3) -> bool:
	var map := _player().get_world_3d().navigation_map
	var a := NavigationServer3D.map_get_closest_point(map, from)
	var b := NavigationServer3D.map_get_closest_point(map, to)
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	return not path.is_empty() and path[path.size() - 1].distance_to(b) < 2.0


# ---------- 3. LOCKS ----------
## Puts the player by a boss in a district, with everything else out of the way.
func _at_boss(id: String, boss_id: String) -> Node3D:
	var w: Waypoint = Waypoints.act_of_scene(YARD).find(id)
	_am().go_to(w.scene, w.spawn_id, w.dungeon_level)
	await _until(_settled.bind(w.scene), 60.0)
	await _wait(0.5)
	var boss := _enemy(boss_id)
	if boss == null:
		_check("%s is there" % boss_id, false)
		return null
	_check("%s rolled modifiers: %s" % [boss_id, boss.display_name], not boss.get("modifiers").is_empty())
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != boss:
			e.process_mode = Node.PROCESS_MODE_DISABLED
	var ai := boss.get("ai") as Node
	if ai != null:
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	_player().global_position = boss.global_position + Vector3(0, 0, 5)
	return boss


func _lock(boss: Node3D, script_class: Variant) -> Node:
	for t in boss.traits:
		if is_instance_of(t, script_class):
			return t
	return null


## A real cast of a skill gem by the player, as a script would run it.
func _cast(gem_id: String, fired: Array = []) -> SkillCast:
	var skill := SkillInstance.new()
	skill.gem = load("res://data/skill_gems/%s.tres" % gem_id)
	skill.rebuild()
	var p := _player()
	var cast := SkillCast.new(p, skill, p.get("stats"), skill.get_behavior())
	if not fired.is_empty():
		cast.extra[ProgramSupport.FIRED_KEY] = fired
	return cast


func _refcount() -> void:
	var boss: Node3D = await _at_boss("act3_heap", "the_leak")
	if boss == null:
		return
	var lock: RefcountLock = _lock(boss, RefcountLock)
	_check("The Leak has REFCOUNT", lock != null)
	await _until(func() -> bool: return lock.refcount() > 0, 3.0)
	_check("it splits when you come close (%d)" % lock.refcount(), lock.refcount() == lock.blobs_per_split)
	for b in lock._alive():
		b.process_mode = Node.PROCESS_MODE_DISABLED
	var hp: HealthComponent = boss.get("health")
	var before := hp.current_health
	var hit := _cast("strike").hit(boss)
	_check("the core is locked while blobs live", hit.absorbed and hp.current_health >= before)

	var blobs: Array = lock._alive().duplicate()
	blobs[0].health.current_health = 1.0
	_cast("strike").hit(blobs[0])
	await get_tree().process_frame
	await get_tree().process_frame
	_check("a lone kill doesn't leak until its window closes", lock.leaked_count == 0)
	await _wait(lock.free_window + 0.2)
	_check("a lone kill leaks (%d leaked)" % lock.leaked_count, lock.leaked_count == 1)
	_check("a leaked blob still counts (%d)" % lock.refcount(), lock.refcount() == lock.blobs_per_split)

	var alive: Array = lock._alive().duplicate()
	for i in 3:                                  # three separate single-target hits, no AREA tag
		alive[i].health.current_health = 1.0
		_cast("strike").hit(alive[i])
		await _wait(0.3)
	_check("three quick single-target kills free them (%d freed)" % lock.freed_count, lock.freed_count == 3)

	await _wait(lock.leak_delay + 0.5)
	_check("the leaked one came back (%d alive)" % lock._alive().size(), lock._alive().size() == 2)
	for b in lock._alive():
		b.process_mode = Node.PROCESS_MODE_DISABLED
	var last: Array = lock._alive().duplicate()
	var both := _cast("slam")
	for b in last:
		b.health.current_health = 1.0
		both.hit(b)
	await _until(func() -> bool: return lock.is_open(), 1.0)
	_check("an AREA cast on the last two frees them, and refcount 0 opens the port", lock.is_open() and lock.refcount() == 0)
	before = hp.current_health
	_cast("strike").hit(boss)
	_check("the open port takes damage (%.0f -> %.0f)" % [before, hp.current_health], hp.current_health < before)
	hp.take_damage(hp.current_health * 0.3, true)
	_cast("strike").hit(boss)
	_check("losing a share of life splits it again (%d)" % lock.refcount(), lock.refcount() > 0 and not lock.is_open())
	var last_blobs: Array = lock._alive().duplicate()
	hp.take_damage(hp.current_health + 1.0, true)
	await _wait(0.5)
	_check("its death takes the blobs too (%d blobs)" % last_blobs.size(), last_blobs.all(func(e) -> bool: return not is_instance_valid(e) or SkillBehavior.is_dead(e)))
	_check("it drops the Guild shard's pick-up, or it's dead at least", SkillBehavior.is_dead(boss) or not is_instance_valid(boss))


func _diff() -> void:
	var boss: Node3D = await _at_boss("act3_mirror_dock", "the_mimic")
	if boss == null:
		return
	var lock: DiffLock = _lock(boss, DiffLock)
	_check("The Mimic has DIFF", lock != null)
	var hp: HealthComponent = boss.get("health")
	var before := hp.current_health
	_check("no rule fired: no diff", _cast("strike").hit(boss).absorbed)
	var first := _cast("strike", ["enemies_nearby"])
	_check("a rule fires: it lands", not first.hit(boss).absorbed and hp.current_health < before)
	_check("the same cast's next hit lands too", not first.hit(boss).absorbed)
	_check("the same rule again: no diff", _cast("strike", ["enemies_nearby"]).hit(boss).absorbed)
	_check("swapping skills with the same rule: no diff", _cast("slam", ["enemies_nearby"]).hit(boss).absorbed)
	before = hp.current_health
	_check("a different rule lands", not _cast("strike", ["every_nth_cast"]).hit(boss).absorbed and hp.current_health < before)
	_check("back to the first rule lands", not _cast("strike", ["enemies_nearby"]).hit(boss).absorbed)
	# A toggle: a script that changes its own pattern with a variable
	var toggle := _scripted("strike", _program([["x", "<", 1], ["x", "+=", 1]], [["x", ">=", 1], ["x", "=", 0]]))
	_check("a toggle compiles (%s)" % "; ".join(toggle.program_validation.errors), toggle.program_validation.valid)
	for i in 4:
		var c := _fire(toggle)
		_check("the toggle's cast %d gets through DIFF %s" % [i + 1, ProgramSupport.fired_conditions(c)], not c.hit(boss).absorbed)
	var caster := lock._enemy_skills()
	_check("it copied the skill that hit it", caster != null and caster._skills.size() == 1 and caster._skills[0].gem.id == "slam" or caster._skills[0].gem.id == "strike")
	hp.take_damage(hp.current_health + 1.0, true)
	await _wait(0.3)
	_check("it goes down", not is_instance_valid(boss) or SkillBehavior.is_dead(boss))


func _generations() -> void:
	Ranks.lent = PackedStringArray(["sets"])
	var skills: SkillComponent = _player().get("skills")
	skills.refresh_rank()
	var boss: Node3D = await _at_boss("act3_sweep", "the_collector")
	if boss == null:
		return
	var lock: GenerationsLock = _lock(boss, GenerationsLock)
	_check("The Collector has GENERATIONS", lock != null)
	await _until(func() -> bool: return lock.generation() == 0, 2.0)
	_check("Gen 0 starts", lock.generation() == 0 and lock.open_set() == 0)
	var hp: HealthComponent = boss.get("health")
	var full: float = lock.max_health()
	hp.current_health = full * 0.9
	skills.switch_script_set(1, true)
	var before := hp.current_health
	_check("the wrong set does nothing", _cast("strike").hit(boss).absorbed)
	_check("and promotes: it heals (%.0f -> %.0f)" % [before, hp.current_health], hp.current_health > before)
	skills.switch_script_set(0, true)
	before = hp.current_health
	_check("set A lands in Gen 0", not _cast("strike").hit(boss).absorbed and hp.current_health < before)
	await _until(func() -> bool: return lock.adds_alive() > 0, 2.0)
	_check("Gen 0 brings adds (%d)" % lock.adds_alive(), lock.adds_alive() > 0)

	hp.current_health = full * 0.6
	_cast("strike").hit(boss)
	_check("two thirds down: Gen 1", lock.generation() == 1)
	_check("set A is wrong now", _cast("strike").hit(boss).absorbed)
	skills.switch_script_set(1, true)
	var plain := _cast("strike")
	_check("set B lands in Gen 1", not plain.hit(boss).absorbed)

	hp.current_health = full * 0.3
	_cast("strike").hit(boss)
	_check("one third left: Gen 2", lock.generation() == 2)
	_check("set B is wrong now", _cast("strike").hit(boss).absorbed)
	skills.switch_script_set(2, true)
	_check("set C lands in Gen 2", not _cast("strike").hit(boss).absorbed)
	skills.switch_script_set(0, true)
	hp.take_damage(hp.current_health + 1.0, true)
	await _wait(0.4)
	_check("its death takes the adds", not is_instance_valid(lock) or lock._adds.is_empty())
	Ranks.lent = PackedStringArray()
	skills.refresh_rank()


# ---------- 4. THE EXAM ----------
func _exam(qm: QuestManager) -> void:
	var spec := ExamSpec.load_for("strategist")
	_check("the Strategist exam loads", spec != null and spec.required_variable)
	_check("the waves are Act III's samples", spec.wave_enemies.map(func(d): return d.id) == ["sample_leak", "sample_copy", "sample_marker"])
	_check("every wave has a name and its own colour", spec.wave_names.size() == 3 and spec.wave_tint(0) != spec.wave_tint(1) and spec.wave_tint(1) != spec.wave_tint(2))
	_check("the armoured wave has no modifiers: starter gear can't get through them", spec.mods_for_wave(1).is_empty())
	_check("the drones' modifiers load (%d)" % spec.mods_for_wave(2).size(), spec.mods_for_wave(2).size() == 2)
	_check("the burst wave's modifiers load (%d)" % spec.mods_for_wave(2).size(), spec.mods_for_wave(2).size() == 2)
	var skills: SkillComponent = _player().get("skills")

	qm.start_by_id("q05_the_leak")
	_complete(qm, "q05_the_leak")
	qm.start_by_id("exam_strategist")
	var gem := ItemInstance.new()                         # the bare test character has no skills
	gem.definition = load("res://data/items/gem/slam_gem.tres")
	skills.socket_skill(0, gem)
	ExamChamber.enter(get_tree(), "strategist")
	await _until(func() -> bool: return _am().current_area is ExamChamber and _am().can_go(), 20.0)
	await _wait(0.5)
	var chamber := _am().current_area as ExamChamber
	_check("the sandbox opens", chamber != null)
	if chamber == null:
		return
	_check("it refuses a script with no count", chamber._spec_problem().contains("keeps a count"))
	var index := -1
	for i in skills.sockets.size():
		if skills.sockets[i].gem != null:
			index = i
			break
	_check("the exam loadout has a skill", index >= 0)
	if index < 0:
		return
	var socket: SkillComponent.Socket = skills.sockets[index]
	_check("the sandbox lends variables", skills.program_limits_for(index).get_knob(&"var") != null)
	var counting_casts := _program([[], ["x", "+=", 1]], [["x", ">=", 1], [&"damage", 1], ["x", "=", 0]])
	skills.set_program(index, counting_casts)
	_check("counting every cast isn't keeping a count", chamber._spec_problem().contains("keeps a count"))
	var v := skills.set_program(index, _counter())
	_check("the counter compiles (%s)" % "; ".join(v.errors), v.valid)
	_check("the counter meets the spec (%s)" % chamber._spec_problem(), chamber._spec_problem() == "")
	_check("the counter is ELEGANT: writes aren't blocks (%d)" % v.actions_used,
			v.actions_used == 3 and v.tier != null and v.tier.display_name.to_lower() == "elegant")

	var tiles := chamber.get_node_or_null("Tiles") as GridMap
	_check("the bay is built from the yard's tiles", tiles != null and tiles.mesh_library == spec.arena_tiles and not tiles.get_used_cells().is_empty())
	_check("a sample tank for each wave", chamber._tanks.size() == 3)
	# Never casting, so the count never pays out: fails
	await _exam_run(chamber, socket, 0)
	var s0 := qm.get_state("exam_strategist")
	_check("a count that never pays out: SPEC NOT MET", s0 != null and s0.status != QuestState.Status.READY_TO_TURN_IN and chamber._fires == 0)
	chamber.retry()
	# Casting through the waves: passes
	await _exam_run(chamber, socket, 4)
	_check("the count pays out (%d times)" % chamber._fires, chamber._fires >= 3)
	var s := qm.get_state("exam_strategist")
	_check("the exam quest is ready to turn in", s != null and s.status == QuestState.Status.READY_TO_TURN_IN)
	# chamber.leave() goes to the character's last town, and this one has no save: straight back
	_am().go_to(YARD, &"default")
	await _until(_settled.bind(YARD), 30.0)
	_check("back in the yard", _settled(YARD))


## when every_nth_cast(2): x += 1   /   when x >= 1: damage up, x = 0
func _counter() -> SkillProgram:
	return _program([["every_nth_cast", 2], ["x", "+=", 1]], [["x", ">=", 1], [&"damage", 1], ["x", "=", 0]])


## A program from rules written as [[condition id, n] or [], [knob, steps], ...].
func _program(r1: Array, r2: Array = []) -> SkillProgram:
	var p := SkillProgram.new()
	for spec in [r1, r2]:
		if spec.is_empty():
			continue
		var rule := ProgramRule.new()
		if spec[0].size() == 3:                           # ["x", ">=", 3]
			rule.conditions.append(VarCondition.make(spec[0][0], spec[0][1], spec[0][2]))
		elif not spec[0].is_empty():
			var c := ProgramConditions.create(spec[0][0])
			c.set("n", spec[0][1])
			rule.conditions.append(c)
		for i in range(1, spec.size()):
			if spec[i].size() == 3:                       # ["x", "+=", 1]
				rule.effects.append(ProgramEffect.make_write(spec[i][0], spec[i][1], spec[i][2]))
			else:
				rule.effects.append(ProgramEffect.make(spec[i][0], spec[i][1]))
		p.rules.append(rule)
	return p


## A skill running `program`, as a holder of the Strategist rank would.
func _scripted(gem_id: String, program: SkillProgram) -> SkillInstance:
	var skill := SkillInstance.new()
	skill.gem = load("res://data/skill_gems/%s.tres" % gem_id)
	skill.rank = 3
	skill.program = program
	skill.rebuild()
	return skill


## One cast of a skill, through its script's before_release, as the game runs it.
func _fire(skill: SkillInstance) -> SkillCast:
	var p := _player()
	var cast := SkillCast.new(p, skill, p.get("stats"), skill.get_behavior())
	var support := ProgramSupport.of(skill)
	if support != null:
		support.before_release(cast)
	return cast


# ---------- VARIABLES ----------
func _variables() -> void:
	var low := SkillProgramLimits.for_socket(load("res://data/skill_gems/slam.tres"), [], null, 2)
	var high := SkillProgramLimits.for_socket(load("res://data/skill_gems/slam.tres"), [], null, 3)
	_check("no variables below Strategist", low.get_knob(&"var") == null and not low.allows("cond:var_compare"))
	_check("variables at Strategist", high.get_knob(&"var") != null and high.allows("cond:var_compare") and high.allows("knob:var"))

	var skill := _scripted("slam", _counter())
	_check("the counter runs", skill.program_validation != null and skill.program_validation.valid and ProgramSupport.of(skill) != null)
	var support := ProgramSupport.of(skill)
	_check("cast 1: nothing", is_equal_approx(_fire(skill).damage_mult, 1.0) and support.registers.get("x", 0) == 0)
	_check("cast 2 counts, but reads the old value", is_equal_approx(_fire(skill).damage_mult, 1.0) and support.registers.get("x", 0) == 1)
	_check("the skill bar shows it", support.registers_badge() == "x=1")
	_check("cast 3 spends it, and it resets", _fire(skill).damage_mult > 1.0 and support.registers.get("x", 0) == 0)

	# Rule order doesn't change what a script means
	var flipped := SkillProgram.new()
	var straight := _counter()
	flipped.rules.append(straight.rules[1])
	flipped.rules.append(straight.rules[0])
	var other := _scripted("slam", flipped)
	_fire(other)
	_fire(other)
	_check("the rules in the other order mean the same", _fire(other).damage_mult > 1.0)

	# always: x += 1 runs per cast, and the bake leaves it alone
	var counting := _scripted("slam", _program([[], ["x", "+=", 1]], [["x", ">=", 2], [&"damage", 1], ["x", "=", 0]]))
	_check("always: x += 1 runs a script", ProgramSupport.of(counting) != null and counting.program_validation.valid)
	_fire(counting)
	_fire(counting)
	_check("always: x += 1 counts casts", counting.program_validation.valid and _fire(counting).damage_mult > 1.0)

	# A defensive condition counts like any other
	var hp: HealthComponent = _player().get("health")
	var hurt := _scripted("slam", _program([["hit_recently", 0], ["x", "+=", 1]], [["x", ">=", 2], [&"damage", 1], ["x", "=", 0]]))
	hp.last_damaged_msec = -1000000
	_fire(hurt)
	_check("hit_recently: not hit, no count", ProgramSupport.register_value(hurt, "x") == 0)
	hp.take_damage(1.0, true)
	_fire(hurt)
	_check("hit_recently: hit, it counts", ProgramSupport.register_value(hurt, "x") == 1)
	_check("hit_recently meets the exam's spec", hurt.program.keeps_a_count())
	hp.last_damaged_msec = -1000000

	var limits := high
	var leak := _program([["every_nth_cast", 2], ["x", "+=", 1]], [["x", ">=", 1], [&"damage", 1]])
	var pays := _counter()
	var flat_read := _program([["every_nth_cast", 2], ["x", "+=", 1]], [[], [&"damage", 1]])
	_check("nothing lowers x: it still compiles (%s)" % "; ".join(leak.validate(limits).errors), leak.validate(limits).valid)
	_check("and it keeps the discount (%.2f, the same as a counter that is lowered; %.2f unconditional)" % [leak.validate(limits).points_used, flat_read.validate(limits).points_used],
			is_equal_approx(leak.validate(limits).points_used, pays.validate(limits).points_used)
			and leak.validate(limits).points_used < flat_read.validate(limits).points_used)
	var stuck := _program([["x", ">=", 1], [&"damage", 1], ["x", "=", 0]])
	_check("nothing raises x: it won't compile", "; ".join(stuck.validate(limits).errors).contains("raises"))
	_check("x >= N costs less than an always rule", ProgramConditions.create("var_compare").cost_multiplier() < 1.0)
	# Every part of both blocks is a choice
	for row in [[2, "<", 3, true], [3, "<", 3, false], [4, ">", 3, true], [3, ">", 3, false], [3, "<=", 3, true],
			[4, "<=", 3, false], [3, ">=", 3, true], [2, ">=", 3, false], [3, "==", 3, true], [2, "==", 3, false],
			[2, "!=", 3, true], [3, "!=", 3, false]]:
		_check("%d %s %d is %s" % [row[0], row[1], row[2], row[3]], ScriptRegisters.compare(row[0], row[1], row[2]) == row[3])
	_check("x = 5 sets it", ScriptRegisters.written(ProgramEffect.make_write("x", "=", 5), 2) == 5)
	_check("x += 2 adds", ScriptRegisters.written(ProgramEffect.make_write("x", "+=", 2), 2) == 4)
	_check("x -= 5 stops at 0", ScriptRegisters.written(ProgramEffect.make_write("x", "-=", 5), 2) == 0)
	var picks := VarCondition.make("x", ">=", 3)
	picks.nudge_param("reg", 1)
	picks.nudge_param("op", 2)
	_check("clicking the tokens cycles them (%s)" % picks.describe(), picks.describe() == "WHEN y != 3")
	picks.nudge_param("op", 1)
	picks.nudge_param("reg", 1)
	_check("and they wrap round (%s)" % picks.describe(), picks.describe() == "WHEN x < 3")
	picks.value = 200
	picks.clamp_params()
	_check("the value stays in range", picks.value == ScriptRegisters.MAX_VALUE)
	var constant := _program([["every_nth_cast", 2], ["x", "+=", 1]], [["x", ">=", 0], [&"damage", 1], ["x", "=", 0]])
	_check("x >= 0 is refused: always true", "; ".join(constant.validate(limits).errors).contains("always true"))
	var never := _program([["every_nth_cast", 2], ["x", "+=", 1]], [["x", "<", 0], [&"damage", 1], ["x", "=", 0]])
	_check("x < 0 is refused: never true", "; ".join(never.validate(limits).errors).contains("never true"))
	var fixed := _program([["every_nth_cast", 2], ["x", "=", 1]], [["x", "==", 1], [&"damage", 1]])
	_check("x = 1 alone compiles", fixed.validate(limits).valid)
	# A one-way switch, the kind the must-lower rule used to refuse: it runs, and stays on
	var latch := _scripted("slam", _program([["every_nth_cast", 2], ["y", "=", 1]], [["y", "==", 1], [&"damage", 1]]))
	_check("a one-way switch runs", latch.program_validation != null and latch.program_validation.valid and ProgramSupport.of(latch) != null)
	_check("switch: off at first", is_equal_approx(_fire(latch).damage_mult, 1.0))
	_fire(latch)
	_check("switch: on once tripped", _fire(latch).damage_mult > 1.0)
	_check("switch: stays on", _fire(latch).damage_mult > 1.0 and _fire(latch).damage_mult > 1.0)
	var by_one := _program([["every_nth_cast", 2], ["x", "+=", 1]], [["x", ">", 2], [&"damage", 1], ["x", "-=", 3]])
	_check("x -= 3 compiles (%s)" % "; ".join(by_one.validate(limits).errors), by_one.validate(limits).valid)
	var band := _program([["every_nth_cast", 2], ["x", "+=", 1], ["y", "=", 0]], [["x", ">=", 1], [&"damage", 1], ["x", "=", 0]])
	band.rules[1].conditions.append(VarCondition.make("x", "<", 5))
	_check("a rule can read twice, and write two variables (%s)" % "; ".join(band.validate(limits).errors), band.validate(limits).valid)
	var largest := _program([["every_nth_cast", 2], ["x", "+=", ScriptRegisters.WRITE_MAX]], [["x", ">=", 99], [&"damage", 1]])
	_check("x += 5 and x >= 99 compile (%s)" % "; ".join(largest.validate(limits).errors), largest.validate(limits).valid)
	var too_big := _program([["every_nth_cast", 2], ["x", "+=", 99]], [["x", ">=", 1], [&"damage", 1]])
	_check("x += 99 is refused", "; ".join(too_big.validate(limits).errors).contains("at most 5"))
	var set_too_big := _program([["every_nth_cast", 2], ["x", "=", 6]], [["x", ">=", 1], [&"damage", 1]])
	_check("x = 6 is refused", "; ".join(set_too_big.validate(limits).errors).contains("at most 5"))
	var climbing := _scripted("slam", _program([["every_nth_cast", 2], ["x", "+=", 5]]))
	for _i in 50:
		_fire(climbing)
	_check("but x += 5 still climbs to 99 (%d)" % int(climbing.program.registers.get("x", 0)), int(climbing.program.registers.get("x", 0)) == 99)
	var yard: Node = load("res://scenes/map/town/act_3_quarantine_yard.tscn").instantiate()
	for smith in ["TinkerHex", "Armoursmith", "Weaponsmith"]:
		var seller := yard.get_node(smith) as ShopNPC
		_check("salvage improves %s's stock" % smith, seller.salvage_magic_per > 0.0 and seller.salvage_rare_per > 0.0)
	_check("the Quartermaster is gone from the yard", not yard.has_node("Quartermaster"))
	var convoy: Node = load("res://scenes/map/town/act_2_convoy.tscn").instantiate()
	_check("and from the convoy, which still has Hex", not convoy.has_node("Quartermaster") and convoy.has_node("TinkerHex"))
	convoy.free()
	yard.free()
	var priced := ItemInstance.new()
	priced.definition = load("res://data/items/equipment/trinket/cracked_charm.tres")
	priced.item_level = 1
	var base_price := ItemPricing.value_of(priced)
	priced.item_level = 29
	var levelled := ItemPricing.value_of(priced)
	_check("a higher item level costs more (%d to %d)" % [base_price, levelled], levelled == roundi(base_price * 3.8))
	priced.rolled_affixes.assign([{}, {}])
	var modified := ItemPricing.value_of(priced)
	_check("each modifier costs more (%d to %d)" % [levelled, modified], modified == roundi(levelled * 1.5))
	await _growing_and_clearing(limits)
	var saved := SkillProgram.from_dict(_counter().to_dict())
	var mixed := SkillProgram.from_dict(_program([["every_nth_cast", 2], ["y", "-=", 7]]).to_dict())
	_check("a write keeps its parts when saved", mixed.rules[0].effects[0].describe_write() == "y -= 7")
	_check("a counter saves and loads", saved.validate(limits).valid and saved.keeps_a_count() and saved.rules[1].conditions[0] is VarCondition)


func _growing(value: int) -> SkillProgram:
	var p := _program([["every_nth_cast", 2], ["x", "+=", 2]], [[], [&"damage", value]])
	p.rules[1].effects[0].ramp = 0
	return p


## A buff growing with a counter, and counters clearing when a fight ends.
func _growing_and_clearing(limits: SkillProgramLimits) -> void:
	var grow := _growing(1)
	var whole: float = limits.get_knob(&"damage").cost_for(limits.get_knob(&"damage").max_steps)
	_check("x * 1%% costs x0.3 of the whole limit (%.2f of %.2f)" % [grow.validate(limits).points_used, whole],
			grow.validate(limits).valid and is_equal_approx(grow.validate(limits).points_used, whole * 0.3))
	var fastest := _growing(limits.get_knob(&"damage").max_steps)
	_check("the fastest line costs x0.6 (%.2f)" % fastest.validate(limits).points_used, is_equal_approx(fastest.validate(limits).points_used, whole * 0.6))
	_check("a faster line costs more", _growing(2).validate(limits).points_used > grow.validate(limits).points_used)
	var filled := _program([[], ["x", "=", 5]], [[], [&"damage", 1]])
	filled.rules[1].effects[0].ramp = 0
	_check("always: x = 5 pays for the whole limit (%.2f)" % filled.validate(limits).points_used, is_equal_approx(filled.validate(limits).points_used, whole))
	var too_fast := _growing(limits.get_knob(&"damage").max_steps + 1)
	_check("a value past the knob's limit is refused", "; ".join(too_fast.validate(limits).errors).contains("too fast"))
	var twice := _growing(1)
	var second := ProgramEffect.make(&"damage", 1)
	second.ramp = 1
	twice.rules[1].effects.append(second)
	_check("a knob can have one growing line", "; ".join(twice.validate(limits).errors).contains("only one line"))
	var full_flat := _growing(1)
	full_flat.rules[0].effects.append(ProgramEffect.make(&"damage", limits.get_knob(&"damage").max_steps))
	_check("no room left: it won't compile", "; ".join(full_flat.validate(limits).errors).contains("no room"))
	var drawback := _program([["every_nth_cast", 2], ["x", "+=", 1]], [[], [&"damage", -2]])
	drawback.rules[1].effects[0].ramp = 0
	_check("a drawback can't grow", "; ".join(drawback.validate(limits).errors).contains("only a buff"))
	var shoot: SkillProgramLimits = load("res://data/skill_programs/shoot_program_limits.tres")
	_check("damage and range can grow", ScriptRegisters.can_grow(shoot.get_knob(&"damage")) and ScriptRegisters.can_grow(shoot.get_knob(&"range")))
	_check("whole numbers can't grow", not ScriptRegisters.can_grow(shoot.get_knob(&"pierce")) and not ScriptRegisters.can_grow(shoot.get_knob(&"max_projectiles")))
	_check("the value shown is per count",
			SkillScriptTab._fmt_per_count(shoot.get_knob(&"damage"), 2) == "2%"
			and SkillScriptTab._fmt_per_count(shoot.get_knob(&"range"), 1) == "1.00m"
			and SkillScriptTab._fmt_per_count(limits.get_knob(&"radius"), 1) == "0.05m"
			and SkillScriptTab._fmt_per_count(shoot.get_knob(&"damage"), 1, 1.5) == "1.5%")
	var over := _program([["every_nth_cast", 2], ["x", "+=", 1]], [[], [&"damage", limits.get_knob(&"damage").max_steps + 1]])
	over.rules[1].effects[0].ramp = 0
	_check("a growing buff's value has its own limit", "; ".join(over.validate(limits).errors).to_lower().contains("damage"))
	_check("a growing buff keeps a count", grow.keeps_a_count())
	var saved := SkillProgram.from_dict(grow.to_dict())
	_check("and it saves", saved.rules[1].effects[0].ramp == 0 and saved.validate(limits).valid)
	var unfed := _program([[], [&"damage", 2]])
	unfed.rules[0].effects[0].ramp = 0
	_check("nothing raises x: a growing buff won't compile", "; ".join(unfed.validate(limits).errors).contains("raises"))
	var stat := _program([["every_nth_cast", 2], ["x", "+=", 1]], [[], [&"attack_speed", 1]])
	stat.rules[1].effects[0].ramp = 0
	_check("attack speed can't grow", "; ".join(stat.validate(limits).errors).contains("can't grow"))

	var skill := _scripted("slam", grow)
	var program: SkillProgram = skill.program
	var knob := skill.get_program_limits().get_knob(&"damage")
	var part := 1.0 + knob.value_for(1) * 0.4
	var limit := 1.0 + knob.value_for(knob.max_steps)
	_check("a growing buff compiles (%s)" % "; ".join(skill.program_validation.errors), skill.program_validation.valid)
	_check("growing: nothing at 0", is_equal_approx(_fire(skill).damage_mult, 1.0))
	_fire(skill)                                              # cast 2 counts: x = 2
	var at_two := _fire(skill).damage_mult
	_check("growing: x * 1%% at x = 2 (%.3f, wants %.3f)" % [at_two, part], is_equal_approx(at_two, part))
	program.registers["x"] = knob.max_steps * ScriptRegisters.RAMP_PER_STEP - 1
	var nearly := _fire(skill).damage_mult
	_check("growing: still growing past 5, just short of the limit (%.3f)" % nearly, nearly > 1.0 + knob.value_for(5) and nearly < limit)
	program.registers["x"] = knob.max_steps * ScriptRegisters.RAMP_PER_STEP
	_check("growing: reaches the limit (x = %d)" % (knob.max_steps * ScriptRegisters.RAMP_PER_STEP), is_equal_approx(_fire(skill).damage_mult, limit))
	program.registers["x"] = 90
	_check("growing: stops at the limit, at x = 90", is_equal_approx(_fire(skill).damage_mult, limit))
	var alongside := _program([["every_nth_cast", 2], ["x", "+=", 2], [&"damage", 2]], [[], [&"damage", 1]])
	alongside.rules[1].effects[0].ramp = 0
	alongside.rules[1].effects.append(ProgramEffect.make(&"mana_cost", 5))     # pays for it all
	var both := _scripted("slam", alongside)
	_check("a growing buff compiles beside a flat one (%s)" % "; ".join(both.program_validation.errors), both.program_validation.valid)
	both.program.registers["x"] = 90
	var room_left := 1.0 + knob.value_for(knob.max_steps - 2)
	var with_flat_idle := _fire(both).damage_mult               # cast 1 of every 2: the flat line doesn't fire
	_check("a flat line takes its share of the room (%.3f, wants %.3f)" % [with_flat_idle, room_left], is_equal_approx(with_flat_idle, room_left))
	for id in [&"leech", &"barrier", &"guard"]:
		var defending := _program([["every_nth_cast", 2], ["x", "+=", 1]], [[], [id, 1]])
		defending.rules[1].effects[0].ramp = 0
		var guarded := _scripted("slam", defending)
		var defence: SkillKnob = guarded.get_program_limits().get_knob(id)
		_check("%s can grow (%s)" % [id, "; ".join(guarded.program_validation.errors)], ScriptRegisters.can_grow(defence) and guarded.program_validation.valid)
		guarded.program.registers["x"] = 5
		var one_step := _fire(guarded).flag(defence.flag_key)
		_check("%s adds one step's worth at x = 5 (%.3f)" % [id, one_step], is_equal_approx(one_step, defence.step))
		guarded.program.registers["x"] = 99
		var capped := _fire(guarded).flag(defence.flag_key)
		_check("%s stops at its limit (%.3f)" % [id, capped], is_equal_approx(capped, defence.value_for(defence.max_steps)))
	_check("the values shown stay readable", SkillScriptTab._fmt_per_count(limits.get_knob(&"leech"), 1) == "0.4%" and SkillScriptTab._fmt_per_count(limits.get_knob(&"guard"), 1) == "1%")
	var twice_a_cast := _program([["every_nth_cast", 2], ["x", "+=", 2]], [[], [&"damage", 1]])
	var other_rule := ProgramRule.new()
	var nth := ProgramConditions.create("every_nth_cast")
	nth.set("n", 2)
	other_rule.conditions.append(nth)
	other_rule.effects.append(ProgramEffect.make_write("x", "+=", 3))
	twice_a_cast.rules.append(other_rule)
	twice_a_cast.rules[1].effects[0].ramp = 0
	var once := _scripted("slam", twice_a_cast)
	_fire(once)
	_fire(once)
	_check("a counter a buff grows with rises once per cast (%d)" % int(once.program.registers.get("x", 0)), int(once.program.registers.get("x", 0)) == 2)
	program.registers["x"] = 5

	# A rebuild keeps the count, on the same script
	var before := int(program.registers.get("x", 0))
	skill.rebuild()
	_check("a rebuild keeps counters (%d)" % before, before > 0 and ProgramSupport.register_value(skill, "x") == before)
	# The script in the other set has its own
	_check("another script has its own", _counter().registers.is_empty())

	# Fights end: no hit for a while
	var hp: HealthComponent = _player().get("health")
	hp.last_damaged_msec = -1000000
	program.last_active_msec = Time.get_ticks_msec() - int(ScriptRegisters.CLEAR_AFTER * 1000.0) + 2000
	_fire(skill)
	_check("still in the fight: it stays", int(program.registers.get("x", 0)) > 0)
	program.last_active_msec = Time.get_ticks_msec() - int(ScriptRegisters.CLEAR_AFTER * 1000.0) - 1000
	_check("10 seconds out of combat: it clears", ProgramSupport.of(skill).registers_badge() == "x=0")
	# Being hit keeps a fight going
	program.registers["x"] = 7
	hp.take_damage(1.0, true)
	_check("being hit keeps the fight going", ProgramSupport.of(skill).registers_badge() == "x=7")
	# Landing a hit does too
	hp.last_damaged_msec = -1000000
	program.last_active_msec = 0
	ProgramSupport.of(skill).modify_hit(SkillCast.new(_player(), skill, _player().get("stats"), skill.get_behavior()), _player(), HitInfo.new())
	_check("landing a hit keeps the fight going", ProgramSupport.of(skill).registers_badge() == "x=7")
	# A new area clears it
	program.area_id = -1
	_check("a new area clears it", ProgramSupport.of(skill).registers_badge() == "x=0")


## Runs the exam, casting the scripted skill this often in each wave, then killing the wave.
func _exam_run(chamber: ExamChamber, socket: SkillComponent.Socket, casts_per_wave: int) -> void:
	chamber.try_start()
	await _wait(3.3)
	for i in 3:
		await _until(func() -> bool: return chamber._wave == i + 1 and not chamber._alive.is_empty(), 5.0)
		await _wait(1.0)                                  # time for this wave's tank to drain
		_check("wave %d drained its tank, and the rim took its colour" % (i + 1),
				(chamber._tanks[i]["fill"] as MeshInstance3D).scale.y < 0.01
				and chamber._ring_mat.albedo_color == chamber.spec.wave_tint(i))
		for _c in casts_per_wave:
			_fire(socket.skill)
		for e in chamber._alive.duplicate():
			if is_instance_valid(e):
				e.ai.process_mode = Node.PROCESS_MODE_DISABLED
				e.health.take_damage(e.health.current_health + 1.0, true)
		await _wait(0.2)
	await _until(func() -> bool: return chamber._ended, 5.0)
	_check("the run ended", chamber._ended)


# ---------- 5. THE CHAIN ----------
func _chain(qm: QuestManager) -> void:
	for id in ["exam_operator", "exam_architect"]:        # the ranks below Strategist
		_complete(qm, id)
	_check("The Mimic can start after The Leak", qm.can_start(qm.get_def("q06_the_mimic")))
	_check("the exam turns in", qm.turn_in("exam_strategist") == "")
	_check("Strategist is held: set C unlocked", (_player().get("skills") as SkillComponent).set_unlocked(2))
	_check("The Collector waits for The Mimic", not qm.can_start(qm.get_def("q06b_the_collector")))
	qm.start_by_id("q06_the_mimic")
	_complete(qm, "q06_the_mimic")
	_check("The Collector can start now", qm.can_start(qm.get_def("q06b_the_collector")))
	_check("The Collector starts", qm.start_by_id("q06b_the_collector"))
	if qm.get_state("q06b_the_collector") == null:
		return
	GameEvents.report("kill", "the_collector")
	qm.recover("root_key")
	var c := qm.get_state("q06b_the_collector")
	_check("killing it and taking the key finishes the quest", c.status == QuestState.Status.READY_TO_TURN_IN)
	_check("The Collector turns in", qm.turn_in("q06b_the_collector") == "")
	_check("the root key stays carried for Root Access", qm.can_start(qm.get_def("q06c_root_access")) and "root_key" in QuestItems.carried(qm))
	var vesper := _npc("vesper")
	_check("Vesper is in the yard", vesper != null)
	if vesper != null:
		await _wait(0.7)
		_check("she shows after The Collector", vesper.visible)
	_check("Root Access starts", qm.start_by_id("q06c_root_access"))
	GameEvents.report("talk", "registrar")
	GameEvents.report("talk", "vesper")
	GameEvents.report("talk", "brack")
	var r := qm.get_state("q06c_root_access")
	_check("handing over the key, Vesper and Brack finish it", r.status == QuestState.Status.READY_TO_TURN_IN)
	_check("Root Access turns in", qm.turn_in("q06c_root_access") == "")
	_check("q07 can follow in Act IV's town", "q06c_root_access" in qm.completed_ids)
	_check("Memory Shards can be given", qm.get_def("memory_shards").reward_support_choice)
	_check("Copied Stock's crates are real items", QuestItems.is_item("copied_crate_a"))


# ---------- HELPERS ----------
## Marks a quest done as if turned in, for testing what it opens.
func _complete(qm: QuestManager, id: String) -> void:
	if not qm.completed_ids.has(id):
		qm.completed_ids.append(id)


func _enemy(id: String) -> Node3D:
	for e in get_tree().get_nodes_in_group("enemies"):
		if str(e.get_meta(&"enemy_id", "")) == id:
			return e
	return null


func _npc(id: String) -> Node:
	for n in _am().current_area.find_children("*", "", true, false):
		if n is DialogueNPC and n.npc_id == id:
			return n
	return null


func _process(_delta: float) -> void:
	if _keep_alive and _player() != null:
		_player().get("health").heal(100000.0)


func _settled(path: String) -> bool:
	var am := _am()
	return _player() != null and am != null and am.current_area != null and am.can_go() \
			and Waypoints.normalize(am.current_scene_path()) == path


func _done() -> void:
	_log("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	_log("%s  %s" % ["ok  " if ok else "FAIL", what])


func _log(text: String) -> void:
	print("[ACT3] ", text)
	if result_file != "":
		var mode := FileAccess.READ_WRITE if FileAccess.file_exists(result_file) and _logged else FileAccess.WRITE
		var f := FileAccess.open(result_file, mode)
		if f != null:
			f.seek_end()
			f.store_line(text)
		_logged = true


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


func _qm() -> QuestManager:
	return _player().get("quests") as QuestManager if _player() != null else null


func _am() -> AreaManager:
	return get_tree().get_first_node_in_group("area_manager") as AreaManager


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout and not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
