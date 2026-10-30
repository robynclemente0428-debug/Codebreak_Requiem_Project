class_name ProgramConditions
extends RefCounted
## Every condition block a player can use, by the id saved in program dictionaries.
## The drag-and-drop palette can list these too. Add new conditions here.

const TYPES := {
	"enemies_nearby": preload("res://systems/skills/program/conditions/enemies_nearby_condition.gd"),
	"caster_life_below": preload("res://systems/skills/program/conditions/caster_life_below_condition.gd"),
	"target_life_below": preload("res://systems/skills/program/conditions/target_life_below_condition.gd"),
	"every_nth_cast": preload("res://systems/skills/program/conditions/every_nth_cast_condition.gd"),
	# Loops (see ProgramLoop)
	"loop_index": preload("res://systems/skills/program/conditions/loop_index_condition.gd"),
	"target_alive": preload("res://systems/skills/program/conditions/target_alive_condition.gd"),
	"stack_overflow": preload("res://systems/skills/program/conditions/stack_overflow_condition.gd"),
	# Only offered with their support gem (see ProgramCondition.required_support)
	"charge_at_least": preload("res://systems/skills/program/conditions/charge_at_least_condition.gd"),
	"missed": preload("res://systems/skills/program/conditions/missed_condition.gd"),
	"target_marked": preload("res://systems/skills/program/conditions/target_marked_condition.gd"),
	"forked": preload("res://systems/skills/program/conditions/forked_condition.gd"),
	"overclocked": preload("res://systems/skills/program/conditions/overclocked_condition.gd"),
}


static func create(type_id: String) -> ProgramCondition:
	var script: Script = TYPES.get(type_id)
	if script == null:
		push_warning("Unknown program condition: %s" % type_id)
		return null
	return script.new() as ProgramCondition


static func from_dict(d: Dictionary) -> ProgramCondition:
	var c := create(str(d.get("type", "")))
	if c != null:
		c.load_params(d)
	return c
