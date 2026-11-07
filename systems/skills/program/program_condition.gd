class_name ProgramCondition
extends Resource
## Base class for a "when" block. A rule's effects only apply while all its conditions are true.
##
## To add a condition:
##   1. extend this class, set TYPE_ID-like type_id(), and override is_true(), describe(),
##      param_names() and cost_multiplier()
##   2. register it in ProgramConditions.TYPES so saved programs can load it
##
## Scope decides when it is checked:
##   CAST  once per cast, just before the skill releases (can change flags and damage)
##   HIT   for every target hit (can only change damage, since targets were already chosen)

enum Scope { CAST, HIT }


func type_id() -> String:
	return ""


func scope() -> Scope:
	return Scope.CAST


## A support gem id this block needs socketed in the skill ("" = always available).
## The script editor only offers it with that gem, and programs using it without the gem are invalid.
func required_support() -> String:
	return ""


## Called when a CAST rule using this block fires (Variable Store spends its charge here).
func on_fired(_cast: SkillCast) -> void:
	pass


## True for blocks about loop repeats (loop == N, stack_overflow, target_alive): rules using
## them are checked again for every repeat. Other WHEN rules are checked once, on the cast,
## and the repeats keep what they did.
func per_repeat() -> bool:
	return false


## True for blocks about staying alive (my life, being hit, being surrounded): the script
## editor lists them under DEFENSE instead of OFFENSE.
func defensive() -> bool:
	return false


## A keyword that replaces "when" in the editor, for blocks that read like statements
## ("except" -> except missed:). "" = a normal when-block with parentheses.
func keyword() -> String:
	return ""


## True for blocks shown as their parameters in a row, each one a token to click, instead of a
## call with parentheses:  when [x] [>=] [3]:
func modular() -> bool:
	return false


## How the editor shows a parameter. "" = its plain value.
func param_text(_param: String) -> String:
	return ""


## What marks this block on a cast as having fired (ProgramSupport.fired_conditions).
func fired_id() -> String:
	return type_id()


## True when a rule may use this block more than once (when x >= 1 and x < 5:).
func allows_repeats() -> bool:
	return false


## True for blocks that can only ever be true on a loop repeat (target_alive, stack_overflow,
## except missed). A rule using one only changes repeats, so in a skill without any loop it
## would do nothing: SkillProgram.validate() reports that.
func needs_loop() -> bool:
	return false


## Can this turn false between one repeat and the next? A while loop needs at least one such
## block, otherwise it would always run to the cap (every_nth_cast never changes mid-cast).
func changes_during_cast() -> bool:
	return false


## `target` is null for CAST-scope checks.
func is_true(_cast: SkillCast, _target: Node) -> bool:
	return false


## How much cheaper an effect is when it only happens under this condition (0.6 = 60% price).
## Rarer conditions should be cheaper. Depends on the parameters, so players can't buy a cheap
## condition and then make it always true.
func cost_multiplier() -> float:
	return 1.0


func describe() -> String:
	return type_id()


## The exported settings the player can change (saved with the program).
func param_names() -> PackedStringArray:
	return PackedStringArray()


## How much one +/- click changes a parameter in the editor.
func param_step(_param: String) -> float:
	return 1.0


## Short name of a parameter for the editor's +/- buttons.
func param_label(param: String) -> String:
	return param.to_upper()


## Name shown on the palette block.
func palette_name() -> String:
	return describe().trim_prefix("WHEN ")


## Change a parameter by `clicks` steps (negative = down), then clamp it.
func nudge_param(param: String, clicks: int) -> void:
	var current = get(param)
	if current is int:
		set(param, current + int(param_step(param)) * clicks)
	else:
		set(param, snappedf(float(current) + param_step(param) * clicks, 0.001))
	clamp_params()


## Keep the player's settings inside sensible ranges. Called after loading.
func clamp_params() -> void:
	pass


func to_dict() -> Dictionary:
	var d := {"type": type_id()}
	for p in param_names():
		d[p] = get(p)
	return d


func load_params(d: Dictionary) -> void:
	for p in param_names():
		if not d.has(p):
			continue
		var current = get(p)
		if current is int:
			set(p, int(d[p]))
		elif current is float:
			set(p, float(d[p]))
		else:
			set(p, d[p])
	clamp_params()


# ---------- helpers for subclasses ----------

static func health_fraction(node: Node) -> float:
	if not is_instance_valid(node):
		return 1.0
	var h := node.get("health") as HealthComponent
	if h == null or h.stats == null:
		return 1.0
	var max_hp := h.stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	return h.current_health / max_hp if max_hp > 0.0 else 1.0
