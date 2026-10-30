class_name SkillProgramLimits
extends Resource
## What players may program on one skill gem: which knobs exist, the point budget, how many
## blocks and rules fit, and the efficiency tiers. Set as SkillGemDefinition.program_limits.

@export var knobs: Array[SkillKnob] = []
## Points a program may spend. 0 = every buff must be paid for with drawbacks.
## Raise it for higher gem levels later.
@export var point_budget: float = 0.0
## Most blocks (conditions + effects) a program may contain.
@export var max_actions: int = 10
@export var max_rules: int = 4
## Smallest max_actions first.
@export var tiers: Array[EfficiencyTier] = []

## Which gem each knob belongs to: knob id -> "" for the skill, or the support's id.
## Filled by for_socket(); empty on the .tres (every knob belongs to the skill).
var knob_owner: Dictionary = {}
## Ids of the supports socketed with this skill (gem-only condition blocks check this).
var support_ids: PackedStringArray = []
## The caster's class trait (null for enemies, or a class without one).
var class_trait: ClassTrait


func get_knob(knob_id: StringName) -> SkillKnob:
	for k in knobs:
		if k.id == knob_id:
			return k
	return null


## The gem that owns a knob: "" for the skill itself, or a support gem's id.
func owner_of(knob_id: StringName) -> String:
	return knob_owner.get(knob_id, "")


## Knobs a rule owned by `owner_id` may use ("" = the skill's own knobs).
func knobs_for(owner_id: String) -> Array[SkillKnob]:
	var out: Array[SkillKnob] = []
	for k in knobs:
		if owner_of(k.id) == owner_id:
			out.append(k)
	return out


## The limits for one socket: the skill's knobs plus the knobs of its socketed supports.
## Everything shares one point budget, block limit and set of tiers.
static func for_socket(gem: SkillGemDefinition, supports: Array, trait_res: ClassTrait = null) -> SkillProgramLimits:
	var base := gem.program_limits if gem != null else null
	if base == null:
		return null
	var out := SkillProgramLimits.new()
	out.knobs = base.knobs.duplicate()
	out.point_budget = base.point_budget
	out.max_actions = base.max_actions
	out.max_rules = base.max_rules
	out.tiers = base.tiers.duplicate()
	for sup in supports:
		var def := sup as SupportGemDefinition
		if def == null:
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
	return out


## Class trait helpers (1.0 / false when there is no trait).
func rule_cost_mult(rule: ProgramRule) -> float:
	return class_trait.rule_cost_mult(rule) if class_trait else 1.0


func rule_effect_mult(rule: ProgramRule) -> float:
	return class_trait.rule_effect_mult(rule) if class_trait else 1.0


## Loops (ProgramLoop): the most repeats one cast may run, the points discount and the mana
## each repeat costs. The For Loop gem improves all three.
func loop_cap() -> int:
	return ProgramLoop.BASE_CAP + (ForLoopSupport.CAP_BONUS if _has_for_loop() else 0)


func loop_cost_mult() -> float:
	return ForLoopSupport.COST_MULT if _has_for_loop() else 1.0


func repeat_mana_mult() -> float:
	return ForLoopSupport.MANA_MULT if _has_for_loop() else 1.0


func _has_for_loop() -> bool:
	return support_ids.has(ForLoopSupport.ID)


## Class trait discount on everything that spends points (Enchanter: 0.75).
func buff_cost_mult() -> float:
	return class_trait.buff_cost_mult if class_trait else 1.0


func per_hit_any_knob() -> bool:
	return class_trait != null and class_trait.per_hit_any_knob


## Assassin: attack speed may go in a per-hit rule too. It can't speed up the cast that already
## started, so it speeds up the skill's NEXT cast (ProgramSupport.speed_mult).
func per_hit_attack_speed(knob: SkillKnob) -> bool:
	return per_hit_any_knob() and knob != null and knob.kind == SkillKnob.Kind.STAT \
			and knob.stat == StatTypes.Stat.ATTACK_SPEED


func tier_for(actions: int) -> EfficiencyTier:
	for t in tiers:
		if actions <= t.max_actions:
			return t
	return null
