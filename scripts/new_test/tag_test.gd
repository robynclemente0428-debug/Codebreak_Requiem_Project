extends Control
## Tag system test scene. Run it with F6.
## Reads every definition in your data folders and checks that eligibility tags,
## exclusivity groups and the generators agree with each other.
## Needs the ItemGenerator, ModifierRegistry and SkillGemRegistry autoloads.

@export var trials := 200                        # generations per item / enemy / rarity
@export var item_level := 100                    # level used by the coverage section
@export var test_levels: Array[int] = [1, 30, 60, 100]   # item levels the generation test rolls at
@export var enemy_dir := 'res://data/enemies/'   # where your EnemyDefinition .tres files are
@export var item_dir := 'res://data/items/'      # where your ItemDefinition .tres files are

const ITEM_RARITIES := ['magic', 'rare']
const ENEMY_MIN_MODS := {'magic': 1, 'rare': 2, 'champion': 4}
const TAG_FIELDS := ['tags', 'allowed_affix_tags', 'allowed_modifier_tags', 'allowed_tags',
	'exclusivity_tags', 'exclusivity_groups']

var _out: RichTextLabel
var _lines: Array[String] = []
var _pass := 0
var _fail := 0
var _warn := 0
var _item_enum: Dictionary = {}
var _enemy_enum: Dictionary = {}
var _gem_enum: Dictionary = {}
var _group_enum: Dictionary = {}
var _items: Array = []
var _affixes: Array = []
var _modifiers: Array = []
var _skill_gems: Array = []
var _support_gems: Array = []


func _ready() -> void:
	_build_ui()
	_run_all()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var btn := Button.new()
	btn.text = 'Run again'
	btn.pressed.connect(_run_all)
	box.add_child(btn)

	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.selection_enabled = true
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_out)


func _run_all() -> void:
	_lines.clear()
	_pass = 0
	_fail = 0
	_warn = 0
	_item_enum = _tag_enum(['ItemTag', 'Tag'])
	_enemy_enum = _tag_enum(['EnemyTag'])
	_gem_enum = _tag_enum(['GemTag', 'TagGem'])
	_group_enum = _tag_enum(['Group'])

	_test_stale_tags()
	_load_registries()
	var enemies := _load_enemies()
	_test_data_sanity(enemies)
	_test_coverage(enemies)
	_test_items()
	_test_enemies(enemies)
	_test_skills()
	_test_tier_weighting()

	var summary := '[b]%d passed   %d failed   %d warnings[/b]' % [_pass, _fail, _warn]
	_out.clear()
	_out.append_text(summary + '\n' + '\n'.join(_lines))
	print_rich(summary)


# ------------------------------------------------------------------
# 0. Old string tags still stored in .tres files
# ------------------------------------------------------------------
## Changing a field from strings to an enum array makes Godot print
## 'Unable to convert array index 0 from String to int' when it loads a file that
## still holds the old strings. This lists exactly which files and fields.
func _test_stale_tags() -> void:
	_head('0. Old string tags still stored in .tres files')
	var regex := RegEx.new()
	regex.compile('(?m)^(' + '|'.join(TAG_FIELDS) + ')\\s*=\\s*(PackedStringArray\\(|Array\\[String\\]\\(|\\[\\s*")')
	var found := 0
	for path in _find_tres('res://data/'):
		var text := FileAccess.get_file_as_string(path)
		for m in regex.search_all(text):
			_bad('%s: "%s" still holds old string tags. Open the file and re-pick them in the Inspector.'
				% [path, m.get_string(1)])
			found += 1
	if found == 0:
		_ok('No .tres file under res://data/ stores string tags')


func _find_tres(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_find_tres(dir_path.path_join(sub)))
	for file_name in dir.get_files():
		if file_name.ends_with('.tres'):
			out.append(dir_path.path_join(file_name))
	return out


# ------------------------------------------------------------------
# 1. Data sanity
# ------------------------------------------------------------------
func _test_data_sanity(enemies: Array[EnemyDefinition]) -> void:
	_head('1. Data sanity (empty or invalid tags are the silent "nothing rolls" bug)')
	var before := _fail

	var no_group := 0
	for a in _affixes:
		if a.tags.is_empty():
			_bad("Affix '%s' has no tags and can never roll" % a.id)
		_check_valid(a.tags, _item_enum, "Affix '%s'" % a.id)
		if _groups(a).is_empty():
			no_group += 1

	for def in _items:
		var tags: Array = _item_tags(def)
		if tags.is_empty():
			_bad("Item '%s' has no affix tags (own or from its weapon type), so nothing rolls on it" % def.id)
		_check_valid(tags, _item_enum, "Item '%s'" % def.id)

	for e in enemies:
		if e.allowed_modifier_tags.is_empty():
			_bad("Enemy '%s' has no allowed_modifier_tags, so it never rolls modifiers" % e.id)
		_check_valid(e.allowed_modifier_tags, _enemy_enum, "Enemy '%s'" % e.id)

	for m in _modifiers:
		if m.tags.is_empty():
			_bad("Enemy modifier '%s' has no tags and can never roll" % m.id)
		_check_valid(m.tags, _enemy_enum, "Enemy modifier '%s'" % m.id)

	for gem in _skill_gems:
		if gem.tags.is_empty():
			_bad("Skill gem '%s' has no tags, so no support is compatible" % gem.id)
		_check_valid(gem.tags, _gem_enum, "Skill gem '%s'" % gem.id)

	for sup in _support_gems:
		if sup.allowed_tags.is_empty():
			_bad("Support gem '%s' has no allowed_tags, so it fits no skill" % sup.id)
		_check_valid(sup.allowed_tags, _gem_enum, "Support gem '%s'" % sup.id)

	if _fail == before:
		_ok('No empty or invalid tag arrays')
	_info('%d of %d affixes have no exclusivity group (they never conflict with anything)'
		% [no_group, _affixes.size()])


# ------------------------------------------------------------------
# 2. Coverage
# ------------------------------------------------------------------
func _test_coverage(enemies: Array[EnemyDefinition]) -> void:
	_head('2. Coverage (what can roll where)')
	var before := _warn

	for a in _affixes:
		var found := false
		for def in _items:
			if _overlap(a.tags, _item_tags(def)):
				found = true
				break
		if not found:
			_warning("Affix '%s' [%s] matches no item" % [a.id, _names(a.tags, _item_enum)])

	for def in _items:
		var tags: Array = _item_tags(def)
		var prefixes := 0
		var suffixes := 0
		for a in _affixes:
			if _available(a, item_level) and _overlap(a.tags, tags):
				if a.affix_type == 'prefix':
					prefixes += 1
				else:
					suffixes += 1
		_info("Item '%s' [%s]: %d prefixes, %d suffixes eligible"
			% [def.id, _names(tags, _item_enum), prefixes, suffixes])
		if prefixes + suffixes < 3:
			_warning("Item '%s' has fewer than 3 eligible affixes, rare items can't fill up" % def.id)

	for m in _modifiers:
		var used := false
		for e in enemies:
			if _overlap(m.tags, e.allowed_modifier_tags):
				used = true
				break
		if not used:
			_warning("Enemy modifier '%s' [%s] matches no enemy" % [m.id, _names(m.tags, _enemy_enum)])

	for e in enemies:
		var pool := 0
		for m in _modifiers:
			if _overlap(m.tags, e.allowed_modifier_tags):
				pool += 1
		_info("Enemy '%s' [%s]: %d modifiers eligible"
			% [e.id, _names(e.allowed_modifier_tags, _enemy_enum), pool])
		if pool < 5:
			_warning("Enemy '%s' has %d eligible modifiers, champions roll 4-5" % [e.id, pool])

	for sup in _support_gems:
		var fits := false
		for gem in _skill_gems:
			if _overlap(sup.allowed_tags, gem.tags):
				fits = true
				break
		if not fits:
			_warning("Support gem '%s' [%s] fits no skill gem" % [sup.id, _names(sup.allowed_tags, _gem_enum)])

	if _warn == before:
		_ok('Everything that can roll has somewhere to roll')


# ------------------------------------------------------------------
# 3. Equipment generation
# ------------------------------------------------------------------
func _test_items() -> void:
	_head('3. Equipment generation (%d items per item, rarity and level)' % trials)
	var rolled: Dictionary = {}          # affix id -> times rolled
	var level_text := ', '.join(test_levels.map(func(l): return str(l)))

	for def in _items:
		var item_tags: Array = _item_tags(def)
		for rarity in ITEM_RARITIES:
			var problems: Dictionary = {}
			var thin: Array[String] = []
			var min_all := 99
			var max_all := 0
			for lvl in test_levels:
				var min_n := 99
				for i in trials:
					var item: ItemInstance = ItemGenerator.generate_item(def, lvl, rarity)
					var n := item.rolled_affixes.size()
					min_n = mini(min_n, n)
					max_all = maxi(max_all, n)
					_check_item(item, item_tags, problems, rolled)
				min_all = mini(min_all, min_n)
				if (rarity == 'rare' and min_n < 3) or (rarity == 'magic' and min_n < 1):
					thin.append('%d (as few as %d)' % [maxi(lvl, def.item_level), min_n])

			for msg in problems.keys():
				_bad('%s (%s): %s' % [def.id, rarity, msg])
			if problems.is_empty():
				_ok('%s (%s): %d-%d affixes per item at levels %s, no violations'
					% [def.id, rarity, min_all, max_all, level_text])
			if not thin.is_empty():
				_warning('%s (%s): too few affixes at item level %s. The eligible pool is too small or too exclusive there.'
					% [def.id, rarity, ', '.join(thin)])

	var never: Array[String] = []
	for a in _affixes:
		if not rolled.has(a.id):
			never.append(a.id)
	if never.is_empty():
		_ok('Every affix rolled at least once')
	else:
		_warning('Never rolled at levels %s: %s (check tags, weight, and min_item_level)'
			% [level_text, ', '.join(never)])


func _check_item(item: ItemInstance, item_tags: Array, problems: Dictionary, counts: Dictionary) -> void:
	var entries: Array = item.rolled_affixes
	var seen_ids: Dictionary = {}
	var prefixes := 0
	var suffixes := 0

	for i in entries.size():
		var a: AffixDefinition = entries[i]['affix']
		counts[a.id] = int(counts.get(a.id, 0)) + 1

		if not _overlap(a.tags, item_tags):
			problems["'%s' rolled on an item whose tags don't overlap its own" % a.id] = true
		if a.id in seen_ids:
			problems["'%s' rolled twice on one item" % a.id] = true
		seen_ids[a.id] = true

		if a.affix_type == 'prefix':
			prefixes += 1
		else:
			suffixes += 1

		for j in range(i + 1, entries.size()):
			var b: AffixDefinition = entries[j]['affix']
			if a.get_effective_op() == b.get_effective_op() and _overlap(_groups(a), _groups(b)):
				problems["'%s' and '%s' share an exclusivity group and operation but rolled together" % [a.id, b.id]] = true

	if prefixes > 3:
		problems['More than 3 prefixes on one item'] = true
	if suffixes > 3:
		problems['More than 3 suffixes on one item'] = true


# ------------------------------------------------------------------
# 4. Enemy modifiers
# ------------------------------------------------------------------
func _test_enemies(enemies: Array[EnemyDefinition]) -> void:
	_head('4. Enemy modifiers (%d rolls per enemy and rarity)' % trials)
	if enemies.is_empty():
		_info('No enemy definitions loaded, skipping')
		return

	for e in enemies:
		for rarity in ENEMY_MIN_MODS.keys():
			var problems: Dictionary = {}
			var min_n := 99
			for i in trials:
				var mods: Array = ModifierRegistry.roll_modifiers(e, rarity)
				min_n = mini(min_n, mods.size())
				var ids: Dictionary = {}
				for m in mods:
					if not _overlap(m.tags, e.allowed_modifier_tags):
						problems["'%s' rolled but its tags don't overlap the enemy's" % m.id] = true
					if m.id in ids:
						problems["'%s' rolled twice on one enemy" % m.id] = true
					ids[m.id] = true

			for msg in problems.keys():
				_bad('%s (%s): %s' % [e.id, rarity, msg])
			if problems.is_empty():
				_ok('%s (%s): min %d modifiers, no violations' % [e.id, rarity, min_n])
			if min_n < int(ENEMY_MIN_MODS[rarity]):
				_warning('%s (%s): rolled as few as %d modifiers (expected at least %d), the eligible pool is too small'
					% [e.id, rarity, min_n, ENEMY_MIN_MODS[rarity]])


# ------------------------------------------------------------------
# 5. Skills and supports
# ------------------------------------------------------------------
func _test_skills() -> void:
	_head('5. Skills and supports')
	var all_stats: Array = StatTypes.Stat.values()
	var problems := 0

	for gem in _skill_gems:
		var compatible: Array[String] = []
		var blocked: Array[String] = []
		var baseline := _make_skill(gem, [])

		for sup in _support_gems:
			var fits := _overlap(sup.allowed_tags, gem.tags)
			if fits:
				compatible.append(sup.id)
			else:
				blocked.append(sup.id)
				# An incompatible support must not change any stat of this skill.
				var with_support := _make_skill(gem, [sup])
				for s in all_stats:
					if not is_equal_approx(with_support.get_stat(s), baseline.get_stat(s)):
						_bad("Support '%s' is incompatible with '%s' but still changed a stat" % [sup.id, gem.id])
						problems += 1
						break

		_info("Skill '%s' [%s]: accepts %s | blocks %s" % [
			gem.id, _names(gem.tags, _gem_enum),
			', '.join(compatible) if not compatible.is_empty() else 'nothing',
			', '.join(blocked) if not blocked.is_empty() else 'nothing'])

	if problems == 0:
		_ok('Incompatible supports never change a skill')


# ------------------------------------------------------------------
# 6. Tier weighting
# ------------------------------------------------------------------
const CLOSEST_TIER_MIN_SHARE := 0.5     # the closest tier should win at least this often
const TIER_PICKS := 1000

## Only runs once AffixDefinition has get_tier_multiplier() and the generator's _weighted_pick(pool).
func _test_tier_weighting() -> void:
	_head('6. Tier weighting (closest tier of a stat should dominate at its item level)')
	if _affixes.is_empty() or not _affixes[0].has_method('get_tier_multiplier'):
		_info('AffixDefinition has no get_tier_multiplier(), skipping')
		return

	var problems := 0

	# The multiplier itself: 1.0 at zero levels behind, then never rising, never zero.
	for a in _affixes:
		var prev: float = a.get_tier_multiplier(0)
		if not is_equal_approx(prev, 1.0):
			_bad("'%s' should have multiplier 1.0 when it is the closest tier" % a.id)
			problems += 1
		for behind in range(1, 101):
			var m: float = a.get_tier_multiplier(behind)
			if m > prev + 0.0001 or m <= 0.0 or m > 1.0:
				_bad("'%s' has a bad tier multiplier (%.4f) at %d levels behind" % [a.id, m, behind])
				problems += 1
				break
			prev = m

	# Tier families: affixes sharing an exclusivity key (group + effective operation).
	var families: Dictionary = {}
	for a in _affixes:
		for g in _groups(a):
			var key := '%s / op %d' % [_names([g], _group_enum), int(a.get_effective_op())]
			if not families.has(key):
				families[key] = []
			families[key].append(a)

	for key in families.keys():
		var members: Array = families[key]
		var levels: Array = []
		for a in members:
			if a.min_item_level not in levels:
				levels.append(a.min_item_level)
		levels.sort()
		if levels.size() < 2:
			continue

		for lvl in levels.slice(1):                      # skip the first tier (nothing to compete with)
			var pool: Array[AffixDefinition] = []
			for a in members:
				if a.min_item_level <= lvl:
					pool.append(a)
			var closest_hits := 0
			for i in TIER_PICKS:
				var picked: AffixDefinition = ItemGenerator.call('_weighted_pick', pool)
				if picked.min_item_level == lvl:
					closest_hits += 1
			var share := float(closest_hits) / TIER_PICKS
			var text := "Family %s at item level %d: the closest tier is picked %d%% of the time (%d affixes in the pool)" \
				% [key, lvl, roundi(share * 100.0), pool.size()]
			if share < CLOSEST_TIER_MIN_SHARE:
				_warning(text + '. Lower level_half_life or raise the weights of the higher tiers.')
				problems += 1
			else:
				_info(text)

	if problems == 0:
		_ok('Tier multipliers behave, and the closest tier dominates in every family')


func _make_skill(gem: SkillGemDefinition, supports: Array) -> SkillInstance:
	var inst := SkillInstance.new()
	inst.gem = gem
	for s in supports:
		inst.supports.append(s)
	inst.rebuild()
	return inst


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
## Finds each registry's definitions by TYPE, so it doesn't matter what your variables are called.
func _load_registries() -> void:
	_items = _collect(ItemGenerator, func(x): return x is ItemDefinition, ['all_items', 'items'])
	if _items.is_empty():
		# ItemGenerator doesn't hold item definitions, so read them from the folder.
		_items = _load_definitions(item_dir, func(x): return x is ItemDefinition)
	_affixes = _collect(ItemGenerator, func(x): return x is AffixDefinition, ['all_affixes', 'affixes'])
	_modifiers = _collect(ModifierRegistry, func(x): return x is EnemyModifierDefinition, ['all_modifiers', 'modifiers'])
	_skill_gems = _collect(SkillGemRegistry, func(x): return x is SkillGemDefinition, ['all_skill_gems', 'skill_gems'])
	_support_gems = _collect(SkillGemRegistry, func(x): return x is SupportGemDefinition, ['all_support_gems', 'support_gems'])

	_info('Loaded %d items, %d affixes, %d enemy modifiers, %d skill gems, %d support gems'
		% [_items.size(), _affixes.size(), _modifiers.size(), _skill_gems.size(), _support_gems.size()])
	if _items.is_empty():
		_warning('No ItemDefinition found in ItemGenerator or in %s. Set Item Dir on the TagTest node.' % item_dir)
	if _affixes.is_empty():
		_warning('No AffixDefinition found on the ItemGenerator autoload.')
	if _modifiers.is_empty():
		_warning('No EnemyModifierDefinition found on the ModifierRegistry autoload.')
	if _skill_gems.is_empty():
		_warning('No SkillGemDefinition found on the SkillGemRegistry autoload.')


## Looks at the preferred variable names first, then at every script variable on the node.
func _collect(source: Object, is_right_type: Callable, preferred: Array) -> Array:
	for prop_name in preferred:
		var found := _as_array(source.get(prop_name))
		if not found.is_empty() and is_right_type.call(found[0]):
			return found
	for prop in source.get_property_list():
		if (int(prop['usage']) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var found := _as_array(source.get(prop['name']))
		if not found.is_empty() and is_right_type.call(found[0]):
			return found
	return []


func _as_array(value: Variant) -> Array:
	if value is Dictionary:
		return value.values()
	if value is Array:
		return value
	return []


func _load_definitions(dir_path: String, is_right_type: Callable) -> Array:
	var out: Array = []
	for path in _find_tres(dir_path):
		var res := load(path)
		if res != null and is_right_type.call(res):
			out.append(res)
	return out


## Uses the generator's own _get_affix_tags() when it has one, so the real function is tested.
## Otherwise falls back to the same rule: allowed_affix_tags plus the weapon type's tags.
func _item_tags(def: ItemDefinition) -> Array:
	if ItemGenerator.has_method('_get_affix_tags'):
		return ItemGenerator.call('_get_affix_tags', def)
	var tags: Array = []
	tags.append_array(def.allowed_affix_tags)
	if def.weapon_type != null:
		for t in def.weapon_type.tags:
			if t not in tags:
				tags.append(t)
	return tags


func _load_enemies() -> Array[EnemyDefinition]:
	var out: Array[EnemyDefinition] = []
	var dir := DirAccess.open(enemy_dir)
	if dir == null:
		_warning('Enemy folder %s not found. Set Enemy Dir on the TagTest node.' % enemy_dir)
		return out
	for file_name in dir.get_files():
		var clean := file_name.trim_suffix('.remap')
		if clean.ends_with('.tres'):
			var res := load(enemy_dir + clean)
			if res is EnemyDefinition:
				out.append(res)
	return out


## Uses the affix's own level window when it has one.
func _available(a: AffixDefinition, level: int) -> bool:
	if a.has_method('is_available_at'):
		return a.is_available_at(level)
	return level >= a.min_item_level


func _overlap(a: Array, b: Array) -> bool:
	for t in a:
		if t in b:
			return true
	return false


## Works before and after you rename exclusivity_tags to exclusivity_groups.
func _groups(a: AffixDefinition) -> Array:
	var g = a.get('exclusivity_groups')
	if g == null:
		g = a.get('exclusivity_tags')
	return g if g != null else []


## Finds an enum inside TagTypes by trying each candidate name.
func _tag_enum(candidates: Array) -> Dictionary:
	for info in ProjectSettings.get_global_class_list():
		if info['class'] == 'TagTypes':
			var script: GDScript = load(info['path'])
			var consts: Dictionary = script.get_script_constant_map()
			for n in candidates:
				if consts.has(n):
					return consts[n]
	return {}


func _names(tags: Array, e: Dictionary) -> String:
	var parts: Array[String] = []
	for t in tags:
		parts.append(str(e.find_key(t)) if not e.is_empty() else str(t))
	return ', '.join(parts)


func _check_valid(tags: Array, e: Dictionary, who: String) -> void:
	if e.is_empty():
		return
	for t in tags:
		if not e.values().has(t):
			_bad('%s has tag value %s which does not exist in its enum (deleted or reordered?)' % [who, str(t)])


func _head(msg: String) -> void:
	_log('\n[b]%s[/b]' % msg)


func _ok(msg: String) -> void:
	_pass += 1
	_log('[color=#6c6]PASS[/color]  ' + msg)


func _bad(msg: String) -> void:
	_fail += 1
	_log('[color=#e55]FAIL[/color]  ' + msg)


func _warning(msg: String) -> void:
	_warn += 1
	_log('[color=#db4]WARN[/color]  ' + msg)


func _info(msg: String) -> void:
	_log('[color=#999]info[/color]  ' + msg)


func _log(msg: String) -> void:
	_lines.append(msg)
	print_rich(msg)
