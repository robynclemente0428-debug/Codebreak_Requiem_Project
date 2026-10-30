class_name EnemySpawner
extends RefCounted

const RARITY_SCALE := {"normal": 0.8, "magic": 1.3, "rare": 1.5, "champion": 1.8}
# Bonus per level above 1, as a fraction (0.12 = +12% of base per level)
const LEVEL_SCALING := {
	StatTypes.Stat.MAX_HEALTH: 0.12,
	StatTypes.Stat.ARMOUR: 0.08,
	StatTypes.Stat.MIN_ATTACK_DAMAGE: 0.07,
	StatTypes.Stat.MAX_ATTACK_DAMAGE: 0.07,
}

## forced_mods:   null = roll the modifiers as usual (every existing call does this).
##                An Array of EnemyModifierDefinition = use those instead of rolling.
## add_to_random: only with forced_mods. true = keep the rolled modifiers and add yours on top.
static func spawn_enemy(def: EnemyDefinition, rarity: String, parent: Node,
		world_pos: Variant = null, level: int = 1,
		forced_mods: Variant = null, add_to_random: bool = false) -> Node3D:
	var enemy = def.scene.instantiate()
	parent.add_child(enemy)                     # @onready vars resolve here
	if world_pos != null:
		enemy.global_position = world_pos       # set before setup() runs

	var s: float = RARITY_SCALE.get(rarity, 1.0)
	enemy.apply_size(def.capsule_radius * s, def.capsule_height * s)   # collision matches the model
	enemy.model_mount.scale = Vector3.ONE * s                          # visual size
	enemy.nav.radius *= s                                              # avoidance radius
	if def.model_scene:
		enemy.attach_model(def.model_scene)

	enemy.ai.aggro_range = def.aggro_range
	enemy.ai.attack_range = def.attack_range * s   # bigger body, so it reaches further
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
		# Skills read these. Without SKILL_DAMAGE_MULT an enemy's skill damage would be 0.
		StatTypes.Stat.SKILL_DAMAGE_MULT: 1.0,
		StatTypes.Stat.ATTACK_RANGE: def.attack_range * s,
	}
	
	if level > 1:
		for stat in LEVEL_SCALING:
			var scale_mod := Modifier.new()
			scale_mod.stat = stat
			scale_mod.op = Modifier.ModOp.PERCENT_MULT
			scale_mod.value = LEVEL_SCALING[stat] * (level - 1)
			scale_mod.source_id = "dungeon_level"
			enemy.stats.add_modifier(scale_mod)

	var mods: Array = []
	if forced_mods == null:
		mods = ModifierRegistry.roll_modifiers(def, rarity)
	else:
		mods = (forced_mods as Array).filter(func(x) -> bool: return x != null)   # skip empty slots
		if add_to_random:
			for extra in ModifierRegistry.roll_modifiers(def, rarity):
				if not mods.any(func(x) -> bool: return x.id == extra.id):       # no duplicates
					mods.append(extra)

	var name_parts: Array[String] = []
	for mod_def in mods:
		for stat_mod in mod_def.stat_modifiers:
			var instance: Modifier = stat_mod.duplicate()
			instance.source_id = "enemymod_%s" % mod_def.id
			enemy.stats.add_modifier(instance)
		name_parts.append(mod_def.display_name_prefix)

	if "modifiers" in enemy:                    # needs `var modifiers: Array = []` on enemy_base.gd
		enemy.modifiers = mods                  # the hover plate reads this
	enemy.rarity = rarity                       # needs `var rarity := "normal"` on enemy_base.gd
	enemy.display_name = ("%s %s" % [" ".join(name_parts), def.display_name]).strip_edges()
	if not def.skills.is_empty():               # needs `skills` on EnemyDefinition
		var caster := EnemySkills.new()
		caster.name = "EnemySkills"
		enemy.add_child(caster)
		print("[Spawner] %s skill_flag_overrides=%s  def_path=%s" % [def.id, def.skill_flag_overrides, def.resource_path])
		caster.setup(enemy, enemy.stats, def.skills, def.skill_flag_overrides,
				def.skill_supports, def.skill_support_ids)
		caster.skill_cooldown = def.skill_cooldown
		caster.cooldown_jitter = def.cooldown_jitter
		caster.cast_lock_fraction = def.cast_lock_fraction

	enemy.setup()                               # LAST step
	return enemy
