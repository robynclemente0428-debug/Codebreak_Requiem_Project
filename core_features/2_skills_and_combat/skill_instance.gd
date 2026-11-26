class_name SkillInstance
extends Resource

@export var gem: SkillGemDefinition
@export var supports: Array[SupportGemDefinition] = []
var program: SkillProgram
var program_validation: ProgramValidation
var routines: Array = []

var last_roll_was_crit := false

var _behavior: SkillBehavior
var support_behaviors: Array[SupportBehavior] = []
var _anim_index := 0
var _anim_override := ""
var flag_overrides: Dictionary = {}
var class_trait: ClassTrait
var rank := 0
var bonus_points := 0.0
var bonus_steps := 0
var owner_ref: WeakRef

var stats: StatComponent
var _flags: Dictionary = {}

var _modifiers: Array[Modifier] = []
var _effective: StatComponent

var _last_anim_msec := 0

signal used(duration: float)

func _init() -> void:
	stats = StatComponent.new()
	_effective = StatComponent.new()


func rebuild() -> void:
	stats.clear_modifiers()
	stats.base_stats = {StatTypes.Stat.MANA_COST: gem.base_mana_cost}
	_modifiers.clear()
	_flags = gem.base_flags.duplicate()
	_anim_override = ""
	support_behaviors.clear()

	for m in gem.stat_modifiers:
		_add_modifier(_tagged(m, "gem_%s" % gem.id))

	for support in supports:
		if not _tags_compatible(support.allowed_tags, gem.tags):
			continue
		if support.animation_override != "":
			_anim_override = support.animation_override
		if support.behavior_script != null:
			var sb := support.behavior_script.new() as SupportBehavior
			if sb == null:
				push_error("Support %s: behavior_script must extend SupportBehavior" % support.id)
			else:
				sb.definition = support
				support_behaviors.append(sb)
		for m in support.stat_modifiers:
			_add_modifier(_tagged(m, "support_%s" % support.id))
		for key in support.flag_modifiers.keys():
			_flags[key] = _flags.get(key, 0.0) + support.flag_modifiers[key]
		if support.mana_cost_increase != 0.0:
			var cost_mod := Modifier.new()
			cost_mod.stat = StatTypes.Stat.MANA_COST
			cost_mod.op = Modifier.ModOp.PERCENT_MULT
			cost_mod.value = support.mana_cost_increase
			cost_mod.source_id = "support_%s_cost" % support.id
			stats.add_modifier(cost_mod)
	_apply_program()
	for key in flag_overrides.keys():
		_flags[key] = float(flag_overrides[key])
	print("[Skill] %s flags=%s overrides=%s" % [gem.id, _flags, flag_overrides])

func _apply_program() -> void:
	program_validation = null
	if program == null or not program.has_rules():
		return
	var limits := get_program_limits()
	program_validation = program.validate(limits)
	if not program_validation.valid:
		push_warning("[Skill] %s: program ignored: %s" % [gem.id, "; ".join(program_validation.errors)])
		return
	var run := program.resolve(limits.routines, limits) if program.has_calls() else program
	var has_conditional := run != program
	for rule in run.rules:
		if not rule.is_baked():
			has_conditional = true
			continue
		has_conditional = has_conditional or rule.uses_registers()
		for e in rule.effects:
			var knob := limits.get_knob(e.knob)
			if knob == null or e.steps == 0 or knob.kind == SkillKnob.Kind.VARIABLE or e.ramps():
				continue
			if knob.kind == SkillKnob.Kind.FLAG:
				_flags[knob.flag_key] = _flags.get(knob.flag_key, 0.0) + knob.value_for(e.steps)
			else:
				_add_modifier(knob.make_modifier(e.steps, "program"))
	var tier := program_validation.tier
	if tier != null:
		for m in tier.modifiers:
			_add_modifier(_tagged(m, "program_tier_%s" % tier.display_name))
		for key in tier.flag_bonus.keys():
			_flags[key] = _flags.get(key, 0.0) + float(tier.flag_bonus[key])
	if has_conditional:
		support_behaviors.push_front(ProgramSupport.new(run, limits))

func get_program_limits() -> SkillProgramLimits:
	var active: Array = []
	for support in supports:
		if _tags_compatible(support.allowed_tags, gem.tags):
			active.append(support)
	var limits := SkillProgramLimits.for_socket(gem, active, class_trait, rank, bonus_points, bonus_steps)
	if limits != null:
		limits.routines = routines
	return limits

func _tagged(m: Modifier, source: String) -> Modifier:
	var copy: Modifier = m.duplicate()
	copy.source_id = source
	return copy

func build_effective_stats(caster_stats: StatComponent) -> StatComponent:
	var base: Dictionary = {}
	for stat in StatTypes.Stat.values():
		base[stat] = caster_stats.get_stat(stat)
	_effective.clear_modifiers()
	_effective.base_stats = base
	for m in _modifiers:
		_effective.add_modifier(m)
	if class_trait != null:
		var inc := class_trait.armour_damage_increase(caster_stats)
		if inc > 0.0:
			var m := Modifier.new()
			m.stat = StatTypes.Stat.SKILL_DAMAGE_MULT
			m.op = Modifier.ModOp.PERCENT_ADD
			m.value = inc
			m.source_id = "class_trait_armour_damage"
			_effective.add_modifier(m)
		var flat := class_trait.armour_flat_damage(caster_stats)
		if flat > 0.0:
			for stat in [StatTypes.Stat.MIN_ATTACK_DAMAGE, StatTypes.Stat.MAX_ATTACK_DAMAGE]:
				var f := Modifier.new()
				f.stat = stat
				f.op = Modifier.ModOp.FLAT_ADD
				f.value = flat
				f.source_id = "class_trait_armour_flat"
				_effective.add_modifier(f)
	return _effective

func peek_animation_key(combo_window := 0.8) -> String:
	if _anim_override != "":
		return _anim_override
	if gem.animation_keys.is_empty():
		return ""
	if (Time.get_ticks_msec() - _last_anim_msec) / 1000.0 > combo_window:
		_anim_index = 0
	return gem.animation_keys[_anim_index % gem.animation_keys.size()]

func advance_animation() -> void:
	_anim_index += 1
	_last_anim_msec = Time.get_ticks_msec()

func get_current_animation() -> String:
	if _anim_override != "":
		return _anim_override
	if gem.animation_keys.is_empty():
		return ""
	return gem.animation_keys[(_anim_index - 1 + gem.animation_keys.size()) % gem.animation_keys.size()]

func get_flag(key: String) -> float:
	return _flags.get(key, 0.0)

func get_melee_range(caster_stats: StatComponent) -> float:
	return maxf(caster_stats.get_stat(StatTypes.Stat.ATTACK_RANGE) + get_flag("range_bonus"), 0.0)

func roll_damage(effective_stats: StatComponent) -> float:
	var lo := effective_stats.get_stat(StatTypes.Stat.MIN_ATTACK_DAMAGE)
	var hi := effective_stats.get_stat(StatTypes.Stat.MAX_ATTACK_DAMAGE)
	var mult := effective_stats.get_stat(StatTypes.Stat.SKILL_DAMAGE_MULT)
	var base := randf_range(lo, hi)
	var total := base * mult

	var chance := clampf(effective_stats.get_stat(StatTypes.Stat.CRIT_CHANCE), 0.0, 1.0)
	var crit_mult := maxf(effective_stats.get_stat(StatTypes.Stat.CRIT_MULTIPLIER), 1.0)
	last_roll_was_crit = randf() < chance
	if last_roll_was_crit:
		total *= crit_mult
	return total

const SWING_KEY := "swing"
var _combo_swings := 0
var _combo_last_msec := -100000

func count_swing(cast: SkillCast) -> int:
	if cast.extra.has(SWING_KEY):
		return int(cast.extra[SWING_KEY])
	var now := Time.get_ticks_msec()
	var base := maxf(cast.flag("recovery_mult"), 1.0) / maxf(cast.stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 0.1)
	var window := base + cast.flag("combo_grace") + 0.35
	if (now - _combo_last_msec) / 1000.0 > window:
		_combo_swings = 0
	_combo_swings += 1
	_combo_last_msec = now
	cast.extra[SWING_KEY] = _combo_swings
	return _combo_swings


func get_cooldown(caster_stats: StatComponent) -> float:
	var speed := build_effective_stats(caster_stats).get_stat(StatTypes.Stat.ATTACK_SPEED) * speed_mult()
	return maxf(get_flag("recovery_mult"), 1.0) / maxf(speed, 0.1)


func speed_mult() -> float:
	var m := 1.0
	for s in support_behaviors:
		m *= s.speed_mult(self)
	return m

func weapon_allows(equipment: EquipmentComponent) -> bool:
	return definition_allows(gem, equipment)

func get_mana_cost() -> float:
	return maxf(stats.get_stat(StatTypes.Stat.MANA_COST), 0.0) + weapon_mana_cost()


func weapon_mana_cost() -> float:
	if gem == null or gem.required_weapon_types.is_empty() or owner_ref == null:
		return 0.0
	var owner_node := owner_ref.get_ref() as Node
	var equipment := owner_node.get("equipment") as EquipmentComponent if owner_node != null else null
	if equipment == null:
		return 0.0
	var weapon: ItemInstance = equipment.get_equipped(EquipmentSlots.Slot.WEAPON)
	if weapon == null or weapon.definition == null or weapon.definition.weapon_type == null:
		return 0.0
	return weapon.definition.weapon_type.skill_mana_cost

func can_afford(mana: ManaComponent) -> bool:
	return mana == null or mana.has_enough(get_mana_cost())

func cast(caster: Node3D, caster_stats: StatComponent, mana: ManaComponent = null) -> void:
	if mana != null:
		mana.spend(get_mana_cost())
	used.emit(get_cooldown(caster_stats))
	get_behavior().execute(caster, self, build_effective_stats(caster_stats))

func get_behavior() -> SkillBehavior:
	if _behavior == null:
		_behavior = gem.behavior_script.new() as SkillBehavior
	return _behavior

func _tags_compatible(a: Array, b: Array) -> bool:
	for t in a:
		if t in b:
			return true
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if stats != null and is_instance_valid(stats):
			stats.free()
		if _effective != null and is_instance_valid(_effective):
			_effective.free()

func get_modifiers() -> Array[Modifier]:
	return _modifiers

func _add_modifier(m: Modifier) -> void:
	if m.stat == StatTypes.Stat.MANA_COST:
		stats.add_modifier(m)
	else:
		_modifiers.append(m)

func required_weapons_text() -> String:
	return definition_requires_text(gem)

static func definition_allows(gem_def: SkillGemDefinition, equipment: EquipmentComponent) -> bool:
	var req := gem_def.required_weapon_types
	if req.is_empty():
		return true
	if equipment == null:
		return false
	var weapon: ItemInstance = equipment.get_equipped(EquipmentSlots.Slot.WEAPON)
	if weapon == null or weapon.definition.weapon_type == null:
		return false
	for t in req:
		if t.id == weapon.definition.weapon_type.id:
			return true
	return false

static func definition_requires_text(gem_def: SkillGemDefinition) -> String:
	var names: Array[String] = []
	for t in gem_def.required_weapon_types:
		names.append(t.display_name.to_upper())
	return ", ".join(names)

func get_combo_index() -> int:
	return _anim_index
