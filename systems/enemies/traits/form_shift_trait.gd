class_name FormShift
extends EnemyTrait
## The Null Gatekeeper: swaps between two forms on a timer, and says so over its head.
##   FAST   moves and attacks quickly, but its armour is halved: the time to hurt it
##   HEAVY  slow and larger, three times the armour, and its hits land harder: the time to back off

const SOURCE := "form_shift"
## Named like a lock (LockBanner.lock_info): the quest tracker shows HINT under "Defeat ...",
## and the lock banner shows each form change.
const LOCK_NAME := "FORM SHIFT"
const HINT := "It changes form every few seconds. Hit hard while it is FAST; back off while it is HEAVY."
const COL_FAST := Color(0.3, 0.9, 1.0)
const COL_HEAVY := Color(1.0, 0.45, 0.2)
const HEAVY_SCALE := 1.25

## Seconds in each form.
@export var form_time := 7.0
## Its hits in the heavy form are multiplied by this.
@export var heavy_damage := 1.5
## Metres: it starts shifting once a player is this close.
@export var notice_range := 18.0

var heavy := false
var _left := 0.0
var _noticed := false                            # the fight has started: a player came close


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	_shift(false)


func _process(delta: float) -> void:
	if not is_instance_valid(enemy) or SkillBehavior.is_dead(enemy):
		set_process(false)
		return
	if not _noticed:
		var player := get_tree().get_first_node_in_group("players") as Node3D
		if player != null and player.global_position.distance_to(enemy.global_position) <= notice_range:
			_noticed = true
			_shift(false)
		return
	_left -= delta
	if _left <= 0.0:
		_shift(not heavy)


func on_outgoing(info: HitInfo) -> void:
	if heavy:
		info.damage *= heavy_damage


func _shift(to_heavy: bool) -> void:
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
