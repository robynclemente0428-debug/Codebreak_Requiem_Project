class_name ProgramObjective
extends Objective
## A scripting objective ("script a skill with enemies_nearby()", "earn the Elegant tier"...).
## Progress comes from the program_* events SkillComponent reports when a program is applied.
## already_met() also counts a program the player applied BEFORE taking the quest.
##
## kind:   program_applied (target = skill gem id), program_applied_tag (target = gem tag),
##         program_condition (target = condition id), program_nested, program_branches,
##         program_efficient (target = "lean" / "elegant", or "" for any tier),
##         program_loop (target = "for" / "while", or "" for any loop),
##         program_defrag (one script with a loop, the registry and a rule with two conditions)


func already_met(player: Node) -> bool:
	var skills: SkillComponent = player.get("skills")
	if skills == null:
		return false
	for s in skills.sockets:
		if s.gem != null and s.skill != null and s.program != null and s.program.has_rules() \
				and s.skill.program_validation != null and s.skill.program_validation.valid \
				and _program_matches(s):
			return true
	return false


func _program_matches(s: SkillComponent.Socket) -> bool:
	var gem := s.gem.definition.skill_gem
	match kind:
		"program_applied":
			return target == "" or gem.id == target
		"program_applied_tag":
			for t in gem.tags:
				if target == "" or TagTypes.name_of(TagTypes.TagGem, t) == target:
					return true
		"program_condition":
			for rule in s.program.flat_rules():
				for c in rule.conditions:
					if target == "" or c.type_id() == target:
						return true
		"program_nested":
			for rule in s.program.flat_rules():
				if rule.conditions.size() >= 2:
					return true
		"program_branches":
			var branches := 0
			for rule in s.program.flat_rules():
				if not rule.is_always():
					branches += 1
			return branches >= 2
		"program_loop":
			for rule in s.program.flat_rules():
				if rule.loop != null:
					var mode := "while" if rule.loop.mode == ProgramLoop.Mode.WHILE else "for"
					if target == "" or mode == target:
						return true
		"program_defrag":                        # the Defragmenter exam: everything at once
			var looped := false
			var nested := false
			var counted := false
			for rule in s.program.flat_rules():
				looped = looped or rule.loop != null
				nested = nested or rule.conditions.size() >= 2
				counted = counted or rule.uses_registers()
			return looped and nested and counted
		"program_efficient":
			var tier := s.skill.program_validation.tier
			return tier != null and (target == "" or tier.display_name.to_lower() == target)
	return false
