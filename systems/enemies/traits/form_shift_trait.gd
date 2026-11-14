class_name FormShift
extends EnemyTrait
## The Null Gatekeeper: swaps between two forms on a timer, and says so over its head.
##   FAST   moves and attacks quickly, but its armour is halved: the time to hurt it
##   HEAVY  slow and larger, three times the armour, and its hits land harder: the time to back off
## The Null Gatekeeper also speaks (VOICE): once when the fight starts, at two thirds and one third
## of its life, and as it dies. It isn't guarding the Core from you; it's guarding the Null from
## what you'd do to it (Vesper says so at the Gate, and the Last Log answers it in the Core).
## The Root Process's last phase reuses FormShift, silently.

const SOURCE := "form_shift"
## Named like a lock (LockBanner.lock_info): the quest tracker shows HINT under "Defeat ...",
## and the lock banner shows each form change.
const LOCK_NAME := "FORM SHIFT"
const HINT := "It changes form every few seconds. Hit hard while it is FAST; back off while it is HEAVY."
const COL_FAST := Color(0.3, 0.9, 1.0)
const COL_HEAVY := Color(1.0, 0.45, 0.2)
const HEAVY_SCALE := 1.25
const COL_VOICE := Color(0.78, 0.5, 1.0)
const VOICE_ID := "null_gatekeeper"
const VOICE_START := "THE NULL IS NOT FINISHED. YOU MAY NOT EDIT IT."
## Said at two thirds and one third of its life.
const VOICE_HURT := ["EVERY PROCESS THAT REACHED THIS GATE CAME TO DELETE IT.",
		"IT IS LEARNING WHAT YOU ARE. LET IT FINISH THE SENTENCE."]
const VOICE_LAST := "THEN YOU DECIDE. NOTHING ELSE CAN."

## Seconds in each form.
@export var form_time := 7.0
## Its hits in the heavy form are multiplied by this.
@export var heavy_damage := 1.5
## Metres: it starts shifting once a player is this close.
@export var notice_range := 18.0

var heavy := false
var _left := 0.0
var _noticed := false                            # the fight has started: a player came close
var _voice := false                              # this is the Gatekeeper: it speaks
var _said_hurt := 0


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	var hp := enemy.get("health") as HealthComponent
	if hp != null:
		hp.died.connect(_on_died)
	_shift(false)


func _process(delta: float) -> void:
	if not is_instance_valid(enemy) or SkillBehavior.is_dead(enemy):
		set_process(false)
		return
	if not _noticed:
		if player_within(notice_range) != null:      # any player in range (co-op: a guest's too)
			_noticed = true
			_voice = str(enemy.get_meta(&"enemy_id", "")) == VOICE_ID
			_shift(false)
			if _voice:
				say(VOICE_START, COL_VOICE, 1.05)
		return
	if _voice and _said_hurt < VOICE_HURT.size():
		var hp := enemy.get("health") as HealthComponent
		var top := max_health()
		if hp != null and top > 0.0 and hp.current_health / top <= (2.0 - _said_hurt) / 3.0:
			say(VOICE_HURT[_said_hurt], COL_VOICE, 1.05)
			_said_hurt += 1
	_left -= delta
	if _left <= 0.0:
		_shift(not heavy)


func _on_died() -> void:
	if str(enemy.get_meta(&"enemy_id", "")) != VOICE_ID:
		return
	say(VOICE_LAST, COL_VOICE, 1.1)
	QuestItems.toast(get_tree(), "THE GATEKEEPER:\n\"Then you decide. Nothing else can.\"", COL_VOICE)


func on_outgoing(info: HitInfo) -> void:
	if heavy:
		info.damage *= heavy_damage


func _shift(to_heavy: bool) -> void:
	_tell_copies("trait_form", [to_heavy])       # co-op: the copies change size too
	heavy = to_heavy
	_left = form_time
	var stats := enemy.get("stats") as StatComponent
	if stats != null:
		stats.remove_by_source(SOURCE)
		if heavy:
			_mod(stats, StatTypes.Stat.MOVE_SPEED, -0.55)
			_mod(stats, StatTypes.Stat.ARMOUR, 2.0)
		else:
			_mod(stats, StatTypes.Stat.MOVE_SPEED, 0.8)
			_mod(stats, StatTypes.Stat.ATTACK_SPEED, 0.6)
			_mod(stats, StatTypes.Stat.ARMOUR, -0.5)
	var mount := enemy.get("model_mount") as Node3D
	if mount != null:
		mount.scale = Vector3.ONE * (HEAVY_SCALE if heavy else 1.0)
	if _noticed:
		pop("HEAVY FORM: BACK OFF" if heavy else "FAST FORM: STRIKE NOW", COL_HEAVY if heavy else COL_FAST, 0.0)


func _mod(stats: StatComponent, stat: StatTypes.Stat, value: float) -> void:
	var m := Modifier.new()
	m.stat = stat
	m.op = Modifier.ModOp.PERCENT_MULT
	m.value = value
	m.source_id = SOURCE
	stats.add_modifier(m)


## On a guest's copy: the host's changed form. Only the look (its size) and `heavy`, for the tag.
func _copy_message(what: String, args: Array) -> void:
	if what != "trait_form" or args.is_empty():
		return
	heavy = bool(args[0])
	var mount := enemy.get("model_mount") as Node3D
	if mount != null:
		mount.scale = Vector3.ONE * (HEAVY_SCALE if heavy else 1.0)
