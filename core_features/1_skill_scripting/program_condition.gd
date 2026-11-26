class_name ProgramCondition
extends Resource

enum Scope { CAST, HIT }


func type_id() -> String:
	return ""


func scope() -> Scope:
	return Scope.CAST


func required_support() -> String:
	return ""


func on_fired(_cast: SkillCast) -> void:
	pass


func per_repeat() -> bool:
	return false


func defensive() -> bool:
	return false


func keyword() -> String:
	return ""


func modular() -> bool:
	return false


func param_text(_param: String) -> String:
	return ""


func fired_id() -> String:
	return type_id()


func allows_repeats() -> bool:
	return false


func needs_loop() -> bool:
	return false


func changes_during_cast() -> bool:
	return false


func is_true(_cast: SkillCast, _target: Node) -> bool:
	return false


func cost_multiplier() -> float:
	return 1.0


func describe() -> String:
	return type_id()


func param_names() -> PackedStringArray:
	return PackedStringArray()


func param_step(_param: String) -> float:
	return 1.0


func param_label(param: String) -> String:
	return param.to_upper()


func palette_name() -> String:
	return describe().trim_prefix("WHEN ")


func nudge_param(param: String, clicks: int) -> void:
	var current = get(param)
	if current is int:
		set(param, current + int(param_step(param)) * clicks)
	else:
		set(param, snappedf(float(current) + param_step(param) * clicks, 0.001))
	clamp_params()


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


static func health_fraction(node: Node) -> float:
	if not is_instance_valid(node):
		return 1.0
	var h := node.get("health") as HealthComponent
	if h == null or h.stats == null:
		return 1.0
	var max_hp := h.stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	return h.current_health / max_hp if max_hp > 0.0 else 1.0
