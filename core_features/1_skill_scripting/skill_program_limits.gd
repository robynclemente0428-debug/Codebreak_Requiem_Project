class_name SkillProgramLimits
extends Resource

@export var knobs: Array[SkillKnob] = []
@export var point_budget: float = 0.0
@export var max_actions: int = 10
@export var max_rules: int = 4
@export var tiers: Array[EfficiencyTier] = []

const DEFENSE_KNOBS := "res://data/skill_programs/defense_knobs.tres"

var knob_owner: Dictionary = {}
var support_ids: PackedStringArray = []
var class_trait: ClassTrait
var rank := 0
var bonus_points := 0.0
var bonus_steps := 0


var routines: Array = []


func get_knob(knob_id: StringName) -> SkillKnob:
	for k in knobs:
		if k.id == knob_id:
			return k
	return null


func owner_of(knob_id: StringName) -> String:
	return knob_owner.get(knob_id, "")


func knobs_for(owner_id: String) -> Array[SkillKnob]:
	var out: Array[SkillKnob] = []
	for k in knobs:
		if owner_of(k.id) == owner_id:
			out.append(k)
	return out


static func for_socket(gem: SkillGemDefinition, supports: Array, trait_res: ClassTrait = null, rank := 0,
		bonus_points := 0.0, bonus_steps := 0) -> SkillProgramLimits:
	var base := gem.program_limits if gem != null else null
	if base == null:
		return null
	var out := SkillProgramLimits.new()
	out.knobs = base.knobs.duplicate()
	out.point_budget = base.point_budget + bonus_points
	out.bonus_points = bonus_points
	out.max_actions = base.max_actions
	out.max_rules = base.max_rules + int(Ranks.perk(rank, "rules"))
	out.max_actions += int(Ranks.perk(rank, "blocks"))
	out.tiers = raised_tiers(base.tiers, int(Ranks.perk(rank, "tier_blocks")))
	out.rank = rank
	var defense := load(DEFENSE_KNOBS) as SkillProgramLimits
	if defense != null:
		for k in defense.knobs:
			if out.get_knob(k.id) == null:
				out.knobs.append(k)
	out.knobs.append_array(ScriptRegisters.knobs())
	out.knobs.assign(out.knobs.filter(func(k: SkillKnob) -> bool: return out.allows("knob:" + String(k.id))))
	for sup in supports:
		var def := sup as SupportGemDefinition
		if def == null or not out.allows("gem:" + def.id):
			continue
		out.support_ids.append(def.id)
		for k in def.program_knobs:
			out.knobs.append(k)
			out.knob_owner[k.id] = def.id
	if trait_res != null:
		out.class_trait = trait_res
		out.point_budget += trait_res.extra_points
		for i in out.knobs.size():
			out.knobs[i] = trait_res.adjust_knob(out.knobs[i])
	if bonus_steps > 0:
		out.bonus_steps = bonus_steps
		for i in out.knobs.size():
			out.knobs[i] = widen_knob(out.knobs[i], bonus_steps)
	return out


static func raised_tiers(tiers: Array[EfficiencyTier], extra: int) -> Array[EfficiencyTier]:
	var out: Array[EfficiencyTier] = []
	for t in tiers:
		if extra <= 0 or t == null:
			out.append(t)
			continue
		var raised := t.duplicate() as EfficiencyTier
		raised.max_actions = t.max_actions + extra
		raised.description = t.description.replace("%d blocks" % t.max_actions, "%d blocks" % raised.max_actions)
		out.append(raised)
	return out


static func widen_knob(k: SkillKnob, extra: int) -> SkillKnob:
	if extra <= 0:
		return k
	if k.cost_per_step > 0.0 and k.max_steps > 0:
		var c := k.duplicate() as SkillKnob
		c.max_steps += extra
		return c
	if k.cost_per_step < 0.0 and k.min_steps < 0:
		var c := k.duplicate() as SkillKnob
		c.min_steps -= extra
		return c
	return k


func allows(block: String) -> bool:
	return Ranks.allows(rank, block)


func rule_cost_mult(rule: ProgramRule) -> float:
	return class_trait.rule_cost_mult(rule) if class_trait else 1.0


func rule_effect_mult(rule: ProgramRule, include_hit := true) -> float:
	return (class_trait.rule_effect_mult(rule, include_hit) if class_trait else 1.0) * VariableStoreSupport.rule_effect_mult(rule)


const HIT_DEFENSE_KNOBS: Array[StringName] = [&"leech", &"barrier", &"guard"]


static func hit_defense_knob(knob: SkillKnob) -> bool:
	return knob != null and knob.kind == SkillKnob.Kind.FLAG and HIT_DEFENSE_KNOBS.has(knob.id)


const HIT_SUPPORT_FLAGS: Array[String] = ["explode_radius", "explode_damage", "breakpoint_bonus",
		"breakpoint_hits", "breakpoint_burst", "tremor_max_chain", "tremor_radius", "var_store_gain",
		"except_stack_damage", "fork_count", "fork_angle"]


static func hit_support_knob(knob: SkillKnob) -> bool:
	return knob != null and knob.kind == SkillKnob.Kind.FLAG and HIT_SUPPORT_FLAGS.has(knob.flag_key)


static func per_hit_knob(knob: SkillKnob) -> bool:
	return hit_defense_knob(knob) or hit_support_knob(knob)


func loop_cap() -> int:
	return ProgramLoop.BASE_CAP + (ForLoopSupport.CAP_BONUS if _has_for_loop() else 0)


func loop_cost_mult() -> float:
	return ForLoopSupport.COST_MULT if _has_for_loop() else 1.0


func repeat_mana_mult() -> float:
	return ForLoopSupport.MANA_MULT if _has_for_loop() else 1.0


func _has_for_loop() -> bool:
	return support_ids.has(ForLoopSupport.ID)


func buff_cost_mult() -> float:
	return class_trait.buff_cost_mult if class_trait else 1.0


func per_hit_any_knob() -> bool:
	return class_trait != null and class_trait.per_hit_any_knob


func per_hit_attack_speed(knob: SkillKnob) -> bool:
	return per_hit_any_knob() and knob != null and knob.kind == SkillKnob.Kind.STAT \
			and knob.stat == StatTypes.Stat.ATTACK_SPEED


func tier_for(actions: int) -> EfficiencyTier:
	for t in tiers:
		if actions <= t.max_actions:
			return t
	return null
