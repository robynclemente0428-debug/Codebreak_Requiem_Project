class_name ProgramRoutine
extends Resource
## A routine (the Engineer rank's unlock): lines written once and run from any skill's script with
## one  call  line. Routines belong to the character, not to a skill, so every skill and every
## script set calls the same ones (SkillComponent.routines):
##
##   def cash_in():                     routines.gd
##       if target in registry:
##           damage += 50%
##           registry.remove(target)
##       registry.add(target)
##
##   when enemies_nearby(3):            any skill's script
##       call cash_in()                 1 block, whatever the routine holds
##
## A call runs the routine's lines as if they were written where the call is, under that rule's
## conditions (SkillProgram.resolve). So routines save space, not power:
##   blocks   a call counts as ONE block in the calling script (and its efficiency tier)
##   points   each skill still pays the full price of the routine's lines, on its own knobs
## A routine has no conditions and no loop of its own (the rule that calls it decides when), at
## most MAX_BLOCKS blocks, and may hold one level of "if" blocks. It can't call a routine.
## A routine with an "if" can't be called from inside an "if" (that would nest two deep).

const MAX_ROUTINES := 3
const MAX_BLOCKS := 6
const NAME_MAX := 14
const DEFAULT_NAMES := ["routine_a", "routine_b", "routine_c"]
## The owner id a routine's body carries, so the editor (SkillScriptTab) tells its lines apart.
const OWNER := "@routines"

@export var routine_name := "routine_a"
## Its lines, as a rule with no conditions and no loop: its effects and its "if" blocks.
@export var body: ProgramRule


func _init() -> void:
	body = ProgramRule.new()
	body.owner = OWNER


static func make(index: int) -> ProgramRoutine:
	var r := ProgramRoutine.new()
	r.routine_name = DEFAULT_NAMES[clampi(index, 0, DEFAULT_NAMES.size() - 1)]
	return r


## Blocks it holds (knob lines, and an if's conditions and lines; registry writes are free).
func block_count() -> int:
	return body.action_count()


func is_empty() -> bool:
	return body.effects.is_empty() and body.branches.is_empty()


func has_if() -> bool:
	return not body.branches.is_empty()


## True when one of its lines is itself a call (not allowed: no routine calls a routine).
func has_call() -> bool:
	for e in body.effects:
		if e.is_call():
			return true
	for b in body.branches:
		for e in b.effects:
			if e.is_call():
				return true
	return false


## What's wrong with it on its own, [full sentence, short text, fix], or [] when it's fine.
func problem() -> Array:
	if is_empty():
		return ["%s() is empty." % routine_name, "%s() is empty" % routine_name,
			"open routines.gd and drop knobs into %s()" % routine_name]
	if block_count() > MAX_BLOCKS:
		return ["%s() has %d blocks, a routine holds at most %d." % [routine_name, block_count(), MAX_BLOCKS],
			"%s() has %d blocks, max %d" % [routine_name, block_count(), MAX_BLOCKS],
			"remove %d block%s from %s() in routines.gd" % [block_count() - MAX_BLOCKS,
				"" if block_count() - MAX_BLOCKS == 1 else "s", routine_name]]
	if not body.conditions.is_empty() or body.loop != null:
		return ["%s() has a condition or loop of its own." % routine_name,
			"%s() has a condition or loop of its own" % routine_name,
			"a routine has no conditions: put them on the rule that calls it"]
	if has_call():
		return ["%s() calls a routine." % routine_name, "%s() calls a routine" % routine_name,
			"a routine can't call a routine: copy its lines in instead"]
	return []


## "Cash In!" -> "cash_in"; "" falls back to its default name.
static func clean_name(text: String, index: int) -> String:
	var out := ""
	for ch in text.strip_edges().to_lower().replace(" ", "_"):
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			out += ch
	out = out.left(NAME_MAX)
	return out if out != "" and not (out[0] >= "0" and out[0] <= "9") else DEFAULT_NAMES[clampi(index, 0, DEFAULT_NAMES.size() - 1)]


func duplicate_routine() -> ProgramRoutine:
	return ProgramRoutine.from_dict(to_dict())


func to_dict() -> Dictionary:
	return {"name": routine_name, "body": body.to_dict()}


static func from_dict(d: Dictionary) -> ProgramRoutine:
	var r := ProgramRoutine.new()
	r.routine_name = str(d.get("name", DEFAULT_NAMES[0]))
	if d.get("body") is Dictionary:
		r.body = ProgramRule.from_dict(d["body"])
	r.body.owner = OWNER
	r.body.conditions.clear()
	r.body.loop = null
	return r
