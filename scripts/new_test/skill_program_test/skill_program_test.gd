## Run this scene (F6) to check the skill program system. Results print to the Output panel.
extends Node3D

var fails := 0
var actor_script := preload("res://scripts/new_test/skill_program_test/test_actor.gd")

func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond: fails += 1

func make_actor(pos: Vector3, hp: float, group: String) -> Node3D:
	var a := Node3D.new()
	a.set_script(actor_script)
	add_child(a)
	a.position = pos
	var st := StatComponent.new()
	st.base_stats = {StatTypes.Stat.MAX_HEALTH: hp, StatTypes.Stat.MIN_ATTACK_DAMAGE: 10.0,
		StatTypes.Stat.MAX_ATTACK_DAMAGE: 10.0, StatTypes.Stat.ATTACK_SPEED: 1.0,
		StatTypes.Stat.SKILL_DAMAGE_MULT: 1.0, StatTypes.Stat.CRIT_MULTIPLIER: 1.0,
		StatTypes.Stat.ATTACK_RANGE: 2.0}
	a.add_child(st)
	var h := HealthComponent.new()
	h.stats = st
	a.add_child(h)
	h.initialize()
	a.health = h
	a.set_meta("stats", st)
	if group != "": a.add_to_group(group)
	return a

func kill(a: Node3D) -> void:
	a.remove_from_group("enemies")
	a.queue_free()

func rule(conds: Array, effs: Array) -> ProgramRule:
	var r := ProgramRule.new()
	for c in conds: r.conditions.append(c)
	for e in effs: r.effects.append(ProgramEffect.make(e[0], e[1]))
	return r

func prog(rules: Array) -> SkillProgram:
	var p := SkillProgram.new()
	for r in rules: p.rules.append(r)
	return p

func crowd(n: int, r: float) -> EnemiesNearbyCondition:
	var c := EnemiesNearbyCondition.new(); c.min_count = n; c.radius = r; return c

func skill_with(gem_id: String, p: SkillProgram) -> SkillInstance:
	var s := SkillInstance.new()
	s.gem = SkillGemRegistry.get_skill_gem(gem_id)
	s.program = p
	s.rebuild()
	return s

func dealt(e: Node3D) -> float:
	return e.get_meta("stats").get_stat(StatTypes.Stat.MAX_HEALTH) - e.health.current_health

func _ready() -> void:
	var strike_limits := SkillGemRegistry.get_skill_gem("strike").program_limits
	strike_limits.point_budget = 0.0    # the checks below assume no free points (only in this test)
	check(strike_limits != null and strike_limits.knobs.size() == 4, "strike has program limits with 4 knobs")
	check(strike_limits.get_knob(&"mana_cost") == null, "strike has no mana knob (costs no mana)")

	# ---------- Your two examples ----------
	var always := rule([], [[&"damage", 4], [&"attack_speed", -4]])                 # +8 -10 = -2
	var cleave := rule([crowd(3, 4.0)], [[&"range_bonus", 4], [&"damage", -3]])    # (8-6)*0.6 = 1.2
	var good := prog([always, cleave])
	var v := good.validate(strike_limits)
	for line in good.describe(strike_limits): print("   ", line)
	print("   points %.2f / %.1f, actions %d, tier %s" % [v.points_used, v.point_budget, v.actions_used, v.tier.display_name if v.tier else "none"])
	check(v.valid, "example program is valid " + str(v.errors))
	check(is_equal_approx(v.points_used, -0.8), "points: -2 + 1.2 = -0.8")
	check(v.tier != null and v.tier.display_name == "Lean", "5 blocks -> Lean tier")
	check(v.next_tier != null and v.next_tier.display_name == "Elegant" and v.actions_to_next_tier == 2, "2 blocks from Elegant")

	var greedy := prog([rule([], [[&"damage", 4], [&"attack_speed", -2]]), cleave])
	v = greedy.validate(strike_limits)
	check(not v.valid and "Over budget" in v.errors[0], "buff without enough drawback is over budget")

	# ---------- Exploits and illegal programs ----------
	var low := CasterLifeBelowCondition.new(); low.fraction = 0.1
	v = prog([rule([], [[&"damage", 6]]), rule([low], [[&"damage", -6]])]).validate(strike_limits)
	check(not v.valid, "conditional drawback can't pay for an ALWAYS buff (points %.1f)" % v.points_used)
	v = prog([rule([crowd(3, 4.0)], [[&"attack_speed", 2]])]).validate(strike_limits)
	check(not v.valid and "ALWAYS" in v.errors[0], "attack speed only in ALWAYS rules")
	v = prog([rule([TargetLifeBelowCondition.new()], [[&"range_bonus", 1]])]).validate(strike_limits)
	check(not v.valid and "per-hit" in v.errors[0], "per-hit rule can only change damage")
	v = prog([rule([], [[&"damage", 11], [&"attack_speed", -8]])]).validate(strike_limits)
	check(not v.valid and "at most 10" in v.errors[0], "damage capped at +10 steps")
	v = prog([rule([], [[&"damage", 6]]), rule([crowd(3, 4.0)], [[&"damage", 6]])]).validate(strike_limits)
	check(not v.valid, "cap counts ALWAYS + conditional together")
	var big := rule([crowd(1, 2.0), crowd(2, 2.0)], [[&"damage", 1], [&"damage", -1], [&"arc_angle", 1], [&"arc_angle", -1], [&"damage", 0], [&"damage", 0], [&"damage", 0], [&"damage", 0], [&"damage", 0]])
	v = prog([big]).validate(strike_limits)
	check(not v.valid and "Too many blocks" in v.errors[0], "11 blocks is over the 10 limit")
	var c := ProgramConditions.from_dict({"type": "enemies_nearby", "min_count": 99, "radius": 0.1})
	check(c.min_count == 6 and is_equal_approx(c.radius, 2.0), "loaded params are clamped")

	# ---------- Runtime: the crowd rule changes reach and damage ----------
	var caster := make_actor(Vector3.ZERO, 100.0, "players")
	var cstats: StatComponent = caster.get_meta("stats")
	var target := make_actor(Vector3(0, 0, 3.0), 100.0, "enemies")     # beyond 2.5 m base reach
	var side1 := make_actor(Vector3(3, 0, 0), 100.0, "enemies")        # nearby but outside the arc
	var side2 := make_actor(Vector3(-3, 0, 0), 100.0, "enemies")
	var s := skill_with("strike", good)
	check(s.program_validation.valid and s.support_behaviors.size() == 1, "program applied + ProgramSupport added")
	check(is_equal_approx(s.get_cooldown(cstats), 1.0 / 0.8), "ALWAYS attack speed -20%% (cooldown %.3f)" % s.get_cooldown(cstats))
	s.cast(caster, cstats)
	await get_tree().process_frame
	check(is_equal_approx(dealt(target), 10.0 * 1.2 * 1.06 * 0.85), "crowd: target at 3 m hit for 10 x1.2 x1.06 x0.85 = %.3f" % dealt(target))
	check(dealt(side1) == 0.0, "enemies outside the arc untouched")
	var hp_before: float = target.health.current_health
	kill(side1); kill(side2)
	await get_tree().process_frame
	s.cast(caster, cstats)
	await get_tree().process_frame
	check(is_equal_approx(target.health.current_health, hp_before), "no crowd: target at 3 m out of reach")
	var close := make_actor(Vector3(0, 0, 1.5), 100.0, "enemies")
	s.cast(caster, cstats)
	await get_tree().process_frame
	check(is_equal_approx(dealt(close), 10.0 * 1.2 * 1.06), "no crowd: normal reach, no -15%% (%.3f)" % dealt(close))
	kill(close); kill(target)

	# ---------- Per-hit rule + Elegant tier ----------
	var execute := prog([rule([TargetLifeBelowCondition.new()], [[&"damage", 10]]), rule([], [[&"attack_speed", -4]])])
	v = execute.validate(strike_limits)
	check(v.valid and v.tier.display_name == "Elegant", "execute program valid, 3 blocks -> Elegant (%.2f pts)" % v.points_used)
	var weak := make_actor(Vector3(0.3, 0, 1.5), 100.0, "enemies")
	weak.health.current_health = 20.0
	var healthy := make_actor(Vector3(-0.3, 0, 1.5), 100.0, "enemies")
	s = skill_with("strike", execute)
	s.cast(caster, cstats)
	await get_tree().process_frame
	check(is_equal_approx(20.0 - weak.health.current_health, 10.0 * 1.12 * 1.5), "low-life target takes x1.5 (%.2f)" % (20.0 - weak.health.current_health))
	check(is_equal_approx(dealt(healthy), 10.0 * 1.12), "healthy target only gets the tier bonus (%.2f)" % dealt(healthy))
	kill(weak)

	# ---------- Every 3rd cast ----------
	var third := EveryNthCastCondition.new()
	s = skill_with("strike", prog([rule([third], [[&"damage", 10]]), rule([], [[&"attack_speed", -4]])]))
	var hits: Array = []
	for i in 3:
		var hp: float = healthy.health.current_health
		s.cast(caster, cstats)
		await get_tree().process_frame
		hits.append(snappedf(hp - healthy.health.current_health, 0.01))
	check(hits[0] == hits[1] and hits[2] > hits[1], "3rd cast hits harder %s" % str(hits))
	kill(healthy)

	# ---------- Slam mana trade ----------
	var slam_limits := SkillGemRegistry.get_skill_gem("slam").program_limits
	slam_limits.point_budget = 0.0      # the checks below assume no free points
	var mana_prog := prog([rule([], [[&"damage", 2], [&"mana_cost", 4]])])
	check(mana_prog.validate(slam_limits).valid, "slam: +10% damage paid by +40% mana")
	s = skill_with("slam", mana_prog)
	check(is_equal_approx(s.get_mana_cost(), 20.0 * 1.4), "slam mana 20 -> %.1f" % s.get_mana_cost())

	# ---------- Save / load + SkillComponent ----------
	var d := good.to_dict()
	var json := JSON.stringify(d)
	var back := SkillProgram.from_dict(JSON.parse_string(json))
	check(back.describe(strike_limits) == good.describe(strike_limits), "JSON round trip keeps the program")
	var comp := SkillComponent.new()
	add_child(comp)
	comp.socket_skill(0, ItemInstance.make_gem(ItemDatabase.get_item("strike_gem")))
	var res := comp.set_program(0, greedy)
	check(not res.valid and comp.get_program(0) == null, "set_program refuses an invalid program")
	res = comp.set_program(0, back)
	check(res.valid and comp.sockets[0].skill.program == back, "set_program applies a valid program")
	comp.set_program(0, null)
	check(comp.sockets[0].skill.program == null, "program can be removed")

	print("RESULT fails=%d" % fails)
	get_tree().quit(fails)
