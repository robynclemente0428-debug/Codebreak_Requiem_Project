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
	# A toggle: a script that changes its own pattern with the registry, one hit in, the next out
	var toggle := _scripted("strike", _program([["not in"], ["add"]], [["in"], ["remove"]]))
	_check("a toggle compiles (%s)" % "; ".join(toggle.program_validation.errors), toggle.program_validation.valid)
	for i in 4:
		var c := _fire(toggle)
		_check("the toggle's hit %d gets through DIFF %s" % [i + 1, ProgramSupport.fired_conditions(c)], not c.hit(boss).absorbed)
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
	_check("it refuses a script with no registry", chamber._spec_problem().contains("keeps a registry"))
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
	var adds_only := _program([[], ["add"]])
	skills.set_program(index, adds_only)
	_check("adding without reading isn't keeping a registry", chamber._spec_problem().contains("keeps a registry"))
	var v := skills.set_program(index, _counter())
	_check("the registry script compiles (%s)" % "; ".join(v.errors), v.valid)
	_check("the registry script meets the spec (%s)" % chamber._spec_problem(), chamber._spec_problem() == "")
	_check("the registry script is ELEGANT: writes aren't blocks (%d)" % v.actions_used,
			v.actions_used == 2 and v.tier != null and v.tier.display_name.to_lower() == "elegant")

	var tiles := chamber.get_node_or_null("Tiles") as GridMap
	_check("the bay is built from the yard's tiles", tiles != null and tiles.mesh_library == spec.arena_tiles and not tiles.get_used_cells().is_empty())
	_check("a sample tank for each wave", chamber._tanks.size() == 3)
	# Never casting, so the registry never pays out: fails
	await _exam_run(chamber, socket, 0)
	var s0 := qm.get_state("exam_strategist")
	_check("a registry that never pays out: SPEC NOT MET", s0 != null and s0.status != QuestState.Status.READY_TO_TURN_IN and chamber._fires == 0)
	chamber.retry()
	# Casting through the waves: passes
	await _exam_run(chamber, socket, 4)
	_check("the registry pays out (%d times)" % chamber._fires, chamber._fires >= 3)
	var s := qm.get_state("exam_strategist")
	_check("the exam quest is ready to turn in", s != null and s.status == QuestState.Status.READY_TO_TURN_IN)
	# chamber.leave() goes to the character's last town, and this one has no save: straight back
	_am().go_to(YARD, &"default")
	await _until(_settled.bind(YARD), 30.0)
	_check("back in the yard", _settled(YARD))


## always: registry.add(target)   /   when target in registry: damage up
func _counter() -> SkillProgram:
	return _program([[], ["add"]], [["in"], [&"damage", 1]])


## A program from rules written as [condition, effect, ...]. A condition is [] (always:),
## ["in"] / ["not in"] (target in registry), ["size", op, n] or [condition id, n]. An effect is
## ["add"] / ["remove"] (registry.add / remove(target)) or [knob, steps].
func _program(r1: Array, r2: Array = []) -> SkillProgram:
	var p := SkillProgram.new()
	for spec in [r1, r2]:
		if spec.is_empty():
			continue
		var rule := ProgramRule.new()
		var cond: Array = spec[0]
		if cond.size() == 1:
			rule.conditions.append(VarCondition.make("target", cond[0]))
		elif cond.size() == 3:
			rule.conditions.append(VarCondition.make("size", cond[1], cond[2]))
		elif not cond.is_empty():
			var c := ProgramConditions.create(cond[0])
			c.set("n", cond[1])
			rule.conditions.append(c)
		for i in range(1, spec.size()):
			if spec[i].size() == 1:
				rule.effects.append(ProgramEffect.make_write(spec[i][0]))
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


# ---------- THE REGISTRY ----------
## A stand-in enemy in the tree: the registry keeps living nodes only.
func _dummy() -> Node3D:
	var n := Node3D.new()
	_player().get_parent().add_child(n)
	return n


## One hit of `cast` on `target` through the script's per-hit rules. Returns the hit's damage
## multiplier (1.0 = no rule changed it).
func _hit(skill: SkillInstance, cast: SkillCast, target: Node) -> float:
	var info := HitInfo.new()
	info.damage = 1.0
	ProgramSupport.of(skill).modify_hit(cast, target, info)
	return info.damage


func _variables() -> void:
	var low := SkillProgramLimits.for_socket(load("res://data/skill_gems/slam.tres"), [], null, 2)
	var high := SkillProgramLimits.for_socket(load("res://data/skill_gems/slam.tres"), [], null, 3)
	_check("no registry below Strategist", low.get_knob(&"var") == null and not low.allows("cond:var_compare"))
	_check("the registry at Strategist", high.get_knob(&"var") != null and high.allows("cond:var_compare") and high.allows("knob:var"))
	var limits := high

	# always: add / when target in registry: a hit only pays out on an enemy already in the set
	var skill := _scripted("slam", _counter())
	_check("the registry script runs", skill.program_validation != null and skill.program_validation.valid and ProgramSupport.of(skill) != null)
	var support := ProgramSupport.of(skill)
	var a := _dummy()
	var b := _dummy()
	_check("first hit on A: not in yet, no buff", is_equal_approx(_hit(skill, _fire(skill), a), 1.0))
	_check("and A is in now", ScriptRegisters.has(support.registers, a))
	_check("the skill bar shows the size", support.registers_badge() == "[1]")
	_check("second hit on A: buffed", _hit(skill, _fire(skill), a) > 1.0)
	_check("first hit on B: no buff, B is a different enemy", is_equal_approx(_hit(skill, _fire(skill), b), 1.0))
	_check("both are in (%d)" % ScriptRegisters.size_of(support.registers), ScriptRegisters.size_of(support.registers) == 2)
	_check("adding twice keeps one of each", ScriptRegisters.size_of(support.registers) == 2)
	b.free()
	_check("an enemy that's gone leaves the set", ScriptRegisters.size_of(support.registers) == 1)

	# remove: in, then out again
	var flip := _scripted("slam", _program([["not in"], ["add"]], [["in"], [&"damage", 1], ["remove"]]))
	_check("add and remove compile (%s)" % "; ".join(flip.program_validation.errors), flip.program_validation.valid)
	_check("flip: hit 1 adds", is_equal_approx(_hit(flip, _fire(flip), a), 1.0) and ScriptRegisters.has(flip.program.registers, a))
	_check("flip: hit 2 pays out and removes", _hit(flip, _fire(flip), a) > 1.0 and not ScriptRegisters.has(flip.program.registers, a))

	# registry.size is read per cast
	var sized := _scripted("slam", _program([[], ["add"]], [["size", ">=", 1], [&"damage", 1]]))
	_check("size: empty, no buff", is_equal_approx(_fire(sized).damage_mult, 1.0))
	_hit(sized, _fire(sized), a)
	_check("size: one enemy in, the next cast is buffed", _fire(sized).damage_mult > 1.0)

	# Validation
	var stuck := _program([["in"], [&"damage", 1]])
	_check("reading with nothing adding won't compile", "; ".join(stuck.validate(limits).errors).contains("stays empty"))
	var constant := _program([[], ["add"]], [["size", ">=", 0], [&"damage", 1]])
	_check("size >= 0 is refused: always true", "; ".join(constant.validate(limits).errors).contains("always true"))
	var never := _program([[], ["add"]], [["size", "<", 0], [&"damage", 1]])
	_check("size < 0 is refused: never true", "; ".join(never.validate(limits).errors).contains("never true"))
	_check("reading costs less than an always rule", ProgramConditions.create("var_compare").cost_multiplier() < 1.0)
	_check("membership is per hit", VarCondition.make("target", "in").scope() == ProgramCondition.Scope.HIT)
	_check("size is per cast", VarCondition.make("size", ">=", 3).scope() == ProgramCondition.Scope.CAST)
	for row in [[2, "<", 3, true], [3, "<", 3, false], [4, ">", 3, true], [3, ">", 3, false], [3, "<=", 3, true],
			[4, "<=", 3, false], [3, ">=", 3, true], [2, ">=", 3, false], [3, "==", 3, true], [2, "==", 3, false],
			[2, "!=", 3, true], [3, "!=", 3, false]]:
		_check("%d %s %d is %s" % [row[0], row[1], row[2], row[3]], ScriptRegisters.compare(row[0], row[1], row[2]) == row[3])
	var picks := VarCondition.make("size", ">=", 3)
	picks.nudge_param("op", 2)
	_check("clicking the operator cycles it (%s)" % picks.describe(), picks.describe() == "WHEN registry.size != 3")
	picks.nudge_param("key", 1)
	_check("clicking the first token switches to membership (%s)" % picks.describe(), picks.describe() == "WHEN target in registry")
	picks.nudge_param("op", 1)
	_check("and in / not in swap (%s)" % picks.describe(), picks.describe() == "WHEN target not in registry")
	picks.nudge_param("key", 1)
	picks.value = 200
	picks.clamp_params()
	_check("the size stays in range", picks.value == ScriptRegisters.MAX_VALUE)
	_check("keeps_a_count: add and read", _counter().keeps_a_count())
	_check("keeps_a_count: add alone isn't", not _program([[], ["add"]]).keeps_a_count())

	# Saving and old scripts
	var saved := SkillProgram.from_dict(_counter().to_dict())
	_check("a registry script saves and loads", saved.validate(limits).valid and saved.keeps_a_count() and saved.rules[1].conditions[0] is VarCondition)
	var removing := SkillProgram.from_dict(_program([[], ["remove"]]).to_dict())
	_check("a write keeps its operation when saved", removing.rules[0].effects[0].describe_write() == "registry.remove(target)")
	_check("an old x += 1 loads as add", ProgramEffect.from_dict({"knob": "var", "steps": 1, "reg": 0, "op": 1}).write_op() == "add")
	_check("an old x -= 1 loads as remove", ProgramEffect.from_dict({"knob": "var", "steps": 1, "reg": 0, "op": 2}).write_op() == "remove")
	_check("an old x = 0 loads as remove", ProgramEffect.from_dict({"knob": "var", "steps": 0, "reg": 0, "op": 0}).write_op() == "remove")

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
	a.free()


func _growing(value: int) -> SkillProgram:
	var p := _program([[], ["add"]], [[], [&"damage", value]])
	p.rules[1].effects[0].ramp = 0
	return p


## Puts `n` living stand-ins in a script's registry.
func _fill(program: SkillProgram, n: int) -> Array[Node3D]:
	program.registers.clear()
	var made: Array[Node3D] = []
	for i in n:
		var d := _dummy()
		program.registers[d.get_instance_id()] = true
		made.append(d)
	return made


func _free_all(nodes: Array[Node3D]) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()


## A buff growing with registry.size, and the registry clearing when a fight ends.
func _growing_and_clearing(limits: SkillProgramLimits) -> void:
	var grow := _growing(1)
	var whole: float = limits.get_knob(&"damage").buff_cost(limits.get_knob(&"damage").max_steps)
	_check("size * 1%% costs x0.3 of the whole limit (%.2f of %.2f)" % [grow.validate(limits).points_used, whole],
			grow.validate(limits).valid and is_equal_approx(grow.validate(limits).points_used, whole * 0.3))
	var fastest := _growing(limits.get_knob(&"damage").max_steps)
	_check("the fastest line costs x0.6 (%.2f)" % fastest.validate(limits).points_used, is_equal_approx(fastest.validate(limits).points_used, whole * 0.6))
	_check("a faster line costs more", _growing(2).validate(limits).points_used > grow.validate(limits).points_used)
	var too_fast := _growing(limits.get_knob(&"damage").max_steps + 1)
	_check("a value past the knob's limit is refused", "; ".join(too_fast.validate(limits).errors).contains("too fast"))
	var twice := _growing(1)
	var second := ProgramEffect.make(&"damage", 1)
	second.ramp = 0
	twice.rules[1].effects.append(second)
	_check("a knob can have one growing line", "; ".join(twice.validate(limits).errors).contains("only one line"))
	var full_flat := _growing(1)
	full_flat.rules[0].effects.append(ProgramEffect.make(&"damage", limits.get_knob(&"damage").max_steps))
	_check("no room left: it won't compile", "; ".join(full_flat.validate(limits).errors).contains("no room"))
	var drawback := _program([[], ["add"]], [[], [&"damage", -2]])
	drawback.rules[1].effects[0].ramp = 0
	_check("a drawback can't grow", "; ".join(drawback.validate(limits).errors).contains("only a buff"))
	var shoot: SkillProgramLimits = load("res://data/skill_programs/shoot_program_limits.tres")
	_check("damage and range can grow", ScriptRegisters.can_grow(shoot.get_knob(&"damage")) and ScriptRegisters.can_grow(shoot.get_knob(&"range")))
	_check("whole numbers can't grow", not ScriptRegisters.can_grow(shoot.get_knob(&"pierce")) and not ScriptRegisters.can_grow(shoot.get_knob(&"max_projectiles")))
	_check("the value shown is per enemy",
			SkillScriptTab._fmt_per_count(shoot.get_knob(&"damage"), 2) == "2%"
			and SkillScriptTab._fmt_per_count(shoot.get_knob(&"range"), 1) == "1.00m"
			and SkillScriptTab._fmt_per_count(limits.get_knob(&"radius"), 1) == "0.05m"
			and SkillScriptTab._fmt_per_count(shoot.get_knob(&"damage"), 1, 1.5) == "1.5%")
	_check("a growing buff keeps a registry", grow.keeps_a_count())
	var saved := SkillProgram.from_dict(grow.to_dict())
	_check("and it saves", saved.rules[1].effects[0].ramp == 0 and saved.validate(limits).valid)
	var unfed := _program([[], [&"damage", 2]])
	unfed.rules[0].effects[0].ramp = 0
	_check("nothing adds: a growing buff won't compile", "; ".join(unfed.validate(limits).errors).contains("stays at nothing"))
	var stat := _program([[], ["add"]], [[], [&"attack_speed", 1]])
	stat.rules[1].effects[0].ramp = 0
	_check("attack speed can't grow", "; ".join(stat.validate(limits).errors).contains("can't grow"))

	var skill := _scripted("slam", grow)
	var program: SkillProgram = skill.program
	var knob := skill.get_program_limits().get_knob(&"damage")
	var limit := 1.0 + knob.value_for(knob.max_steps)
	_check("a growing buff compiles (%s)" % "; ".join(skill.program_validation.errors), skill.program_validation.valid)
	_check("growing: nothing at size 0", is_equal_approx(_fire(skill).damage_mult, 1.0))
	var two := _fill(program, 2)
	var at_two := _fire(skill).damage_mult
	var part := 1.0 + knob.value_for(1) * 0.4
	_check("growing: size * 1%% at size 2 (%.3f, wants %.3f)" % [at_two, part], is_equal_approx(at_two, part))
	_free_all(two)
	var lots := _fill(program, knob.max_steps * ScriptRegisters.RAMP_PER_STEP + 3)
	_check("growing: stops at the limit", is_equal_approx(_fire(skill).damage_mult, limit))
	_free_all(lots)
	_check("growing: the dead leave, and it falls back", is_equal_approx(_fire(skill).damage_mult, 1.0))

	# A rebuild keeps the set, on the same script
	var kept := _fill(program, 3)
	skill.rebuild()
	_check("a rebuild keeps the registry", ScriptRegisters.size_of(ProgramSupport.of(skill).registers) == 3)
	_check("another script has its own", _counter().registers.is_empty())

	# Fights end: no hit for a while
	var hp: HealthComponent = _player().get("health")
	hp.last_damaged_msec = -1000000
	program.last_active_msec = Time.get_ticks_msec() - int(ScriptRegisters.CLEAR_AFTER * 1000.0) + 2000
	_fire(skill)
	_check("still in the fight: it stays", ScriptRegisters.size_of(program.registers) == 3)
	program.last_active_msec = Time.get_ticks_msec() - int(ScriptRegisters.CLEAR_AFTER * 1000.0) - 1000
	_check("10 seconds out of combat: it clears", ProgramSupport.of(skill).registers_badge() == "[0]")
	_free_all(kept)
	kept = _fill(program, 2)
	hp.take_damage(1.0, true)
	_check("being hit keeps the fight going", ProgramSupport.of(skill).registers_badge() == "[2]")
	hp.last_damaged_msec = -1000000
	program.last_active_msec = 0
	ProgramSupport.of(skill).modify_hit(SkillCast.new(_player(), skill, _player().get("stats"), skill.get_behavior()), kept[0], HitInfo.new())
	_check("landing a hit keeps the fight going", ProgramSupport.of(skill).registers_badge() == "[2]")
	program.area_id = -1
	_check("a new area clears it", ProgramSupport.of(skill).registers_badge() == "[0]")
	_free_all(kept)


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
			var cast := _fire(socket.skill)
			var sample: Node = chamber._alive[0] if not chamber._alive.is_empty() else null
			if sample != null and is_instance_valid(sample) and ProgramSupport.of(socket.skill) != null:
				_hit(socket.skill, cast, sample)               # adds it
				_hit(socket.skill, cast, sample)               # in the registry now: pays out
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
