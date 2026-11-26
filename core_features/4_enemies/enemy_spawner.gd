class_name EnemySpawner
extends RefCounted

const RARITY_SCALE := {"normal": 0.8, "magic": 1.3, "rare": 1.5, "champion": 1.8}
const LEVEL_SCALING := {
	StatTypes.Stat.MAX_HEALTH: 0.15,
	StatTypes.Stat.ARMOUR: 0.10,
	StatTypes.Stat.MIN_ATTACK_DAMAGE: 0.07,
	StatTypes.Stat.MAX_ATTACK_DAMAGE: 0.07,
}
const LEVEL_RAMP := {
	StatTypes.Stat.MAX_HEALTH: 0.006,
}
const LEVEL_FLAT := {
	StatTypes.Stat.ARMOUR: 3.0,
}

const ACT_SCALING := 0.5
const ACT_STATS: Array[StatTypes.Stat] = [StatTypes.Stat.MAX_HEALTH, StatTypes.Stat.ARMOUR]


static func act_multiplier_of_scene(scene_path: String) -> float:
	var act := Waypoints.act_of_scene(scene_path)
	return 1.0 + ACT_SCALING * maxi(act.act_number - 1, 0) if act != null else 1.0


static func _act_multiplier(node: Node) -> float:
	while node != null:
		if node.scene_file_path != "" and Waypoints.act_of_scene(node.scene_file_path) != null:
			return act_multiplier_of_scene(node.scene_file_path)
		node = node.get_parent()
	return 1.0


static func spawn_enemy(def: EnemyDefinition, rarity: String, parent: Node,
		world_pos: Variant = null, level: int = 1,
		forced_mods: Variant = null, add_to_random: bool = false) -> Node3D:
	var enemy = def.scene.instantiate()
	parent.add_child(enemy)
	if world_pos != null:
		enemy.global_position = world_pos

	var s: float = RARITY_SCALE.get(rarity, 1.0)
	enemy.apply_size(def.capsule_radius * s, def.capsule_height * s)
	enemy.model_mount.scale = Vector3.ONE * s
	enemy.nav.radius *= s
	if def.model_scene:
		enemy.attach_model(def.model_scene)

	enemy.ai.aggro_range = def.aggro_range
	enemy.ai.attack_range = def.attack_range * s
	enemy.ai.basic_attack_enabled = def.basic_attack_enabled
	enemy.ai.preferred_distance = def.preferred_distance
	enemy.ai.flee_distance = def.flee_distance
	enemy.ai.kite_delay_min = def.kite_delay_min
	enemy.ai.kite_delay_max = def.kite_delay_max
	enemy.stats.base_stats = {
		StatTypes.Stat.MAX_HEALTH: def.max_health,
		StatTypes.Stat.ARMOUR: def.armour,
		StatTypes.Stat.MOVE_SPEED: def.move_speed,
		StatTypes.Stat.MIN_ATTACK_DAMAGE: def.min_attack_damage,
		StatTypes.Stat.MAX_ATTACK_DAMAGE: def.max_attack_damage,
		StatTypes.Stat.ATTACK_SPEED: def.attack_speed,
		StatTypes.Stat.SKILL_DAMAGE_MULT: 1.0,
		StatTypes.Stat.ATTACK_RANGE: def.attack_range * s,
	}
	
	if level > 1:
		for stat in LEVEL_SCALING:
			var scale_mod := Modifier.new()
			scale_mod.stat = stat
			scale_mod.op = Modifier.ModOp.PERCENT_MULT
			scale_mod.value = LEVEL_SCALING[stat] * (level - 1) \
					+ LEVEL_RAMP.get(stat, 0.0) * pow(level - 1, 2)
			scale_mod.source_id = "dungeon_level"
			enemy.stats.add_modifier(scale_mod)
		for stat in LEVEL_FLAT:
			var flat_mod := Modifier.new()
			flat_mod.stat = stat
			flat_mod.op = Modifier.ModOp.FLAT_ADD
			flat_mod.value = LEVEL_FLAT[stat] * (level - 1)
			flat_mod.source_id = "dungeon_level"
			enemy.stats.add_modifier(flat_mod)

	var act_mult := _act_multiplier(parent)
	if act_mult > 1.0:
		for stat in ACT_STATS:
			var act_mod := Modifier.new()
			act_mod.stat = stat
			act_mod.op = Modifier.ModOp.PERCENT_MULT
			act_mod.value = act_mult - 1.0
			act_mod.source_id = "act_scaling"
			enemy.stats.add_modifier(act_mod)

	var mods: Array = []
	if forced_mods == null:
		mods = ModifierRegistry.roll_modifiers(def, rarity)
	else:
		mods = (forced_mods as Array).filter(func(x) -> bool: return x != null)
		if add_to_random:
			for extra in ModifierRegistry.roll_modifiers(def, rarity):
				if not mods.any(func(x) -> bool: return x.id == extra.id):
					mods.append(extra)

	var name_parts: Array[String] = []
	for mod_def in mods:
		for stat_mod in mod_def.stat_modifiers:
			var instance: Modifier = stat_mod.duplicate()
			instance.source_id = "enemymod_%s" % mod_def.id
			enemy.stats.add_modifier(instance)
		name_parts.append(mod_def.display_name_prefix)
		if mod_def.on_spawn_script != null:
			_add_trait(enemy, mod_def.on_spawn_script, mod_def.id)
	for script in def.innate_traits:
		if script != null:
			_add_trait(enemy, script, script.resource_path.get_file().get_basename())

	if "modifiers" in enemy:
		enemy.modifiers = mods
	enemy.rarity = rarity
	enemy.level = level
	enemy.display_name = _with_prefixes(def.display_name, name_parts)
	if not def.skills.is_empty():
		var caster := EnemySkills.new()
		caster.name = "EnemySkills"
		enemy.add_child(caster)
		print("[Spawner] %s skill_flag_overrides=%s  def_path=%s" % [def.id, def.skill_flag_overrides, def.resource_path])
		caster.setup(enemy, enemy.stats, def.skills, def.skill_flag_overrides,
				def.skill_supports, def.skill_support_ids, def.skill_loops)
		caster.skill_cooldown = def.skill_cooldown
		caster.cooldown_jitter = def.cooldown_jitter
		caster.cast_lock_fraction = def.cast_lock_fraction

	enemy.setup()
	Coop.enemy_spawned(enemy, def, rarity, level, mods)
	return enemy


static func empower(enemy: Node3D, health: float, armour: float, damage: float, source := "wave",
		flat_health := 0.0, flat_armour := 0.0) -> void:
	if enemy == null or not "stats" in enemy:
		return
	var given: Array = enemy.get_meta(Coop.NET_BOOST, [])
	given.append([health, armour, damage, source, flat_health, flat_armour])
	enemy.set_meta(Coop.NET_BOOST, given)
	var bonus := {
		StatTypes.Stat.MAX_HEALTH: health,
		StatTypes.Stat.ARMOUR: armour,
		StatTypes.Stat.MIN_ATTACK_DAMAGE: damage,
		StatTypes.Stat.MAX_ATTACK_DAMAGE: damage,
	}
	for stat in bonus:
		if bonus[stat] <= 0.0:
			continue
		var m := Modifier.new()
		m.stat = stat
		m.op = Modifier.ModOp.PERCENT_MULT
		m.value = bonus[stat]
		m.source_id = source
		enemy.stats.add_modifier(m)
	var flat := {StatTypes.Stat.MAX_HEALTH: flat_health, StatTypes.Stat.ARMOUR: flat_armour}
	for stat in flat:
		if flat[stat] <= 0.0:
			continue
		var f := Modifier.new()
		f.stat = stat
		f.op = Modifier.ModOp.FLAT_ADD
		f.value = flat[stat]
		f.source_id = source
		enemy.stats.add_modifier(f)
	var hp = enemy.get("health")
	if hp is HealthComponent:
		hp.revive(1.0)


static func _with_prefixes(base: String, prefixes: Array[String]) -> String:
	var words := " ".join(prefixes)
	if words == "":
		return base
	if base.begins_with("The "):
		return "The %s %s" % [words, base.substr(4)]
	return "%s %s" % [words, base]


static func _add_trait(enemy: Node3D, script: Script, id: String) -> void:
	if not "traits" in enemy:
		return
	var t := Node.new()
	t.set_script(script)
	if t is EnemyTrait:
		t.name = "Trait_%s" % id
		enemy.add_child(t)
		(t as EnemyTrait).setup(enemy)
		enemy.traits.append(t)
	else:
		t.free()
		push_warning("Trait %s: script is not an EnemyTrait" % id)
