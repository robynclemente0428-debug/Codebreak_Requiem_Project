class_name ChallengeLock
extends PortLock
## CHALLENGE (the Perimeter Warden at Checkpoint's gate, THE LAST MILE): challenge-response.
## Checkpoint keeps asking who you are, and you answer in code. Once a player comes close, the
## Warden pauses the fight and opens a coding challenge in the PATCH panel (PatchPanel's CHALLENGE
## mode, one of PatchPanel.WARDEN_PUZZLES, never the same one twice in a row):
##   solved                the port opens for `open_time` seconds: "RESPONSE ACCEPTED // PORT OPEN"
##   a wrong RUN TESTS     punished: the player takes `wrong_damage` of their life, and can try again
##   walked away / timed   punished the same, and a new challenge comes after `retry_delay`
## Once the port closes, the next challenge comes after `next_delay`. While it's shut, every hit is
## absorbed ("LOCKED // ANSWER THE CHALLENGE"). The challenges are built on what Acts I and II taught:
## a crowd condition, a loop count, a life check, steps in order, and the IFF's two records.

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "CHALLENGE"
const HINT := "It asks in code. Solve its challenge to open the port; a wrong answer hurts."

const PatchPanelScript := preload("res://scenes/map/town/convoy/patch_panel.gd")
const COL_CHALLENGE := Color(1.0, 0.82, 0.3)
const LOCKED_GAP := 1.5

## Metres: it starts challenging once a player is this close.
@export var notice_range := 5.0
## Seconds the player has to answer each challenge.
@export var answer_time := 40.0
## Share of the player's life a wrong answer costs (through armour; a barrier still soaks it).
@export var wrong_damage := 0.15
## Seconds before the next challenge: after the port closes, and after walking away.
@export var next_delay := 2.5
@export var retry_delay := 4.0

var challenge := ""                              # the puzzle id it's asking now ("" = none open)
var _last := ""
var _wait := 1.0
var _dead := false
var solved_count := 0                            # for the test, and a HUD readout


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	open_time = 6.0
	var hp := enemy.get("health") as HealthComponent
	if hp != null:
		hp.died.connect(func() -> void: _dead = true)


func modify_incoming(info: HitInfo) -> void:
	super(info)
	if info.absorbed:
		pop("LOCKED // ANSWER THE CHALLENGE", Color(COL_REJECT, 0.85), LOCKED_GAP)


func _closed_process(delta: float) -> void:
	if _dead or challenge != "":
		return
	_wait -= delta
	if _wait > 0.0:
		return
	var p := _player()
	if p == null or p.global_position.distance_to(enemy.global_position) > notice_range:
		return
	var hp := p.get("health") as HealthComponent
	if hp != null and hp.current_health <= 0.0:
		return
	var dialogue := get_tree().get_first_node_in_group("dialogue_panel")
	if dialogue != null and dialogue.has_method("is_open") and dialogue.is_open():
		return
	_ask(p)


## Opens a challenge (a different one from the last).
func _ask(p: Node3D) -> void:
	var pool: Array = PatchPanelScript.WARDEN_PUZZLES.filter(func(id: String) -> bool: return id != _last)
	var id: String = pool[randi() % pool.size()]
	var puzzle = PatchPanelScript.warden_puzzle(id)
	if not PatchPanelScript.open_challenge(get_tree(), puzzle, p, "Perimeter Warden", self, answer_time):
		_wait = 0.5                                  # another panel is up: ask in a moment
		return
	challenge = id
	_last = id
	say("CHALLENGE: " + str(puzzle.file).to_upper(), COL_CHALLENGE, 1.1)


# ---------- THE PANEL'S ANSWERS (PatchPanel CHALLENGE mode) ----------
func challenge_solved() -> void:
	challenge = ""
	solved_count += 1
	if not _dead:
		open_port("RESPONSE ACCEPTED // PORT OPEN")


## A wrong RUN: it hurts. Returns true when that killed the player (the panel closes).
func challenge_failed() -> bool:
	say("WRONG RESPONSE", COL_REJECT, 1.0)
	SoundManager.play_ui(SOUND_FAIL, -8.0)
	var killed := _punish()
	if killed:
		challenge = ""                               # the panel closes; ask again after they're back
		_wait = retry_delay
	return killed


func challenge_abandoned() -> void:
	challenge = ""
	_wait = retry_delay
	fail("NO RESPONSE // PUNISHED")
	_punish()


## The port closed: the next challenge soon.
func _on_closed() -> void:
	_wait = next_delay


func _punish() -> bool:
	var p := _player()
	var hp := p.get("health") as HealthComponent if p != null else null
	var stats := p.get("stats") as StatComponent if p != null else null
	if hp == null or stats == null or hp.current_health <= 0.0:
		return true
	hp.take_damage(stats.get_stat(StatTypes.Stat.MAX_HEALTH) * wrong_damage, true)
	return hp.current_health <= 0.0


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D
