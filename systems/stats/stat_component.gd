
class_name StatComponent
extends Node

@export var base_stats: Dictionary = {}: # StatType.Stat - should be float
	set(value):
		base_stats = value
		_mark_dirty()

var _modifiers: Array[Modifier] = []
var _cache: Dictionary = {}
var _dirty: bool = true

signal stats_changed

func add_modifier(mod: Modifier) -> void:
	_modifiers.append(mod)
	_mark_dirty()

func remove_by_source(source_id: String) -> void:
	_modifiers = _modifiers.filter(func(m): return m.source_id != source_id)
	_mark_dirty()

func clear_modifiers() -> void:
	_modifiers.clear()
	_mark_dirty()

func remove_by_source_prefix(prefix: String) -> void:
	_modifiers = _modifiers.filter(func(m): return not m.source_id.begins_with(prefix))
	_mark_dirty()

func get_stat(stat: StatTypes.Stat) -> float:
	if _dirty:
		_recompute()
	return _cache.get(stat, 0.0)

func _mark_dirty() -> void:
	_dirty = true
	stats_changed.emit()

func _recompute() -> void:
	_cache.clear()
	var touched: Dictionary = {}

	for stat in base_stats.keys():
		touched[stat] = true

	for m in _modifiers:
		touched[m.stat] = true

	for stat in touched.keys():
		var base: float = base_stats.get(stat, 0.0)
		var flat := 0.0
		var percent_add := 0.0
		var percent_mult := 1.0
		var override_val = null
		for m in _modifiers:
			if m.stat != stat:
				continue
			match m.op:
				Modifier.ModOp.FLAT_ADD:
					flat += m.value
				Modifier.ModOp.PERCENT_ADD:
					percent_add += m.value
				Modifier.ModOp.PERCENT_MULT:
					percent_mult *= (1.0 + m.value)
				Modifier.ModOp.OVERRIDE:
					override_val = m.value
		var result: float = override_val if override_val != null \
		else (base + flat) * (1.0 + percent_add) * percent_mult
		if stat == StatTypes.Stat.MAX_HEALTH and override_val == null:
			# Stacked "-x% health" modifiers can sum past -100%. Below 1 the owner would spawn
			# dead: unhittable, never attacking, but still chasing (seen on swarm champions).
			result = maxf(result, 1.0)
		_cache[stat] = result
	_dirty = false
