extends Node

func _ready() -> void:
	_test_geometry_math()
	_test_skill_instance()

func _test_geometry_math() -> void:
	print("=== Part 1: raw resolve_hits() geometry test ===")
	var caster_pos := Vector3.ZERO
	var forward := Vector3(0, 0, -1)   # facing -Z
	
	# 5 mock enemies at various angles/distances around the caster
	var enemies: Array[Vector3] = [
		Vector3(0, 0, -1),    # dead ahead, close
		Vector3(1, 0, -1),    # 45 degrees to the right, close
		Vector3(-1, 0, -1),   # 45 degrees to the left, close
		Vector3(1, 0, 1),     # behind, to the right
		Vector3(0, 0, -10),   # dead ahead, too far away
	]
	
	print("\n--- Base Strike (90 deg arc, range 2.5, max 1 target) ---")
	var hits = StrikeBehavior.resolve_hits(caster_pos, forward, 90.0, 2.5, 1, enemies)
	print("  Hit indices: %s (expect just [0], the closest one dead ahead)" % [hits])

	print("\n--- Cleave-boosted Strike (180 deg arc, range 2.5, max 5 targets) ---")
	hits = StrikeBehavior.resolve_hits(caster_pos, forward, 180.0, 2.5, 5, enemies)
	print("  Hit indices: %s (expect [0, 1, 2], everything in front-facing half-circle, in range)" % [hits])

func _test_skill_instance() -> void:
	print("\n=== Part 2: full SkillInstance + supports test ===")

	var strike_def: SkillGemDefinition = SkillGemRegistry.get_skill_gem("strike")
	var cleave_def: SupportGemDefinition = SkillGemRegistry.get_support_gem("cleave_support")

	var skill := SkillInstance.new()
	skill.gem = strike_def
	skill.rebuild()

	print("\n--- Strike, unsupported ---")
	_print_skill(skill)

	print("\n--- Socketing Cleave Support ---")
	skill.supports.append(cleave_def)
	skill.rebuild()
	_print_skill(skill)

	print("\n--- Unsocketing Cleave Support ---")
	skill.supports.erase(cleave_def)
	skill.rebuild()
	_print_skill(skill)

func _print_skill(skill: SkillInstance) -> void:
	print("  Arc Angle: %.1f" % skill.get_flag("arc_angle"))
	print("  Range: %.1f" % skill.get_flag("range"))
	print("  Max Targets: %d" % int(skill.get_flag("max_targets")))
	print("  Skill Damage Multiplier: %.2f" % skill.get_stat(StatTypes.Stat.SKILL_DAMAGE_MULT))
