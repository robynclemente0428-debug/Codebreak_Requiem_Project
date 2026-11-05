class_name PortLock
extends EnemyTrait
## Base of the boss locks (a puzzle a boss fight is built round). While the port is closed,
## every hit on the boss is absorbed: it counts as landed (loops and on-hit supports see it) but
## deals nothing. Solving the lock opens the port for `open_time` seconds: hits land normally and
## the boss glows cyan (its own EnemySilhouette overlay). Then it closes and the lock starts over.
##   ChecksumLock   bursts of exactly N hits                     (Loop Hound Alpha)
##   HandshakeLock  take its slam with a scripted shield up      (Corrupted Gate Guard)
##   BroodLock      clear the brood it summons                   (Glitchling Queen)
## A subclass decides when to call open_port(), and says why a try failed with say().
## Give a boss one through EnemyDefinition.innate_traits.

const COL_OPEN := Color(0.3, 0.95, 1.0)          # cyan: stands out against an orange boss
const COL_SHORT := Color(1.0, 0.75, 0.3)
const COL_REJECT := Color(1.0, 0.3, 0.3)
const SOUND_OPEN := "res://assets/sound/Start_Button_Click.wav"
const SOUND_FAIL := "res://assets/sound/Exit_Button_Click.mp3"

## Seconds the port stays open once the lock is solved.
@export var open_time := 4.0

var _open_left := 0.0
var _opened_for := 4.0
var _overlay: ShaderMaterial


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	var model := enemy.get("model") as Node
	if model != null:
		_overlay = EnemySilhouette.cover_own(model)     # its own copy, so only this boss glows


func is_open() -> bool:
	return _open_left > 0.0


## How much of the open window is left (1 = just opened, 0 = closed). LockBanner's bar.
func open_fraction() -> float:
	return clampf(_open_left / maxf(_opened_for, 0.01), 0.0, 1.0) if is_open() else 0.0


## Closed port: absorb the hit. Subclasses that override this call super() first.
func modify_incoming(info: HitInfo) -> void:
	if not is_open():
		info.absorbed = true


## Opens the port: `text` pops over the boss, and `damage` (held hits) lands at once.
## `seconds` < 0 = open_time.
func open_port(text: String, damage := 0.0, seconds := -1.0) -> void:
	_open_left = open_time if seconds < 0.0 else seconds
	_opened_for = _open_left
	say(text, COL_OPEN, 1.25)
	SoundManager.play_ui(SOUND_OPEN, -2.0)
	var hp := enemy.get("health") as HealthComponent
	if hp != null and damage > 0.0:
		hp.take_damage(damage)


## Shuts the port early (`text` "" = no pop).
func close_port(text := "PORT CLOSED") -> void:
	if not is_open():
		return
	_open_left = 0.0
	_set_glow(0.0)
	if text != "":
		say(text, Color(COL_OPEN, 0.7), 0.8)
	_on_closed()


## A failed try: the reason pops over the boss, with a dull click.
func fail(text: String, col := COL_REJECT) -> void:
	say(text, col, 1.0)
	SoundManager.play_ui(SOUND_FAIL, -8.0)


func _process(delta: float) -> void:
	if not is_instance_valid(enemy):
		return
	if _open_left > 0.0:
		_open_left -= delta
		_set_glow(_open_glow())
		if _open_left <= 0.0:
			_set_glow(0.0)
			say("PORT CLOSED", Color(COL_OPEN, 0.7), 0.8)
			_on_closed()
	else:
		_closed_process(delta)


## Every frame while the port is closed.
func _closed_process(_delta: float) -> void:
	pass


## The port just closed.
func _on_closed() -> void:
	pass


## Brightest when the port opens, pulsing faster in its last second as a warning.
func _open_glow() -> float:
	if _open_left < 1.0:
		return 0.45 + 0.45 * absf(sin(_open_left * 18.0))
	return 1.0 - 0.25 * clampf((_opened_for - _open_left) / maxf(_opened_for, 0.01), 0.0, 1.0)


func _set_glow(v: float) -> void:
	if _overlay != null:
		_overlay.set_shader_parameter("open_amount", v)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
