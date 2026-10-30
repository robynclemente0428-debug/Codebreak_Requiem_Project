class_name ManaComponent
extends Node
## Mana pool for one character. Works like HealthComponent: maximum mana comes from the
## StatComponent (StatTypes.Stat.MANA), so gear and attributes that add Mana raise it.
##
## Spending:   if mana.spend(20.0): cast_the_skill()
## Checking:   if mana.has_enough(20.0): ...

@export var stats: StatComponent
## How often regeneration is applied, in seconds.
@export var regen_interval: float = 0.25
## Mana regained per second before any stat bonus. Set 0 to rely on stats only.
@export var base_regen_per_second: float = 2.0
## Seconds after spending before regeneration starts again. 0 = no delay.
@export var regen_delay: float = 0.0
## Start full when initialize() runs.
@export var start_full: bool = true

var current_mana: float = 0.0
var _initialized: bool = false
var _regen_timer: float = 0.0
var _delay_left: float = 0.0
var _last_max: float = 0.0

signal mana_changed(current: float, max: float)
## Emitted when spend() is refused because there isn't enough mana (for a "no mana" cue).
signal spend_failed(needed: float, current: float)


func initialize() -> void:
	var m := get_max_mana()
	current_mana = m if start_full else 0.0
	_initialized = true
	_emit_changed()


func get_max_mana() -> float:
	if stats == null:
		return 0.0
	return maxf(stats.get_stat(StatTypes.Stat.MANA), 0.0)

func get_regen() -> float:
	var r := base_regen_per_second
	if stats:
		r += stats.get_stat(StatTypes.Stat.MANA_REGEN)
	return maxf(r, 0.0)


func has_enough(amount: float) -> bool:
	return _initialized and current_mana >= amount


## Takes mana if there is enough. Returns false (and takes nothing) otherwise.
func spend(amount: float) -> bool:
	if not _initialized or amount <= 0.0:
		return _initialized
	if current_mana < amount:
		spend_failed.emit(amount, current_mana)
		return false
	current_mana -= amount
	_delay_left = regen_delay
	_emit_changed()
	return true


func restore(amount: float) -> void:
	if not _initialized:
		return
	current_mana = minf(current_mana + amount, get_max_mana())
	_emit_changed()


## Fills the pool (respawn, potion).
func restore_full() -> void:
	if _initialized:
		current_mana = get_max_mana()
		_emit_changed()


func _process(delta: float) -> void:
	if not _initialized:
		return
	if _delay_left > 0.0:
		_delay_left -= delta
		return
	_regen_timer += delta
	if _regen_timer < regen_interval:
		return
	var elapsed := _regen_timer
	_regen_timer = 0.0
	var regen := get_regen()
	if regen <= 0.0 or current_mana >= get_max_mana():
		return
	restore(regen * elapsed)


## Connect to StatComponent.stats_changed. Keeps current mana under a lowered maximum.
func _on_stats_changed() -> void:
	if not _initialized:
		return
	var new_max := get_max_mana()
	var clamped := minf(current_mana, new_max)
	if is_equal_approx(clamped, current_mana) and is_equal_approx(new_max, _last_max):
		return
	current_mana = clamped
	_emit_changed()


func _emit_changed() -> void:
	_last_max = get_max_mana()
	mana_changed.emit(current_mana, _last_max)

# mana_component.gd
## Call once for every hit the owner lands, with the final MANA_ON_HIT value
## (use the skill's effective stats so gem/support modifiers count).
func gain_on_hit(amount: float) -> void:
	if amount > 0.0:
		restore(amount)
