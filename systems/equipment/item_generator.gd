extends Node

const DEBUG := false
const MIN_TIER_MULT := 0.01      # an outdated tier keeps at least 1% of its weight

var all_affixes: Array[AffixDefinition] = []
var _affix_by_id: Dictionary = {}

func _ready() -> void:
	_load_affixes("res://data/affixes/")
	print("Loaded %d affixes" % [all_affixes.size()])

func _load_affixes(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("Cannot open %s" % path)
		return
	for sub in dir.get_directories():
		_load_affixes(path.path_join(sub))
	for file_name in dir.get_files():
		# exported builds list resources as "name.tres.remap", so strip that suffix
		if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			var res = load(path.path_join(file_name.trim_suffix(".remap")))
			if res is AffixDefinition:
				all_affixes.append(res)
				_affix_by_id[res.id] = res

func generate_item(def: ItemDefinition, drop_level: int, rarity: String) -> ItemInstance:
	# The item's own level counts too, so a high-level base item can roll high-level affixes.
	if def.skill_gem != null:
		rarity = "skill_gem"
	elif def.support_gem != null:
		rarity = "support_gem"
	var item_level := maxi(drop_level, def.item_level)
	var instance := ItemInstance.new()
	instance.definition = def
	instance.rarity = rarity
	instance.item_level = item_level
	if def.stim != null:                 # stims roll their own numbers and modifiers
		StimRoller.roll(instance)
		return instance
	
	var affix_count := _roll_affix_count(rarity)
	var combined_tags := _get_affix_tags(def)
	if DEBUG: print("Combined tags for %s: %s" % [def.id, combined_tags])
	var eligible = all_affixes.filter(func(a):
		return a.min_item_level <= item_level and _tags_overlap(a.tags, combined_tags)
	)
	if DEBUG: print("Item level %d: %d eligible affixes (of %d)" % [item_level, eligible.size(), all_affixes.size()])
	var prefixes_used := 0
	var suffixes_used := 0
	var used_ids: Dictionary = {}
	var used_exclusivity_keys: Dictionary = {}
	
	for i in affix_count:
		var pool = eligible.filter(func(a):
			if a.id in used_ids: return false
			if a.affix_type == "prefix" and prefixes_used >= 3: return false
			if a.affix_type == "suffix" and suffixes_used >= 3: return false
			for key in _exclusivity_keys(a):
				if key in used_exclusivity_keys:
					return false
			return true
		)
		if pool.is_empty(): break
		var chosen = _weighted_pick(pool)
		used_ids[chosen.id] = true
		for key in _exclusivity_keys(chosen):
			used_exclusivity_keys[key] = true
			if DEBUG: print("Used exclusivity keys: %s" % used_exclusivity_keys)
		if chosen.affix_type == "prefix": prefixes_used += 1
		else: suffixes_used += 1
		
		if chosen.shape == AffixDefinition.AffixShape.DAMAGE_RANGE:
			var roll_t := randf()
			var rolled_min = lerp(chosen.added_min_low, chosen.added_min_high, roll_t)
			var rolled_max = lerp(chosen.added_max_low, chosen.added_max_high, roll_t)
			instance.rolled_affixes.append({
				"affix": chosen,
				"rolled_min": rolled_min,
				"rolled_max": rolled_max,
			})
		elif chosen.shape == AffixDefinition.AffixShape.PERCENT_RANGE:
			var rolled_percent = randf_range(chosen.min_value, chosen.max_value)
			instance.rolled_affixes.append({"affix": chosen, "rolled_value": rolled_percent})
		else:
			var rolled_value = randf_range(chosen.min_value, chosen.max_value)
			instance.rolled_affixes.append({
				"affix": chosen,
				"rolled_value": rolled_value
			})
		
	return instance
	

func _roll_affix_count(rarity: String) -> int:
	match rarity:
		"magic":    return randi_range(1, 2)
		"rare":     return randi_range(3, 6)
		"champion": return randi_range(5, 6)
		_:          return 0      # normal, or an unknown rarity string

func _exclusivity_keys(affix: AffixDefinition) -> Array[String]:
	var keys: Array[String] = []
	var op := int(affix.get_effective_op())
	for group in affix.exclusivity_tags:
		keys.append("%d_%d" % [group, op])
	return keys

func _get_affix_tags(def: ItemDefinition) -> Array[TagTypes.ItemTag]:
	var tags: Array[TagTypes.ItemTag] = []
	tags.append_array(def.allowed_affix_tags)
	if def.weapon_type != null:
		for t in def.weapon_type.tags:
			if t not in tags:
				tags.append(t)
	if def.equipment_type != null:
		for t in def.equipment_type.tags:
			if t not in tags:
				tags.append(t)
	return tags

func _tags_overlap(a: Array, b: Array) -> bool:
	for t in a:
		if t in b:
			return true
	return false
	

## Weighted pick where tiers of the same stat compete by closeness to the item level.
## Every affix in the pool already has min_item_level <= item_level. Within one exclusivity key
## (group + operation, i.e. one family of tiers) the closest tier keeps its full weight and each
## tier further behind it is scaled down by its level_half_life. Stats that only have low tiers
## are not penalised, because they are compared with their own family, not with other stats.
func _weighted_pick(pool: Array[AffixDefinition]) -> AffixDefinition:
	var best_level: Dictionary = {}      # exclusivity key -> highest min_item_level in the pool
	for a in pool:
		for key in _exclusivity_keys(a):
			best_level[key] = maxi(int(best_level.get(key, 0)), a.min_item_level)

	var weights: Array[float] = []
	var total := 0.0
	for a in pool:
		var behind := 0
		for key in _exclusivity_keys(a):
			behind = maxi(behind, int(best_level[key]) - a.min_item_level)
		var w: float = a.weight * maxf(a.get_tier_multiplier(behind), MIN_TIER_MULT)
		weights.append(w)
		total += w

	var roll := randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll < 0.0:
			return pool[i]
	return pool[pool.size() - 1]

func get_affix(id: String) -> AffixDefinition:
	return _affix_by_id.get(id)
