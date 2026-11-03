class_name HealthComponent
extends Node

@export var stats: StatComponent
@export var regen_interval: float = 0.25

## The most damage armour can ever remove, as a fraction. 0.9 = 90%.
@export var max_damage_reduction: float = 0.9
## Tuning: how much damage a point of armour is worth against. Higher = armour is weaker against big hits.
const ARMOUR_CONSTANT := 10.0

var current_health: float = 0.0
## Defence from skill scripts (see SkillBehavior._apply_defense):
##   barrier  absorbs damage before health, until it runs out or `_barrier_until` passes
##   guard    share of every hit removed while `_guard_until` hasn't passed (0.2 = 20% less)
var barrier: float = 0.0
var guard: float = 0.0
var _barrier_until := 0
var _barrier_seconds := 0.0      # how long the current barrier was given for
var _guard_until := 0
## When damage last got through (ms), for the hit_recently() script condition.
var last_damaged_msec := -1000000
var _initialized: bool = false
var _regen_timer: float = 0.0
var _last_max: float = 0.0

signal health_changed(current: float, max: float)
signal damage_taken(amount: float)
signal died
signal barrier_changed(amount: float)

func initialize() -> void:
	current_health = stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	_initialized = true
	_emit_changed()

func _process(delta: float) -> void:
	if barrier > 0.0 and Time.get_ticks_msec() >= _barrier_until:
		barrier = 0.0
		barrier_changed.emit(0.0)
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
## ignore_armour: the full amount lands (a Reflector's zap).
func take_damage(amount: float, ignore_armour := false) -> float:
	if not _initialized:
		push_warning("take_damage called before HealthComponent.initialize()")
		return 0.0
	if current_health <= 0.0:
		return 0.0
	var now := Time.get_ticks_msec()
	if guard > 0.0 and now < _guard_until:
		amount *= 1.0 - guard
	if barrier > 0.0 and now < _barrier_until:
		var absorbed := minf(barrier, amount)
		barrier -= absorbed
		amount -= absorbed
		barrier_changed.emit(barrier)
		if amount <= 0.0:
			return 0.0                  # all of it hit the barrier
	var armour: float = stats.get_stat(StatTypes.Stat.ARMOUR)
	var mitigated := amount if ignore_armour else mitigate(amount, armour)
	last_damaged_msec = now
	current_health -= mitigated
	damage_taken.emit(mitigated)
	_emit_changed()
	if current_health <= 0.0:
		died.emit()
	return mitigated

## A barrier of `amount` for `seconds`. Doesn't stack: a bigger one replaces a smaller one,
## and every new one restarts the timer.
func add_barrier(amount: float, seconds: float) -> void:
	if amount <= 0.0 or current_health <= 0.0:
		return
	barrier = maxf(barrier if Time.get_ticks_msec() < _barrier_until else 0.0, amount)
	_barrier_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	_barrier_seconds = seconds
	barrier_changed.emit(barrier)


## How much of the current barrier's time is left, 1 = just given, 0 = gone.
func barrier_time_left() -> float:
	if barrier <= 0.0 or _barrier_seconds <= 0.0:
		return 0.0
	return clampf((_barrier_until - Time.get_ticks_msec()) / (_barrier_seconds * 1000.0), 0.0, 1.0)


## Takes `fraction` less damage for `seconds` (the stronger guard wins while both last).
func add_guard(fraction: float, seconds: float) -> void:
	if fraction <= 0.0:
		return
	var now := Time.get_ticks_msec()
	guard = maxf(guard if now < _guard_until else 0.0, clampf(fraction, 0.0, 0.9))
	_guard_until = maxi(_guard_until, now + int(seconds * 1000.0))


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
