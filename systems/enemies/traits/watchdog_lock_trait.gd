class_name WatchdogLock
extends EnemyTrait
## HEARTBEAT (The Watchdog, boss of The Page File, Act V). A watchdog timer: something has to
## keep telling it the process is alive. Every hit that lands resets its timer to `timeout`
## seconds; let the timer run out and it decides the process hung, and RESETS: it restores
## `reset_heal` of its maximum life and REBOOTS, taking no damage for `reboot_seconds`.
## Below half life the timer tightens to `tight_timeout`.
## It's PAGED like everything in The Page File (PagedLock, an innate trait): while it's paged out
## your hits pass through it, and its timer keeps running. So it wants both halves of Act V:
## keep it referenced (a registry.add(target) line, or kernel.gd's when enemy_spotted line) so it
## can't page out, and a steady rhythm: a fast rule, a loop, a skill that hits every second or two.
## Big slow hits with gaps lose to it; so does losing the reference.
##     "BEAT"                     a hit landed: the timer is back to full (now and then)
##     "TIMEOUT // WATCHDOG RESET" no hit in time: it heals and reboots
##     "REBOOTING"                a hit during the reboot
##     "TIMER TIGHTENED"          below half life
## Its look (WatchdogLook) follows the timer: the overlay flashes on each beat and runs red as the
## timer runs out.

const LOCK_NAME := "HEARTBEAT"
const HINT := "A watchdog timer: land a hit at least every 3 seconds or it resets, healing and rebooting. It pages out like its zone: keep it in your registry so your hits keep landing."
const LOCK_COLOR := Color(0.45, 0.95, 1.0)
const LOCK_SHAPE := "ring"

const COL_BEAT := Color(0.45, 0.95, 1.0)
const COL_RESET := Color(1.0, 0.3, 0.25)
const ENGAGE_RANGE := 18.0
const BEAT_GAP := 1.2

@export var timeout := 3.0
@export var tight_timeout := 2.2
@export_range(0.0, 0.5, 0.01) var reset_heal := 0.12
@export var reboot_seconds := 2.0

var _left := 3.0
var _engaged := false
var _reboot_left := 0.0
var _tight := false
var _beat := 0.0
var _overlay: ShaderMaterial


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	_left = timeout
	_find_overlay.call_deferred()


func _find_overlay() -> void:
	var model := enemy.get("model") as Node if is_instance_valid(enemy) else null
	if model != null and model.has_meta(&"watchdog_overlay"):
		_overlay = model.get_meta(&"watchdog_overlay") as ShaderMaterial


func _limit() -> float:
	return tight_timeout if _tight else timeout


## On its tag: the time left on its timer, or REBOOT.
func tag_state() -> String:
	if _reboot_left > 0.0:
		return "REBOOT"
	return "%.1fs" % maxf(_left, 0.0) if _engaged else ""


func _process(delta: float) -> void:
	if not is_instance_valid(enemy) or SkillBehavior.is_dead(enemy):
		return
	_beat = maxf(_beat - delta * 3.0, 0.0)
	if not _engaged:
		_engaged = player_within(ENGAGE_RANGE) != null   # any player in range (co-op: a guest's too)
	if _reboot_left > 0.0:
		_reboot_left -= delta
		if _reboot_left <= 0.0:
			_left = _limit()
	elif _engaged:
		_left -= delta
		if _left <= 0.0:
			_reset()
	if not _tight and _life_share() < 0.5:
		_tight = true
		_left = minf(_left, tight_timeout)
		say("TIMER TIGHTENED // %.1fs" % tight_timeout, COL_RESET, 1.0)
	if _overlay != null:
		var alarm := 0.0
		if _engaged and _reboot_left <= 0.0:
			alarm = clampf(1.0 - _left / 1.2, 0.0, 1.0)       # the last 1.2 s run red
		elif _reboot_left > 0.0:
			alarm = 1.0
		_overlay.set_shader_parameter("alarm", alarm)
		_overlay.set_shader_parameter("beat", _beat)


func modify_incoming(info: HitInfo) -> void:
	if _reboot_left > 0.0:
		info.absorbed = true
		pop("REBOOTING", COL_RESET, 0.8)


func after_hit(info: HitInfo) -> void:
	if info.absorbed or not info.landed or _reboot_left > 0.0:
		return                                       # paged out, or rebooting: it never felt it
	_engaged = true
	_left = _limit()
	_beat = 1.0
	pop("BEAT", COL_BEAT, BEAT_GAP)


func _reset() -> void:
	var hp := enemy.get("health") as HealthComponent
	if hp != null:
		hp.heal(max_health() * reset_heal)
	_reboot_left = reboot_seconds
	say("TIMEOUT // WATCHDOG RESET", COL_RESET, 1.2)


func _life_share() -> float:
	var hp := enemy.get("health") as HealthComponent
	var top := max_health()
	return hp.current_health / top if hp != null and top > 0.0 else 1.0
