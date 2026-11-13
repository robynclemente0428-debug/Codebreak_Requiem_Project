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

## ---- CO-OP (Coop.in_game) ----
## One challenge for the whole party, and the fight does NOT pause. The host's Warden owns the
## lock: it picks ONE player in range (the next one round the party each time, so everyone
## answers), and only that player gets the panel. The others see who is answering and keep the
## Warden busy. Messages go through Coop.lock_send / coop_message:
##   host -> the solver   "ask"   [puzzle id, seconds]     open the panel
##   host -> everyone     "say"   [text, colour]           the same pop over the Warden
##   host -> everyone     "port"  [seconds]                the port is open: hits land
##   solver -> host       "solved" / "failed" / "abandoned" / "dead" / "busy"
## The solver's machine runs the tests and takes the punishment for a wrong answer; while the
## panel is up their character stands still and takes SOLVER_GUARD less damage. A solve opens the
## port for everyone. A guest's copy never asks on its own, and its port only follows the host's.
const COOP_ANSWER_MULT := 1.5                    # longer to answer: the fight is still going on
const COOP_OPEN_BONUS := 2.0                     # seconds more of open port: the others must react
const SOLVER_GUARD := 0.5                        # share of damage the answering player doesn't take
var _asked_peer := 0                             # host: who is answering now
var _last_peer := 0                              # host: who answered last (the next one is someone else)
var _answer_left := 0.0                          # host: seconds until an answer that never came is given up on
var _answering := false                          # this machine's player has the panel
var _guard_tick := 0.0


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
	if Coop.in_game:
		_coop_closed_process(delta)
		return
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


# ---------- CO-OP: ONE CHALLENGE FOR THE PARTY ----------
func _coop_closed_process(delta: float) -> void:
	if _answering:                               # our player has the panel: keep them guarded
		_guard_tick -= delta
		if _guard_tick <= 0.0:
			_guard_tick = 1.0
			var mine := _player()
			var hp := mine.get("health") as HealthComponent if mine != null else null
			if hp != null:
				hp.add_guard(SOLVER_GUARD, 1.5)      # renewed every second, gone soon after the panel closes
	if not Coop.is_host() or _dead:
		return
	if challenge != "":
		_answer_left -= delta
		if _answer_left <= 0.0:                  # the solver left the game, or never answered
			challenge = ""
			_wait = retry_delay
			_tell("NO RESPONSE", COL_REJECT)
		return
	_wait -= delta
	if _wait > 0.0:
		return
	var target := _next_solver()
	if target == null:
		return
	var pool: Array = PatchPanelScript.WARDEN_PUZZLES.filter(func(id: String) -> bool: return id != _last)
	var id: String = pool[randi() % pool.size()]
	var peer := Coop.player_peer(target)
	var seconds := answer_time * COOP_ANSWER_MULT
	if peer == Coop.my_id():
		if not _open_panel(id, target, seconds):
			_wait = 0.5                              # another panel is up: ask in a moment
			return
	else:
		Coop.lock_send(enemy, "ask", [id, seconds], peer)
	challenge = id
	_last = id
	_asked_peer = peer
	_last_peer = peer
	_answer_left = seconds + 6.0
	_tell("CHALLENGE FOR %s // DEFEND THEM" % Coop.peer_name(peer).to_upper(), COL_CHALLENGE)


## The player who answers next: someone alive and close, going round the party in turn.
func _next_solver() -> Node3D:
	var near: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		var body := p as Node3D
		var hp := p.get("health") as HealthComponent
		if body == null or hp == null or hp.current_health <= 0.0:
			continue
		if body.global_position.distance_to(enemy.global_position) > notice_range:
			continue
		if Coop.player_peer(body) == Coop.my_id():
			var dialogue := get_tree().get_first_node_in_group("dialogue_panel")
			if dialogue != null and dialogue.has_method("is_open") and dialogue.is_open():
				continue
		near.append(body)
	if near.is_empty():
		return null
	near.sort_custom(func(a: Node3D, b: Node3D) -> bool: return Coop.player_peer(a) < Coop.player_peer(b))
	for p: Node3D in near:
		if Coop.player_peer(p) > _last_peer:
			return p
	return near[0]


func _open_panel(id: String, player: Node, seconds: float) -> bool:
	var puzzle = PatchPanelScript.warden_puzzle(id)
	if not PatchPanelScript.open_challenge(get_tree(), puzzle, player, "Perimeter Warden", self, seconds):
		return false
	_answering = true
	_guard_tick = 0.0
	return true


## The same pop over the Warden on every machine.
func _tell(text: String, col: Color) -> void:
	say(text, col, 1.1)
	Coop.lock_send(enemy, "say", [text, col])


## What our panel said, to the host's lock (which may be this one).
func _report(what: String) -> void:
	if Coop.is_host():
		_coop_result(Coop.my_id(), what)
	else:
		Coop.lock_send(enemy, what, [])


## Host: the solver's answer.
func _coop_result(peer: int, what: String) -> void:
	if challenge == "" or peer != _asked_peer:
		return                                   # not the one we asked, or too late
	match what:
		"solved":
			challenge = ""
			solved_count += 1
			if not _dead:
				var seconds := open_time + COOP_OPEN_BONUS
				open_port("RESPONSE ACCEPTED // PORT OPEN", 0.0, seconds)
				Coop.lock_send(enemy, "port", [seconds])
		"failed":
			_tell("WRONG RESPONSE", COL_REJECT)  # they can try again: the panel is still up
		"abandoned":
			challenge = ""
			_wait = retry_delay
			_tell("NO RESPONSE // PUNISHED", COL_REJECT)
		"dead":
			challenge = ""
			_wait = retry_delay
		"busy":
			challenge = ""
			_wait = 0.5


## Coop: a message from the other side's copy of this lock (see the CO-OP notes at the top).
func coop_message(what: String, args: Array, from: int) -> void:
	if Coop.is_host():
		_coop_result(from, what)
		return
	if from != 1:
		return                                   # only the host's lock tells a copy what to do
	match what:
		"ask":
			var id := str(args[0]) if args.size() > 0 else ""
			var seconds := clampf(float(args[1]) if args.size() > 1 else answer_time, 5.0, 300.0)
			if not id in PatchPanelScript.WARDEN_PUZZLES or _player() == null \
					or not _open_panel(id, _player(), seconds):
				Coop.lock_send(enemy, "busy", [])
				return
			challenge = id
		"say":
			if args.size() >= 2 and args[1] is Color:
				say(str(args[0]).left(80), args[1], 1.1)
		"port":
			var seconds := clampf(float(args[0]) if args.size() > 0 else open_time, 0.5, 30.0)
			challenge = ""
			open_port("RESPONSE ACCEPTED // PORT OPEN", 0.0, seconds)


# ---------- THE PANEL'S ANSWERS (PatchPanel CHALLENGE mode) ----------
func challenge_solved() -> void:
	if Coop.in_game:
		_answering = false
		challenge = "" if not Coop.is_host() else challenge
		_report("solved")
		return
	challenge = ""
	solved_count += 1
	if not _dead:
		open_port("RESPONSE ACCEPTED // PORT OPEN")


## A wrong RUN: it hurts. Returns true when that killed the player (the panel closes).
func challenge_failed() -> bool:
	if Coop.in_game:                             # the host's lock says it to everyone
		SoundManager.play_ui(SOUND_FAIL, -8.0)
		var died := _punish()
		if died:
			_answering = false
			if not Coop.is_host():
				challenge = ""
		_report("dead" if died else "failed")
		return died
	say("WRONG RESPONSE", COL_REJECT, 1.0)
	SoundManager.play_ui(SOUND_FAIL, -8.0)
	var killed := _punish()
	if killed:
		challenge = ""                               # the panel closes; ask again after they're back
		_wait = retry_delay
	return killed


func challenge_abandoned() -> void:
	if Coop.in_game:
		_answering = false
		if not Coop.is_host():
			challenge = ""
		SoundManager.play_ui(SOUND_FAIL, -8.0)
		_punish()
		_report("abandoned")
		return
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
