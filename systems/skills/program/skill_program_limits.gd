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

## Knobs every programmable skill gets on top of its own (leech, barrier, guard). They belong
## to the skill itself and share its budget.
const DEFENSE_KNOBS := "res://data/skill_programs/defense_knobs.tres"

## Which gem each knob belongs to: knob id -> "" for the skill, or the support's id.
## Filled by for_socket(); empty on the .tres (every knob belongs to the skill).
var knob_owner: Dictionary = {}
## Ids of the supports socketed with this skill (gem-only condition blocks check this).
var support_ids: PackedStringArray = []
## The caster's class trait (null for enemies, or a class without one).
var class_trait: ClassTrait
## The caster's rank (Ranks.LADDER index): blocks above it don't exist (Ranks.LOCKED_BLOCKS).
var rank := 0
## Points on top of the gem's own budget (ScriptBudget), already in point_budget.
var bonus_points := 0.0
## Steps every knob got past its own limits (ScriptBudget: exam DISTINCTIONs), already applied.
var bonus_steps := 0


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
## Everything shares one point budget, block limit and set of tiers. `rank` (Ranks.LADDER index)
## adds the rank's extra rules and blocks, `bonus_points` / `bonus_steps` the player's ScriptBudget.
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
	out.tiers = base.tiers.duplicate()
	out.rank = rank
	var defense := load(DEFENSE_KNOBS) as SkillProgramLimits
	if defense != null:
		for k in defense.knobs:
			if out.get_knob(k.id) == null:       # a gem may define its own version
				out.knobs.append(k)
	out.knobs.append_array(ScriptRegisters.knobs())
	out.knobs.assign(out.knobs.filter(func(k: SkillKnob) -> bool: return out.allows("knob:" + String(k.id))))
	for sup in supports:
		var def := sup as SupportGemDefinition
		if def == null or not out.allows("gem:" + def.id):
			continue                             # a gem above the player's rank does nothing
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


## A copy of `k` that can go `extra` more steps the way that costs points (the buff side):
## up for most knobs, down for a knob whose steps pay points back (mana cost: fewer is the buff).
## The drawback side keeps its limit, and a knob with no buff side is left alone.
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


## True when the caster's rank may use a script block ("loop", "cond:<id>", "knob:<id>", "gem:<id>").
func allows(block: String) -> bool:
	return Ranks.allows(rank, block)


## Class trait helpers (1.0 / false when there is no trait).
func rule_cost_mult(rule: ProgramRule) -> float:
	return class_trait.rule_cost_mult(rule) if class_trait else 1.0


## How much stronger a rule's effects are than their knob steps: the class trait (Gladiator:
## every-Nth rules x1.5) times Variable Store's charge bonus (WHEN charge >= N rules).
func rule_effect_mult(rule: ProgramRule) -> float:
	return (class_trait.rule_effect_mult(rule) if class_trait else 1.0) * VariableStoreSupport.rule_effect_mult(rule)


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
