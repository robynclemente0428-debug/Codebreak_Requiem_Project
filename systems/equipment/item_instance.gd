class_name ItemInstance
extends Resource

@export var definition: ItemDefinition
@export var rolled_affixes: Array[Dictionary] = []
@export var rarity: String = "normal"
@export var item_level: int = 1
## A "COPY OF" item from Hex's copied stock: the same stats, half the value.
@export var copied := false
## Stims only (see StimRoller): rolled numbers, modifier ids, charges left.
@export var stim_roll: Dictionary = {}
@export var stim_mods: Array[String] = []
@export var charges: int = -1

func get_display_name() -> String:
	if definition.stim != null:
		return StimRoller.display_name(self)
	var prefix := ""
	var suffix := ""
	for entry in rolled_affixes:
		var affix: AffixDefinition = entry.affix
		if affix.affix_type == "prefix" and prefix == "":
			prefix = affix.display_name
		elif affix.affix_type == "suffix" and suffix == "":
			suffix = affix.display_name
	var parts: Array[String] = []
	if copied:
		parts.append("COPY OF")
	if prefix != "":
		parts.append(prefix)
	parts.append(definition.display_name)
	if suffix != "":
		parts.append(suffix)
	return " ".join(parts)

func build_modifiers() -> Array[Modifier]:
	var mods: Array[Modifier] = []
	var sid := "item_%s_" % definition.id

	# the item's own base stats
	for stat in definition.base_stats.keys():
		mods.append(_make_mod(stat, Modifier.ModOp.FLAT_ADD, definition.base_stats[stat], sid + "base"))

	# rolled affixes
	for entry in rolled_affixes:
		var affix: AffixDefinition = entry.affix
		match affix.shape:
			AffixDefinition.AffixShape.DAMAGE_RANGE:
				mods.append(_make_mod(affix.min_stat, Modifier.ModOp.FLAT_ADD, entry.rolled_min, sid + affix.id))
				mods.append(_make_mod(affix.max_stat, Modifier.ModOp.FLAT_ADD, entry.rolled_max, sid + affix.id))
			AffixDefinition.AffixShape.PERCENT_RANGE:
				mods.append(_make_mod(affix.min_stat, Modifier.ModOp.PERCENT_ADD, entry.rolled_value, sid + affix.id))
				mods.append(_make_mod(affix.max_stat, Modifier.ModOp.PERCENT_ADD, entry.rolled_value, sid + affix.id))
			AffixDefinition.AffixShape.PERCENT_MULT_RANGE:
				mods.append(_make_mod(affix.min_stat, Modifier.ModOp.PERCENT_MULT, entry.rolled_value, sid + affix.id))
				mods.append(_make_mod(affix.max_stat, Modifier.ModOp.PERCENT_MULT, entry.rolled_value, sid + affix.id))
			_:
				mods.append(_make_mod(affix.stat, affix.op, entry.rolled_value, sid + affix.id))
	if definition.weapon_type != null and definition.weapon_type.base_range != 0.0:
		mods.append(_make_mod(StatTypes.Stat.ATTACK_RANGE, Modifier.ModOp.FLAT_ADD,
		definition.weapon_type.base_range, sid + "range"))
	return mods

func _make_mod(stat: StatTypes.Stat, op: Modifier.ModOp, value: float, source: String) -> Modifier:
	var m := Modifier.new()
	m.stat = stat
	m.op = op
	m.value = value
	m.source_id = source
	return m

static func make_gem(def: ItemDefinition) -> ItemInstance:
	if def == null:
		push_error("make_gem: the item definition is null, check the file path and that it is an ItemDefinition")
		return null
	var item := ItemInstance.new()
	item.definition = def
	item.rarity = "skill_gem" if def.skill_gem != null else "support_gem"
	return item

func to_dict() -> Dictionary:
	var affixes: Array = []
	for e in rolled_affixes:
		var a := {'id': e.affix.id}
		if e.has('rolled_value'):
			a['value'] = e.rolled_value
		if e.has('rolled_min'):
			a['min'] = e.rolled_min
			a['max'] = e.rolled_max
		affixes.append(a)
	var d := {'item': definition.id, 'rarity': rarity, 'level': item_level, 'affixes': affixes}
	if copied:
		d['copied'] = true
	if definition.stim != null:
		d['stim'] = {'base_amount': stim_roll.get('base_amount', 0.0), 'mods': stim_mods.duplicate(),
				'charges': charges}
	return d


static func from_dict(d: Dictionary) -> ItemInstance:
	var def := ItemDatabase.get_item(str(d.get('item', '')))
	if def == null:
		return null
	var inst := ItemInstance.new()
	inst.definition = def
	inst.rarity = str(d.get('rarity', 'normal'))
	inst.item_level = int(d.get('level', 1))
	inst.copied = bool(d.get('copied', false))
	for a in d.get('affixes', []):
		var affix := ItemGenerator.get_affix(str(a.get('id', '')))
		if affix == null:
			continue          # affix was removed from the game: skip it
		var entry := {'affix': affix}
		if a.has('value'):
			entry['rolled_value'] = float(a['value'])
		if a.has('min'):
			entry['rolled_min'] = float(a['min'])
			entry['rolled_max'] = float(a['max'])
		inst.rolled_affixes.append(entry)
	if def.stim != null:
		var s: Dictionary = d.get('stim', {})
		if s.has('base_amount') and float(s['base_amount']) > 0.0:
			inst.stim_roll['base_amount'] = float(s['base_amount'])
		for m in s.get('mods', []):
			inst.stim_mods.append(str(m))
		inst.charges = int(s.get('charges', -1))
		StimRoller.recompute(inst)
	return inst
