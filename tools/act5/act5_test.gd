extends Node
## Walks Act V's descent with NO character slot loaded (nothing is saved): The Core, then down
## through The Stack Trace, Sentinel's Hall, The Page File, The Scheduler and The Kernel, and back
## up to The Core. On the way it checks:
##   - every portal: where it leads, its level, and that each sealed one opens with its key
##     (stack_road from Sudo; kernel_road and swap_road dropped by the bosses and picked up)
##   - each zone's threat on its enemies (FRAGMENTED in the Stack Trace, PAGED in the Page File)
##   - kernel.gd: the Null's pull request on each floor (its card, the game waiting, and each answer:
##     MERGE on the Stack Trace, OVERWRITE on Sentinel's Hall, TERMINATE on the Page File, MERGE on
##     the Kernel), the KERNEL card on screen, the Scheduler running what you turned down, and the
##     ending the answers lean toward
##   - each boss's lock, driven by setting its life (no hits needed):
##       Core Sentinel  RECALL: BROOD LINK -> CHECKSUM -> DIFF, and a burst past a lock restored
##       The Watchdog   HEARTBEAT: no hit in time -> it heals and reboots
##       Root Process   SPAWN (fragmented adds) -> LOOP -> FORK (FormShift)
##   - the quests: The Core Sentinel and The Root Process finish on the kill, and both are act bosses
## Writes act5_test_results.txt (and prints it), and holds on each area for `linger` seconds so it
## can be looked at.
## Run it from the editor (F6 on act5_test.tscn) or headless:
##   godot --path . res://tools/act5/act5_test.tscn

const MAIN := "res://scenes/map/main.tscn"
const CORE := "res://scenes/map/town/act_5_core.tscn"
const GATE := "res://scenes/map/dungeon/act_4_core_gate.tscn"
const STACK := "res://scenes/map/dungeon/act_5_stack_trace.tscn"
const HALL := "res://scenes/map/dungeon/act_5_sentinel_hall.tscn"
const PAGE := "res://scenes/map/dungeon/act_5_page_file.tscn"
const SCHED := "res://scenes/map/dungeon/act_5_scheduler.tscn"
const KERNEL := "res://scenes/map/dungeon/act_5_kernel.tscn"
const RESULTS := "res://tools/act5/act5_test_results.txt"

@export var linger := 3.0

var _lines := PackedStringArray()
var _failed := 0
var _qm: QuestManager


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var main: Node = load(MAIN).instantiate()
	for n in main.find_children("*", "", true, false):
		if n is AreaManager:
			n.start_area = CORE
	reparent(get_tree().root)
	var old := get_tree().current_scene
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	if old != null and old != self:
		old.queue_free()
	while not (_player() != null and _am() != null and _am().current_area != null and _am().can_go()):
		await get_tree().process_frame
	await _wait(1.0)
	_qm = _player().get("quests")
	# No gear at level 50: enough life to stand among the bosses while they're looked at
	var tough: Dictionary = (_player().get("stats") as StatComponent).base_stats.duplicate()
	tough[StatTypes.Stat.MAX_HEALTH] = 1000000.0
	(_player().get("stats") as StatComponent).base_stats = tough
	(_player().get("health") as HealthComponent).heal(1000000.0)
	# Where Act IV leaves off: the Gatekeeper turned in (root: kernel.gd). The Collector too, which
	# Vesper waits on (shown_after_quest): she shows in the Core once it reloads, checked at the end.
	for id in ["q06b_the_collector", "q08_null_gatekeeper"]:
		if not _qm.completed_ids.has(id):
			_qm.completed_ids.append(id)

	# --- The Core ---
	var core := _am().current_area
	_check("The Core loads", core != null and core.scene_file_path == CORE)
	_check("it's a town of Act V", core is TownArea and (core as TownArea).act == "V")
	_check("the player lands on the floor (%s)" % _player().global_position, _on_floor())
	_check("the act is on the map", Waypoints.act_of_scene(CORE) != null and Waypoints.act_of_scene(CORE).act_number == 5)
	for npc in ["LastLog", "ExaminerSudo", "TinkerHex"]:
		var n := core.get_node_or_null(npc) as Node3D
		_check("%s is here" % npc, n != null and n.visible)
	_check("kernel.gd is unlocked", KernelScript.unlocked(_qm))
	var core_portals := core.find_children("*", "Portal", true, false)
	_check("the Core has two portals (%d)" % core_portals.size(), core_portals.size() == 2)
	var to_stack := _portal_to(core_portals, STACK)
	_check("one back to the Core's Gate, one down to the Stack Trace",
		_portal_to(core_portals, GATE) != null and to_stack != null)
	_check("the way down is shut before Sudo ranks you (stack_road)", to_stack != null and to_stack.is_sealed())
	_qm.recover("stack_road")
	_check("and opens with stack_road", to_stack != null and not to_stack.is_sealed())
	_qm.recovered.erase("stack_road")
	_qm.completed_ids.append("exam_defragmenter")   # passing the exam opens it too (open_after_quest)
	_check("or once the Defragmenter exam is passed", to_stack != null and not to_stack.is_sealed())
	_check("THE CORE SENTINEL can start", _qm.start_by_id("q09_core_sentinel"))
	await _wait(linger)

	# --- 1st floor: The Stack Trace ---
	var stack := await _enter(to_stack, STACK, "The Stack Trace", 41)
	_check_threat(FragmentLock, "FRAGMENTED")
	await _answer_request("null_armour", "merge")
	_check_card()
	var to_hall := _portal_to(stack.find_children("*", "Portal", true, false), HALL)
	_check("portals back up and on to Sentinel's Hall (level %d)" % (to_hall.dungeon_level if to_hall else -1),
		_portal_to(stack.find_children("*", "Portal", true, false), CORE) != null and to_hall != null and to_hall.dungeon_level == 43)
	_check("the way on is open", to_hall != null and not to_hall.is_sealed())
	await _wait(linger)

	# --- 2nd floor: Sentinel's Hall ---
	var hall := await _enter(to_hall, HALL, "Sentinel's Hall", 43)
	await _answer_request("null_drain", "overwrite")
	var hall_portals := hall.find_children("*", "Portal", true, false)
	var to_page := _portal_to(hall_portals, PAGE)
	_check("a portal on to the Page File (level %d), shut by kernel_road" % (to_page.dungeon_level if to_page else -1),
		to_page != null and to_page.dungeon_level == 46 and to_page.is_sealed())
	var sentinel := _boss("Core Sentinel")
	_check("the Core Sentinel is there", sentinel != null)
	if sentinel != null:
		var recall := _trait_of(sentinel, RecallLock) as RecallLock
		_check("it has RECALL, starting on BROOD LINK", recall != null and recall.phase == 0
			and _has_trait_script(sentinel, RecallLock.PHASES[0]))
		_near(sentinel, 8.0)
		await _wait(0.5)
		_set_life(sentinel, 0.10)                   # a burst straight past CHECKSUM and DIFF
		await _wait(0.5)
		var share := _life(sentinel)
		_check("a burst past a lock is RESTORED FROM BACKUP to the middle of the next third (%.0f%%)" % (share * 100.0),
			share > 0.45 and share < 0.55)
		_check("and it loads CHECKSUM", recall != null and recall.phase == 1
			and _has_trait_script(sentinel, RecallLock.PHASES[1]) and not _has_trait_script(sentinel, RecallLock.PHASES[0]))
		_set_life(sentinel, 0.20)
		await _wait(0.5)
		_check("then DIFF, with no restore (%.0f%%)" % (_life(sentinel) * 100.0), recall != null and recall.phase == 2
			and _has_trait_script(sentinel, RecallLock.PHASES[2]) and _life(sentinel) < 0.25)
		var at := sentinel.global_position
		_kill(sentinel)
		await _wait(1.5)
		_check("killing it finishes THE CORE SENTINEL", _ready_to_turn_in("q09_core_sentinel"))
		_check("and counts as an act boss", _qm.deed_count(ScriptBudget.BOSS_DEED, "core_sentinel") > 0)
		await _pick_up_key(at, "kernel_road")
	_check("the Page File portal opens", to_page != null and not to_page.is_sealed())
	await _wait(linger)
	# THE ROOT PROCESS follows (turned in at the Last Log in play)
	_qm.active.erase("q09_core_sentinel")
	if not _qm.completed_ids.has("q09_core_sentinel"):
		_qm.completed_ids.append("q09_core_sentinel")

	# --- 3rd floor: The Page File ---
	var page := await _enter(to_page, PAGE, "The Page File", 46)
	_check_threat(PagedLock, "PAGED")
	await _answer_request("null_swap", "terminate")
	var to_sched := _portal_to(page.find_children("*", "Portal", true, false), SCHED)
	_check("a portal on to the Scheduler (level %d), shut by swap_road" % (to_sched.dungeon_level if to_sched else -1),
		to_sched != null and to_sched.dungeon_level == 48 and to_sched.is_sealed())
	var dog := _boss("Watchdog")
	_check("The Watchdog is there", dog != null)
	if dog != null:
		var hb := _trait_of(dog, WatchdogLock) as WatchdogLock
		_check("it has HEARTBEAT and is PAGED", hb != null and _trait_of(dog, PagedLock) != null)
		_near(dog, 8.0)                             # in range: its timer runs
		await _wait(0.3)
		_set_life(dog, 0.40)                        # below half: the timer tightens
		var before := _life(dog)
		await _wait(hb.tight_timeout + 0.8 if hb else 3.0)   # and no hit lands
		_check("no hit in time: it heals %.0f%% and reboots (%.0f%% -> %.0f%%, %s)" % [
			(hb.reset_heal if hb else 0.0) * 100.0, before * 100.0, _life(dog) * 100.0, hb.tag_state() if hb else "?"],
			hb != null and _life(dog) > before + hb.reset_heal * 0.8 and hb.tag_state() == "REBOOT")
		var at := dog.global_position
		_kill(dog)
		await _wait(1.5)
		_check("killing it counts as an act boss", _qm.deed_count(ScriptBudget.BOSS_DEED, "watchdog") > 0)
		await _pick_up_key(at, "swap_road")
	_check("the Scheduler portal opens", to_sched != null and not to_sched.is_sealed())
	await _wait(linger)

	# --- 4th floor: The Scheduler ---
	var sched := await _enter(to_sched, SCHED, "The Scheduler", 48)
	var director := sched.find_children("*", "KernelDirector", true, false)
	var first := str(director[0].get("_scheduled")) if not director.is_empty() else ""
	_check("no pull request of its own here", not get_tree().root.find_children("*", "PullRequestCard", false, false).size())
	_check("the Null schedules a line you turned down (%s, %s)" % [first, KernelScript.answer_of(_qm, first)],
		KernelScript.NULL_LINES.has(first) and KernelScript.answer_of(_qm, first) in ["overwrite", "terminate"])
	if not director.is_empty():
		director[0].set("_schedule_left", 0.01)      # skip the 45 s
		await _wait(0.5)
		var second := str(director[0].get("_scheduled"))
		_check("then the other one, round and round (%s, %s)" % [second, KernelScript.answer_of(_qm, second)],
			second != first and KernelScript.answer_of(_qm, second) in ["overwrite", "terminate"])
	var to_kernel := _portal_to(sched.find_children("*", "Portal", true, false), KERNEL)
	_check("an open portal on to the Kernel (level %d)" % (to_kernel.dungeon_level if to_kernel else -1),
		to_kernel != null and to_kernel.dungeon_level == 50 and not to_kernel.is_sealed())
	await _wait(linger)

	# --- 5th floor: The Kernel ---
	var kernel := await _enter(to_kernel, KERNEL, "The Kernel", 50)
	await _answer_request("null_regrow", "merge")
	_check("THE ROOT PROCESS can start", _qm.start_by_id("q10_root_process"))
	var root := _boss("Root Process")
	_check("the Root Process is there", root != null)
	if root != null:
		var phases := _trait_of(root, RootPhases) as RootPhases
		_check("it starts in PHASE 1 // SPAWN", phases != null and phases.phase == 0)
		_near(root, 7.0)
		await _wait(5.0)                            # its Summoner's first wave: 3 s after it notices you
		var adds := get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool:
			return e != root and not SkillBehavior.is_dead(e) and _trait_of(e, FragmentLock) != null)
		_check("its adds come FRAGMENTED (%d)" % adds.size(), not adds.is_empty())
		_set_life(root, 0.60)
		await _wait(0.5)
		_check("PHASE 2 // LOOP at two thirds", phases != null and phases.phase == 1)
		_set_life(root, 0.25)
		await _wait(0.5)
		_check("PHASE 3 // FORK at a third, swapping forms", phases != null and phases.phase == 2
			and _trait_of(root, FormShift) != null)
		_kill(root)
		await _wait(1.5)
		_check("killing it finishes THE ROOT PROCESS", _ready_to_turn_in("q10_root_process"))
		_check("and counts as an act boss", _qm.deed_count(ScriptBudget.BOSS_DEED, "root_process") > 0)
	var out := _portal_to(kernel.find_children("*", "Portal", true, false), CORE)
	_check("the far exit goes back up to the Core, open", out != null and not out.is_sealed())
	await _wait(linger)

	# --- The ending your kernel leans toward ---
	var t := KernelScript.tally(_qm)
	_check("all four requests answered (merge %d, overwrite %d, terminate %d)" % [t["merge"], t["overwrite"], t["terminate"]],
		t["merge"] == 2 and t["overwrite"] == 1 and t["terminate"] == 1)
	_check("two merges lean MERGE (%s)" % KernelScript.lean(_qm), KernelScript.lean(_qm) == "merge")
	_check("and both merged lines run (%s)" % ", ".join(KernelScript.null_running(_qm)),
		KernelScript.null_running(_qm).size() == 2)
	# Other answers, set straight on the deeds (each request is answered once in play)
	_reanswer("null_regrow", "terminate")
	_check("two terminates lean TERMINATE (%s)" % KernelScript.lean(_qm), KernelScript.lean(_qm) == "terminate")
	_reanswer("null_regrow", "overwrite")
	_check("two overwrites lean OVERWRITE (%s)" % KernelScript.lean(_qm), KernelScript.lean(_qm) == "overwrite")
	_reanswer("null_regrow", "")
	_check("a 1-1-1 tie goes to the deepest answer, the Page File's TERMINATE (%s)" % KernelScript.lean(_qm),
		KernelScript.lean(_qm) == "terminate")
	_reanswer("null_regrow", "merge")

	# --- And back up ---
	if out != null:
		await _go(out.target_area, out.target_spawn, 0)
	_check("back in the Core", _am().current_area.scene_file_path == CORE)
	_check("the player lands on the floor (%s)" % _player().global_position, _on_floor())
	_check("no KERNEL card in the Core", _card() == null)
	var vesper := _am().current_area.get_node_or_null("Vesper") as Node3D
	_check("Vesper is in the Core (after The Collector)", vesper != null and vesper.is_visible_in_tree())

	# --- The endings (Endings): the choice is final, so the test resets it to try each one ---
	await _check_endings(vesper)

	_lines.append("ALL PASSED" if _failed == 0 else "%d FAILED" % _failed)
	var f := FileAccess.open(RESULTS, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\nDONE\n")
	print("\n".join(_lines))


## Test only: forget the chosen ending, so the next one can be tried (the game never does this).
func _reset_ending() -> void:
	for id in Endings.IDS:
		_qm.deeds.erase("%s:%s" % [Endings.NOW_DEED, id])
		_qm.deeds.erase("ending:%s" % id)


# ---------- ZONE CHECKS ----------
## Through `portal`, then the usual: it loads, the player's on the floor, enemies at its level.
func _enter(portal: Portal, area: String, label: String, level: int) -> Node:
	if portal == null:
		_check("%s: no portal to it" % label, false)
		return _am().current_area
	await _go(portal.target_area, portal.target_spawn, portal.dungeon_level)
	var here := _am().current_area
	_check("%s loads" % label, here != null and here.scene_file_path == area)
	await _wait(2.0)
	_check("the player lands on the floor (%s)" % _player().global_position, _on_floor())
	var enemies := _alive_enemies()
	_check("enemies spawn (%d)" % enemies.size(), not enemies.is_empty())
	if not enemies.is_empty():
		_check("at level %d (%d)" % [level, int(enemies[0].get("level"))], int(enemies[0].get("level")) == level)
	_check("on the waypoint map", Waypoints.for_scene(area) != null)
	return here


## Every regular enemy here has the zone's threat. Placed ones (bosses, the Stack Trace's three
## Architect-log carriers) are rare or champion and keep their own traits (threat_traits = false).
func _check_threat(script: Script, label: String) -> void:
	var regular := _alive_enemies().filter(func(e: Node) -> bool: return e.get("rarity") in ["normal", "magic"])
	var with := regular.filter(func(e: Node) -> bool: return _trait_of(e, script) != null)
	_check("the zone's enemies are %s (%d of %d)" % [label, with.size(), regular.size()],
		not regular.is_empty() and with.size() == regular.size())


## The Null's pull request: submitted on arrival, its card up and the game waiting. Answer it
## through the card (as a click would), then check what the answer did.
func _answer_request(id: String, how: String) -> void:
	_check("the Null submits %s" % KernelScript.code_of(id), KernelScript.is_inserted(_qm, id))
	var card: PullRequestCard = null
	var left := 4.0
	while left > 0.0 and card == null:
		var found := get_tree().root.find_children("*", "PullRequestCard", false, false)
		card = found[0] if not found.is_empty() else null
		await get_tree().process_frame
		left -= get_process_delta_time()
	_check("its card asks for an answer", card != null and card.null_id == id)
	_check("and the game waits while it's up", get_tree().paused)
	var lines: Array[String] = (_player().get("skills") as SkillComponent).kernel
	var pick := str(KernelScript.offers(lines, id)[0]) if how == "overwrite" else ""
	var before := _alive_enemies().filter(func(e: Node) -> bool: return e.has_meta(&"kernel_defender")).size()
	if card != null:
		card._answer(how, pick)
	await _wait(0.6)
	_check("answered %s (%s)" % [how.to_upper(), KernelScript.answer_of(_qm, id)], KernelScript.answer_of(_qm, id) == how)
	_check("the card is gone and the game runs again", not get_tree().paused
		and get_tree().root.find_children("*", "PullRequestCard", false, false).is_empty())
	match how:
		"merge":
			var gift := str(KernelScript.NULL_LINES[id]["gift"])
			_check("its line runs, and its gift is yours (%s)" % gift, id in KernelScript.null_running(_qm) and gift in lines)
		"overwrite":
			_check("its line doesn't run; yours does (%s)" % pick, not id in KernelScript.null_running(_qm) and pick in lines)
		"terminate":
			var after := _alive_enemies().filter(func(e: Node) -> bool: return e.has_meta(&"kernel_defender")).size()
			_check("neither runs, and a champion comes for you (%d)" % (after - before),
				not id in KernelScript.null_running(_qm) and after == before + 1)


## Each ending in turn, chosen in the Core: its epilogue, the Core's look, Vesper, and what it
## leaves behind (MERGE's lines everywhere: checked in the Core's Gate, Act IV's last dungeon).
func _check_endings(vesper: Node3D) -> void:
	var core := _am().current_area
	var ce := core.get_node_or_null("CoreEnding") as CoreEnding
	_check("the Core watches the ending (CoreEnding)", ce != null)
	_check("no ending yet: the Core as it was", Endings.current(_qm) == "" and ce != null and ce.shown == "")
	var glow := core.get_node_or_null("NullGlowW") as OmniLight3D
	var glow_before := glow.light_energy if glow != null else -1.0
	var sun := get_tree().root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
	var sun_orig := sun.light_energy if sun != null else -1.0

	# MERGE
	Endings.choose(_qm, "merge")
	await _wait(1.2)
	_check("MERGE: the Core shows it (%s)" % (ce.shown if ce else "?"), ce != null and ce.shown == "merge")
	_check("the Null's glow brightens (%.1f -> %.1f)" % [glow_before, glow.light_energy if glow else -1.0],
		glow != null and glow.light_energy > glow_before)
	_check("Vesper is gone from the Core", vesper != null and not vesper.visible)
	var pages := Endings.pages(_qm, _player(), "merge")
	_check("its epilogue: %d pages (%s)" % [pages.size(), ", ".join(pages.map(func(p: Dictionary) -> String: return str(p.title)))],
		pages.size() >= 5)
	_check("one of them reads back your kernel", pages.any(func(p: Dictionary) -> bool:
		return str(p.title) == "YOUR KERNEL" and str(p.text).contains("Page File")))
	_check("your lines run everywhere now", Endings.runs_everywhere(_qm) and not Endings.kernel_editable(_qm))
	_check("the character sheet's title: %s" % Endings.TITLES["merge"], Endings.TITLES.has(Endings.current(_qm)))
	EndingCard.show_ending(get_tree(), "merge")
	await _wait(0.3)
	var cards := get_tree().root.find_children("*", "EndingCard", false, false)
	_check("the epilogue card opens", not cards.is_empty())
	for c in cards:
		c.queue_free()
	await _wait(0.3)

	# MERGE's lines in a dungeon past Act V: the Core's Gate (Act IV)
	var gate := _portal_to(core.find_children("*", "Portal", true, false), "res://scenes/map/dungeon/act_4_core_gate.tscn")
	if gate != null:
		await _go(gate.target_area, gate.target_spawn, gate.dungeon_level)
		await _wait(2.0)
		var kd := _am().current_area.find_children("*", "KernelDirector", true, false)
		_check("past Act V, kernel.gd runs (the Core's Gate)", not kd.is_empty() and kd[0].get("_mine") == true)
		_check("and its card is up there", _card() != null)
		var back := _portal_to(_am().current_area.find_children("*", "Portal", true, false), CORE)
		if back != null:
			await _go(back.target_area, back.target_spawn, 0)
		core = _am().current_area
		ce = core.get_node_or_null("CoreEnding") as CoreEnding
		glow = core.get_node_or_null("NullGlowW") as OmniLight3D
		vesper = core.get_node_or_null("Vesper") as Node3D
		await _wait(1.2)
		_check("back in the Core, still merged", ce != null and ce.shown == "merge")

	_check("the choice is final: a second one is refused", not Endings.choose(_qm, "overwrite")
		and Endings.current(_qm) == "merge")

	# OVERWRITE (test only: the ending reset, as a fresh save would be)
	_reset_ending()
	Endings.choose(_qm, "overwrite")
	await _wait(1.2)
	_check("OVERWRITE: the Core shows it", ce != null and ce.shown == "overwrite")
	_check("the Null's glow is out", glow != null and is_zero_approx(glow.light_energy))
	_check("Vesper is back in the Core", vesper != null and vesper.visible)
	_check("the Null is dormant: none of its lines run (%d)" % KernelScript.null_running(_qm).size(),
		KernelScript.null_running(_qm).is_empty())
	_check("kernel.gd is yours to edit (up to %d lines)" % Endings.MAX_ROOT_LINES, Endings.kernel_editable(_qm))
	_check("its epilogue counts the convoy", Endings.pages(_qm, _player(), "overwrite").any(func(p: Dictionary) -> bool:
		return str(p.title) == "THE CONVOY" and str(p.text).contains("crate")))

	# TERMINATE
	var sun_before := sun.light_energy if sun != null else -1.0
	_reset_ending()
	Endings.choose(_qm, "terminate")
	await _wait(1.2)
	_check("TERMINATE: the Core goes dark (sun %.2f -> %.2f)" % [sun_before, sun.light_energy if sun else -1.0],
		ce != null and ce.shown == "terminate" and sun != null and sun.light_energy < sun_before * 0.5)
	_check("but the Last Log's terminal still glows", core.find_children("EndingLight*", "OmniLight3D", false, false).size() == 1)
	var tp := Endings.pages(_qm, _player(), "terminate")
	var fl := tp.filter(func(p: Dictionary) -> bool: return str(p.title) == "// FINAL LOG //")
	_check("its FINAL LOG reads the run", not fl.is_empty() and str(fl[0].text).contains("> bosses")
		and str(fl[0].text).contains("> kernel     merged 2"))
	_check("it ends: END OF LOG", str(tp[-1].text).begins_with("// END OF LOG"))
	_check("lines don't run everywhere after it", not Endings.runs_everywhere(_qm))
	_check("still TERMINATE after trying MERGE", not Endings.choose(_qm, "merge") and Endings.current(_qm) == "terminate")

	# Leaving the Core puts the world's light back
	var to_stack := _portal_to(core.find_children("*", "Portal", true, false), STACK)
	await _wait(1.2)
	if to_stack != null:
		await _go(to_stack.target_area, to_stack.target_spawn, to_stack.dungeon_level)
		# The next area lights itself (AreaLighting: the saved sun x its light_scale; dungeons are
		# dark): nothing of the Core's ending may be left on top of that.
		var want := AreaLighting._base_sun * float(_am().current_area.get("light_scale"))
		_check("leaving the Core puts the light back: the next area's own (sun %.3f, its %.3f; the Core's was %.2f)" % [
			sun.light_energy if sun else -1.0, want, sun_orig],
			sun != null and absf(sun.light_energy - want) < 0.005)


## Sets a request's answer straight on the deeds ("" = unanswered), to check the lean (test only:
## in play a request is answered once, for good).
func _reanswer(id: String, how: String) -> void:
	for a in KernelScript.ANSWERS:
		_qm.deeds.erase("%s:%s" % [KernelScript.deed_of(a), id])
	if how != "":
		_qm.deeds["%s:%s" % [KernelScript.deed_of(how), id]] = 1


## The KERNEL card is up, in the top-centre strip (Announcer), clear of the screen's edges.
func _check_card() -> void:
	var card := _card()
	_check("the KERNEL card is on screen", card != null and card.is_visible_in_tree())
	if card != null:
		var screen := card.get_viewport_rect().size
		var r := card.get_global_rect()
		_check("top centre, clear of the corners (%s in %s)" % [r, screen],
			r.position.y >= Announcer.fit(Announcer.STRIP_TOP) - 1.0 and absf(r.get_center().x - screen.x * 0.5) < 2.0)


func _card() -> Control:
	var hud := get_tree().root.find_child("StimLayer", true, false)
	return hud.find_child("KernelStrip", true, false) as Control if hud != null else null


# ---------- BOSSES ----------
## By the end of its name: a champion's rolled modifiers go in front ("The Hardened Watchdog"),
## so "Watchdog", not "The Watchdog".
func _boss(name_has: String) -> Node3D:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not SkillBehavior.is_dead(e) and String(e.get("display_name")).ends_with(name_has):
			return e
	return null


func _trait_of(e: Node, script: Script) -> Node:
	for t in e.get("traits") if e.get("traits") != null else []:
		if is_instance_valid(t) and is_instance_of(t, script):
			return t
	return null


func _has_trait_script(e: Node, script: Script) -> bool:
	for t in e.get("traits"):
		if is_instance_valid(t) and t.get_script() == script:
			return true
	return false


func _life(e: Node) -> float:
	var hp := e.get("health") as HealthComponent
	var top := (e.get("stats") as StatComponent).get_stat(StatTypes.Stat.MAX_HEALTH)
	return hp.current_health / top if top > 0.0 else 0.0


## Sets its life to `share` of its maximum, straight on the health (no hit, so no lock judges it).
func _set_life(e: Node, share: float) -> void:
	var hp := e.get("health") as HealthComponent
	var top := (e.get("stats") as StatComponent).get_stat(StatTypes.Stat.MAX_HEALTH)
	var want := top * share
	if hp.current_health > want:
		hp.take_damage(hp.current_health - want, true)
	if absf(hp.current_health - want) > top * 0.01:
		hp.current_health = want                 # armour or a floor got in the way: set it


func _kill(e: Node) -> void:
	(e.get("health") as HealthComponent).take_damage(1.0e12, true)


func _near(e: Node3D, metres: float) -> void:
	_player().global_position = e.global_position + Vector3(metres, 0.5, 0.0)


## The boss dropped its key where it fell: walk onto it.
func _pick_up_key(at: Vector3, key: String) -> void:
	var pickups := get_tree().root.find_children("*", "QuestKeyPickup", true, false)
	_check("it drops %s (%d on the floor)" % [key, pickups.size()], not pickups.is_empty())
	_player().global_position = at + Vector3.UP * 0.5
	var left := 3.0
	while left > 0.0 and not _qm.has_recovered(key):
		await get_tree().process_frame
		left -= get_process_delta_time()
	_check("walking onto it picks up %s" % key, _qm.has_recovered(key))
	await _wait(0.8)                             # portals check their seal twice a second


func _ready_to_turn_in(id: String) -> bool:
	var s: QuestState = _qm.get_state(id)
	return s != null and s.status == QuestState.Status.READY_TO_TURN_IN


# ---------- HELPERS (as act4_test) ----------
func _process(_delta: float) -> void:
	var p := _player()
	if p != null:
		(p.get("health") as HealthComponent).heal(100000.0)


func _alive_enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return not SkillBehavior.is_dead(e))


func _portal_to(portals: Array, area: String) -> Portal:
	for p in portals:
		if (p as Portal).target_area == area:
			return p
	return null


func _go(area: String, spawn: StringName, level: int) -> void:
	_am().go_to(area, spawn, level)
	await _wait(0.5)
	var left := 40.0
	while left > 0.0 and not (_am().current_area != null and _am().current_area.scene_file_path == area and _am().can_go()):
		await get_tree().process_frame
		left -= get_process_delta_time()
	await _wait(1.0)


## A floor to stand on: something solid just under the player's feet.
func _on_floor() -> bool:
	var p := _player()
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP, p.global_position + Vector3.DOWN * 2.0)
	q.exclude = [(p as CollisionObject3D).get_rid()]
	return not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _check(what: String, ok: bool) -> void:
	_lines.append("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


func _am() -> AreaManager:
	return get_tree().get_first_node_in_group("area_manager") as AreaManager
