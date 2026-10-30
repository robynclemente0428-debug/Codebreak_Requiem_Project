class_name AttributeEffects
extends RefCounted
## Turns a character's attributes into modifiers on their StatComponent.
## Safe to call again at any time (level-up, respec): it removes its own modifiers first.
##
## Use bind() once when the character is set up. It applies the effects and then re-applies
## them whenever Strength, Dexterity or Intelligence change, so attributes from equipment,
## buffs or level-ups all count. (apply() alone only uses the attributes at that moment.)

const SOURCE_PREFIX := 'attr_'

# Tuning placeholders. Change freely, nothing is saved from these numbers.
const HEALTH_PER_STRENGTH := 2.0              # +2 max health per point (flat)
const ATTACK_SPEED_PER_DEXTERITY := 0.005     # +0.5% attack speed per point
const SKILL_DAMAGE_PER_INTELLIGENCE := 0.01   # +1% skill damage per point


## Apply now, and again every time an attribute changes. Call once per StatComponent.
static func bind(stats: StatComponent) -> void:
	apply(stats)
	if stats.has_meta(&"attribute_watcher"):
		return
	var watcher := _Watcher.new()
	watcher.stats = stats
	watcher.last = attributes_of(stats)
	stats.set_meta(&"attribute_watcher", watcher)
	stats.stats_changed.connect(watcher.on_stats_changed)


## Current (whole) Strength, Dexterity and Intelligence.
static func attributes_of(stats: StatComponent) -> Vector3:
	return Vector3(floorf(stats.get_stat(StatTypes.Stat.STRENGTH)),
		floorf(stats.get_stat(StatTypes.Stat.DEXTERITY)),
		floorf(stats.get_stat(StatTypes.Stat.INTELLIGENCE)))


static func apply(stats: StatComponent) -> void:
	stats.remove_by_source_prefix(SOURCE_PREFIX)

	var strength := floorf(stats.get_stat(StatTypes.Stat.STRENGTH))
	var dexterity := floorf(stats.get_stat(StatTypes.Stat.DEXTERITY))
	var intelligence := floorf(stats.get_stat(StatTypes.Stat.INTELLIGENCE))

	_add(stats, StatTypes.Stat.MAX_HEALTH, Modifier.ModOp.FLAT_ADD,
		strength * HEALTH_PER_STRENGTH, SOURCE_PREFIX + Attr.STRENGTH)
	_add(stats, StatTypes.Stat.ATTACK_SPEED, Modifier.ModOp.PERCENT_ADD,
		dexterity * ATTACK_SPEED_PER_DEXTERITY, SOURCE_PREFIX + Attr.DEXTERITY)
	_add(stats, StatTypes.Stat.SKILL_DAMAGE_MULT, Modifier.ModOp.PERCENT_ADD,
		intelligence * SKILL_DAMAGE_PER_INTELLIGENCE, SOURCE_PREFIX + Attr.INTELLIGENCE)


static func _add(stats: StatComponent, stat: StatTypes.Stat, op: Modifier.ModOp,
		value: float, source: String) -> void:
	var m := Modifier.new()
	m.stat = stat
	m.op = op
	m.value = value
	m.source_id = source
	stats.add_modifier(m)


## Re-applies the effects when the attributes change. apply() itself changes stats (and so
## fires stats_changed again), but never the attributes, so this stops after one pass.
class _Watcher extends RefCounted:
	var stats: StatComponent
	var last := Vector3.ZERO
	var _busy := false

	func on_stats_changed() -> void:
		if _busy or not is_instance_valid(stats):
			return
		var now := AttributeEffects.attributes_of(stats)
		if now == last:
			return
		_busy = true
		last = now
		AttributeEffects.apply(stats)
		_busy = false
