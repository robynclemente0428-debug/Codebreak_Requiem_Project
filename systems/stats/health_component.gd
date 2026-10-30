class_name HealthComponent
extends Node

@export var stats: StatComponent
@export var regen_interval: float = 0.25

## The most damage armour can ever remove, as a fraction. 0.9 = 90%.
@export var max_damage_reduction: float = 0.9
## Tuning: how much damage a point of armour is worth against. Higher = armour is weaker against big hits.
const ARMOUR_CONSTANT := 10.0

var current_health: float = 0.0
var _initialized: bool = false
var _regen_timer: float = 0.0
var _last_max: float = 0.0

signal health_changed(current: float, max: float)
signal damage_taken(amount: float)
signal died

func initialize() -> void:
	current_health = stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	_initialized = true
	_emit_changed()

func _process(delta: float) -> void:
	if not _initialized or current_health <= 0.0:
		return
	_regen_timer += delta
	if _regen_timer < regen_interval:
		return
	var elapsed := _regen_timer
	_regen_timer = 0.0
	var regen := stats.get_stat(StatTypes.Stat.REGENERATION)
	if regen <= 0.0 or current_health >= stats.get_stat(StatTypes.Stat.MAX_HEALTH):
		return
	heal(regen * elapsed)

## Returns the damage actually dealt after armour (0 if the hit was ignored).
func take_damage(amount: float) -> float:
	if not _initialized:
		push_warning("take_damage called before HealthComponent.initialize()")
		return 0.0
	if current_health <= 0.0:
		return 0.0
	var armour: float = stats.get_stat(StatTypes.Stat.ARMOUR)
	var mitigated := mitigate(amount, armour)
	current_health -= mitigated
	damage_taken.emit(mitigated)
	_emit_changed()
	if current_health <= 0.0:
		died.emit()
	return mitigated

func mitigate(amount: float, armour: float) -> float:
	var reduction := armour / (armour + ARMOUR_CONSTANT * amount)   # 0 to 1, never reaches 1
	reduction = minf(reduction, max_damage_reduction)
	return maxf(amount * (1.0 - reduction), 1.0)    

func heal(amount: float) -> void:
	if not _initialized or current_health <= 0.0:
		return                      # the dead stay dead
	var max_hp := stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	current_health = min(current_health + amount, max_hp)
	_emit_changed()

func _on_stats_changed() -> void:
	if not _initialized:
		return
	var new_max := stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	var clamped := minf(current_health, new_max)
	if is_equal_approx(clamped, current_health) and is_equal_approx(new_max, _last_max):
		return                      # nothing relevant changed
	current_health = clamped
	_emit_changed()

func revive(fraction: float = 1.0) -> void:
	current_health = stats.get_stat(StatTypes.Stat.MAX_HEALTH) * fraction
	_regen_timer = 0.0
	_emit_changed()

func _emit_changed() -> void:
	_last_max = stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	health_changed.emit(current_health, _last_max)
