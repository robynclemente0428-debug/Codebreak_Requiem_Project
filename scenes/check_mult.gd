extends Node

func _ready() -> void:
	var caster := StatComponent.new()
	add_child(caster)
	caster.base_stats = {
		StatTypes.Stat.MIN_ATTACK_DAMAGE: 100.0,
		StatTypes.Stat.MAX_ATTACK_DAMAGE: 100.0,    # min = max, so there is no randomness
		StatTypes.Stat.SKILL_DAMAGE_MULT: 1.0,
	}

	var skill := SkillInstance.new()
	skill.gem = SkillGemRegistry.get_skill_gem("strike")
	skill.rebuild()
	_check("no supports", skill.roll_damage(caster), 100.0)

	var cleave := SkillGemRegistry.get_support_gem("cleave_support")
	skill.supports.append(cleave)
	skill.rebuild()
	_check("Cleave (-15%)", skill.roll_damage(caster), 85.0)

	# Caster-side multiplier, like a Skill Damage affix on gear
	var m := Modifier.new()
	m.stat = StatTypes.Stat.SKILL_DAMAGE_MULT
	m.op = Modifier.ModOp.PERCENT_ADD
	m.value = 0.20
	m.source_id = "test"
	caster.add_modifier(m)
	_check("Cleave + caster +20%", skill.roll_damage(caster), 102.0)   # 100 x 0.85 x 1.2

	skill.supports.erase(cleave)
	skill.rebuild()
	_check("caster +20%, no Cleave", skill.roll_damage(caster), 120.0)

func _check(label: String, got: float, expected: float) -> void:
	print("%s  %s: got %.2f, expected %.2f" % [
		"PASS" if is_equal_approx(got, expected) else "FAIL", label, got, expected])
