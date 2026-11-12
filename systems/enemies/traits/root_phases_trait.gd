class_name RootPhases
extends EnemyTrait
## THE ROOT PROCESS: no lock ("it cannot be reasoned with"), but three phases, one per third of
## its life, each with a different pattern from an earlier boss. Its model holds a Summoner and
## a LoopCharger; this switches them on and off.
##   1  SPAWN   its Summoner calls in adds (the Queen's pattern), Fragmented (FragmentLock): they
##              only take full damage in order, which the Defragmenter exam taught
##   2  LOOP    the adds stop; its LoopCharger charges a loop marked in red (Loop Hound Alpha's)
##   3  FORK    the charges stop (after the one running); it swaps forms on a short timer
##              (FormShift, the Gatekeeper's pattern, twice as fast)

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "THREE PHASES"
const HINT := "No lock, three patterns. First it calls adds, then it charges a loop marked in red, then it swaps forms fast: strike while FAST, back off while HEAVY."

const NAMES := ["PHASE 1 // SPAWN", "PHASE 2 // LOOP", "PHASE 3 // FORK"]
const COL_PHASE := Color(1.0, 0.35, 0.55)
## FormShift's seconds in each form during the last phase.
const FORK_FORM_TIME := 3.5

var phase := 0
var _summoner: Summoner
var _charger: LoopCharger
var _charger_stopped := false


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	for n in enemy.find_children("*", "", true, false):
		if n is Summoner:
			_summoner = n
			var frag := load("res://data/enemy_traits/fragmented.tres") as EnemyModifierDefinition
			if frag != null and not frag in _summoner.summon_mods:
				_summoner.summon_mods.append(frag)
		elif n is LoopCharger:
			_charger = n


func _process(_delta: float) -> void:
	if not is_instance_valid(enemy) or SkillBehavior.is_dead(enemy):
		set_process(false)
		return
	# Nodes turn their own processing on when they become ready, so this holds them each frame.
	if _summoner != null:
		_summoner.set_process(phase == 0)
	if _charger != null and not _charger_stopped:
		if phase == 0:
			_charger.set_physics_process(false)
		elif phase == 1:
			_charger.set_physics_process(true)
		elif _charger._phase == LoopCharger.Phase.WAIT:   # never cut a charge off half-way
			_charger._on_died()                          # stops it and clears its marks
			_charger_stopped = true
	var hp := enemy.get("health") as HealthComponent
	var top := max_health()
	if hp == null or top <= 0.0 or phase >= 2:
		return
	var due := clampi(int((1.0 - hp.current_health / top) * 3.0), 0, 2)
	if due > phase:
		_enter(phase + 1)


func _enter(i: int) -> void:
	phase = i
	say(NAMES[i], COL_PHASE, 1.3)
	if i == 2:
		var t := Node.new()
		t.set_script(FormShift)
		t.name = "Fork"
		(t as FormShift).form_time = FORK_FORM_TIME
		enemy.add_child(t)
		(t as FormShift).setup(enemy)
		enemy.traits.append(t)
