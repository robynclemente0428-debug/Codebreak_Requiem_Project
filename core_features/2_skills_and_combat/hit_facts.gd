class_name HitFacts
extends RefCounted

var caster: Node
var by_player := false
var gem_id := ""
var gem: SkillGemDefinition
var script_set := -1
var owner_set := 0
var fired: Array = []
var rule_pairs: Array = []
var tier := ""
var has_script := false
var blocks_to_next := 0
var cast_id := ""
var root_id := ""
var root_damage_mult := 1.0
var loop_id := ""
var loop_repeat := false
var forked := false


static func from_cast(cast: SkillCast) -> HitFacts:
	if cast == null or not cast.is_valid():
		return null
	var f := HitFacts.new()
	f.caster = cast.caster
	f.by_player = cast.caster.is_in_group(&"players")
	var skill := cast.skill
	if skill != null and skill.gem != null:
		f.gem = skill.gem
		f.gem_id = String(skill.gem.id)
	var skills := cast.caster.get("skills") as SkillComponent
	f.script_set = skills.script_set if skills != null else -1
	f.owner_set = f.script_set
	if skills == null:
		var own := Coop.own_player(cast.caster.get_tree())
		var own_skills := own.get("skills") as SkillComponent if own != null else null
		f.owner_set = own_skills.script_set if own_skills != null else 0
	f.fired = ProgramSupport.fired_conditions(cast)
	var support := ProgramSupport.of(skill)
	if support != null and support.program != null:
		for rule in support.program.flat_rules():
			if rule.conditions.size() == 2:
				f.rule_pairs.append([rule.conditions[0].type_id(), rule.conditions[1].type_id()])
	var v = skill.program_validation if skill != null else null
	if v != null and v.valid:
		f.tier = v.tier.display_name.to_lower() if v.tier != null else ""
		f.has_script = skill.program != null and skill.program.has_rules()
		f.blocks_to_next = v.actions_to_next_tier if v.next_tier != null else 0
	f.cast_id = _id(cast)
	var runner := cast.extra.get(ProgramSupport.LOOP_KEY) as ProgramLoopRunner
	var root: SkillCast = runner.root if runner != null and runner.root != null else cast
	f.root_id = _id(root)
	f.root_damage_mult = root.damage_mult
	if runner != null:
		f.loop_id = _id(runner)
		_track_loop(f.loop_id, runner)
	f.loop_repeat = bool(cast.extra.get("loop_repeat", false))
	f.forked = bool(cast.extra.get("forked", false))
	return f


static var _loops := {}
const LOOPS_KEEP := 256


static var _remote := {}


static func loop_running(id: String) -> bool:
	if _remote.has(id):
		return bool(_remote[id]["running"])
	var w: WeakRef = _loops.get(id)
	var runner := w.get_ref() as ProgramLoopRunner if w != null else null
	if runner == null:
		_loops.erase(id)
		return false
	return not runner.finished


static func remote_loop(id: String, running: bool) -> void:
	if not running and not _remote.has(id):
		return
	if running and _remote.has(id) and not bool(_remote[id]["running"]):
		return
	var now := Time.get_ticks_msec()
	if _remote.size() > LOOPS_KEEP:
		for k: String in _remote.keys():
			if now - int(_remote[k]["at"]) > 60000:
				_remote.erase(k)
	_remote[id] = {"running": running, "at": now}


static func _track_loop(id: String, runner: ProgramLoopRunner) -> void:
	if _loops.has(id):
		return
	if _loops.size() > LOOPS_KEEP:
		for k: String in _loops.keys():
			if (_loops[k] as WeakRef).get_ref() == null:
				_loops.erase(k)
	_loops[id] = weakref(runner)


static func _id(o: Object) -> String:
	return "%d:%d" % [Coop.my_id(), o.get_instance_id()]


func to_dict() -> Dictionary:
	return {"by_player": by_player, "gem": gem_id, "set": script_set, "owner_set": owner_set, "fired": fired,
			"pairs": rule_pairs, "tier": tier, "script": has_script, "blocks": blocks_to_next,
			"cast": cast_id, "root": root_id, "root_mult": root_damage_mult, "loop": loop_id,
			"repeat": loop_repeat, "forked": forked}


static func from_dict(d: Dictionary, p_caster: Node) -> HitFacts:
	var f := HitFacts.new()
	f.caster = p_caster
	f.by_player = bool(d.get("by_player", false))
	f.gem_id = str(d.get("gem", "")).left(64)
	f.gem = SkillGemRegistry.get_skill_gem(f.gem_id) if f.gem_id != "" else null
	f.script_set = int(d.get("set", -1))
	f.owner_set = int(d.get("owner_set", maxi(f.script_set, 0)))
	f.fired = _short_list(d.get("fired"), 16)
	for pair in _short_list(d.get("pairs"), 32):
		if pair is Array and pair.size() == 2:
			f.rule_pairs.append(pair)
	f.tier = str(d.get("tier", "")).left(16)
	f.has_script = bool(d.get("script", false))
	f.blocks_to_next = int(d.get("blocks", 0))
	f.cast_id = str(d.get("cast", "")).left(48)
	f.root_id = str(d.get("root", "")).left(48)
	f.root_damage_mult = clampf(float(d.get("root_mult", 1.0)), 0.0, 100.0)
	f.loop_id = str(d.get("loop", "")).left(48)
	f.loop_repeat = bool(d.get("repeat", false))
	f.forked = bool(d.get("forked", false))
	return f


static func _short_list(v: Variant, most: int) -> Array:
	return (v as Array).slice(0, most) if v is Array else []
