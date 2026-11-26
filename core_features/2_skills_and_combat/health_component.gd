class_name HealthComponent
extends Node

@export var stats: StatComponent
@export var regen_interval: float = 0.25

@export var max_damage_reduction: float = 0.9
const ARMOUR_CONSTANT := 10.0

var current_health: float = 0.0
var barrier: float = 0.0
var guard: float = 0.0
var _barrier_until := 0
var _barrier_seconds := 0.0
var _guard_until := 0
var last_damaged_msec := -1000000
var _initialized: bool = false
var _regen_timer: float = 0.0
var _last_max: float = 0.0

signal health_changed(current: float, max: float)
signal damage_taken(amount: float)
signal died
signal barrier_changed(amount: float)

var remote_damage := Callable()
var remote_shielded := false
var untouchable := false


signal damage_shown(amount: float)


func apply_remote(value: float, show_hit := true) -> void:
	var was_alive := current_health > 0.0
	if show_hit and was_alive and value < current_health:
		damage_shown.emit(current_health - maxf(value, 0.0))
	current_health = value
	_emit_changed()
	if was_alive and value <= 0.0:
		died.emit()

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

func take_damage(amount: float, ignore_armour := false) -> float:
	if not _initialized:
		push_warning("take_damage called before HealthComponent.initialize()")
		return 0.0
	if current_health <= 0.0:
		return 0.0
	if remote_damage.is_valid():
		remote_damage.call(amount, ignore_armour)
		return amount if ignore_armour else mitigate(amount, stats.get_stat(StatTypes.Stat.ARMOUR))
	if untouchable:
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
			return 0.0
	var armour: float = stats.get_stat(StatTypes.Stat.ARMOUR)
	var mitigated := amount if ignore_armour else mitigate(amount, armour)
	last_damaged_msec = now
	current_health -= mitigated
	damage_taken.emit(mitigated)
	_emit_changed()
	if current_health <= 0.0:
		died.emit()
	return mitigated

func add_barrier(amount: float, seconds: float) -> void:
	if amount <= 0.0 or current_health <= 0.0:
		return
	barrier = maxf(barrier if Time.get_ticks_msec() < _barrier_until else 0.0, amount)
	_barrier_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	_barrier_seconds = seconds
	barrier_changed.emit(barrier)


func barrier_time_left() -> float:
	if barrier <= 0.0 or _barrier_seconds <= 0.0:
		return 0.0
	return clampf((_barrier_until - Time.get_ticks_msec()) / (_barrier_seconds * 1000.0), 0.0, 1.0)


func add_guard(fraction: float, seconds: float) -> void:
	if fraction <= 0.0:
		return
	var now := Time.get_ticks_msec()
	guard = maxf(guard if now < _guard_until else 0.0, clampf(fraction, 0.0, 0.9))
	_guard_until = maxi(_guard_until, now + int(seconds * 1000.0))


func mitigate(amount: float, armour: float) -> float:
	var reduction := armour / (armour + ARMOUR_CONSTANT * amount)
	reduction = minf(reduction, max_damage_reduction)
	return maxf(amount * (1.0 - reduction), 1.0)    

func heal(amount: float) -> void:
	if not _initialized or current_health <= 0.0:
		return
	var max_hp := stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	current_health = min(current_health + amount, max_hp)
	_emit_changed()

func _on_stats_changed() -> void:
	if not _initialized:
		return
	var new_max := stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	var clamped := minf(current_health, new_max)
	if is_equal_approx(clamped, current_health) and is_equal_approx(new_max, _last_max):
		return
	current_health = clamped
	_emit_changed()

func revive(fraction: float = 1.0) -> void:
	current_health = stats.get_stat(StatTypes.Stat.MAX_HEALTH) * fraction
	_regen_timer = 0.0
	_emit_changed()

func _emit_changed() -> void:
	_last_max = stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	health_changed.emit(current_health, _last_max)

func is_shielded() -> bool:
	if remote_damage.is_valid():
		return remote_shielded
	var now := Time.get_ticks_msec()
	return (barrier > 0.0 and now < _barrier_until) or (guard > 0.0 and now < _guard_until)
