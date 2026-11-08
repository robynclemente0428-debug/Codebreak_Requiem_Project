extends Node

var all_skill_gems: Dictionary = {}      # id -> SkillGemDefinition
var all_support_gems: Dictionary = {}    # id -> SupportGemDefinition

# id -> {String flag_name -> value}
var _skill_base_flags: Dictionary = {
	"strike": {"arc_angle": 90.0,"range_bonus": 0.5, "combo_grace": 0.5},
	"slam": {"radius": 2.0, "center_offset": 1.5, "recovery_mult": 1.5},
	"blast": {"max_projectiles": 1.0, "spread_angle": 15.0, "speed": 14.0, "range": 20.0,
		"radius": 2.0, "spawn_height": 1.0, "spawn_forward": 0.8, "recovery_mult": 2.0},
	"shoot": {"max_projectiles": 1.0, "spread_angle": 6.0, "speed": 60.0, "range": 30.0,
		"pierce": 0.0, "pierce_falloff": 0.2, "spawn_height": 1.0, "spawn_forward": 0.8,
		"recovery_mult": 0.1},
}

# id -> {String flag_name -> value}
var _support_flag_modifiers: Dictionary = {
	"cleave_support": {"arc_angle": 90.0, "range_bonus": 2.0},
	"many_projectiles_support": {"max_projectiles": 4, "spread_angle": -8.0},
	"explode_on_kill_support": {"explode_radius": 2.5, "explode_damage": 0.5},
	# Slam-only supports
	"aftershock_support": {"aftershock_count": 1.0, "aftershock_delay": 0.4, "aftershock_damage": 0.4, "aftershock_growth": 0.35},
	"tremor_chain_support": {"tremor_max_chain": 3.0, "tremor_damage": 0.5, "tremor_radius": 0.6, "tremor_delay": 0.15},
	# Strike-only supports
	"finishing_blow_support": {"finisher_every": 3.0, "finisher_damage": 0.8, "finisher_arc": 60.0, "finisher_reach": 1.0},
	"rending_wave_support": {"wave_range": 8.0, "wave_width": 3.2, "wave_speed": 16.0, "wave_damage": 0.6, "wave_delay": 0.05},
	# Blast-only (scripting) supports
	"variable_store_support": {"var_store_gain": 1.0, "var_store_max": 10.0},
	"pointer_support": {"pointer_range": 6.0, "pointer_turn": 90.0, "pointer_hops": 1.0, "pointer_hop_damage": 0.5},
	"try_except_support": {"except_retries": 1.0, "except_refund": 1.0, "except_max_stacks": 3.0, "except_stack_damage": 0.25},
	# Shoot-only supports
	"fork_support": {"fork_count": 2.0, "fork_angle": 30.0, "fork_damage": 0.6},
	"breakpoint_support": {"breakpoint_bonus": 0.3, "breakpoint_hits": 5.0, "breakpoint_burst": 2.0, "breakpoint_duration": 6.0},
	"overclock_support": {"overclock_speed": 0.08, "overclock_max": 5.0, "overclock_grace": 0.6},
	# Any skill
	"multicast_support": {"multicast_effectiveness": 0.6, "multicast_offset": 0.0, "multicast_linger": 0.6},
	"rollback_support": {"rollback_window": 3.0, "rollback_cooldown": 20.0, "rollback_trigger": 0.3},
}

func _ready() -> void:
	_load_skill_gems("res://data/skill_gems/")
	_load_support_gems("res://data/support_gems/")
	print("Loaded %d skill gems, %d support gems" % [all_skill_gems.size(), all_support_gems.size()])

func _resource_files(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("SkillGemRegistry: can't open %s" % dir_path)
		return result
	for file_name in dir.get_files():
		# Exported builds list remapped resources as "name.tres.remap" (or .res)
		var clean := file_name.trim_suffix(".remap")
		if clean.ends_with(".tres") or clean.ends_with(".res"):
			result.append(dir_path.path_join(clean))
	return result

func _load_skill_gems(dir_path: String) -> void:
	for path in _resource_files(dir_path):
		var def := load(path) as SkillGemDefinition
		if def == null:
			continue
		if _skill_base_flags.has(def.id):
			def.base_flags = _skill_base_flags[def.id]
		all_skill_gems[def.id] = def

func _load_support_gems(dir_path: String) -> void:
	for path in _resource_files(dir_path):
		var def := load(path) as SupportGemDefinition
		if def == null:
			continue
		if _support_flag_modifiers.has(def.id):
			def.flag_modifiers = _support_flag_modifiers[def.id]
		all_support_gems[def.id] = def
func get_skill_gem(id: String) -> SkillGemDefinition:
	return all_skill_gems.get(id)

func get_support_gem(id: String) -> SupportGemDefinition:
	return all_support_gems.get(id)
