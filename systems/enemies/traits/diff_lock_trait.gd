class_name DiffLock
extends EnemyTrait
## DIFF (The Mimic at Mirror Dock, the Mirror Husks of the Dangling Quarter, and RECALL's last
## third): it copies what hits it and compares each cast with the last one it copied. A cast where
## the same WHEN rule fired is an empty diff, and does nothing. A cast where a different rule fired
## lands, and is copied in turn. A cast where no rule fired has nothing to compare. Swapping skills
## or script sets doesn't help, since it copies the swap: only a script that branches inside
## itself gets through, with one skill and two WHEN rules on different conditions.
##
## And it uses what it copied. Every `mirror_every` seconds it charges a MIRROR for `mirror_charge`
## seconds ("MIRRORING: ENEMIES NEARBY"), then throws it at where the player stands: a slow orb that
## takes `mirror_damage` of their maximum life where it lands (LockBlast.orb; armour, barrier and
## guard soak it). The orb carries the rule copied WHEN IT'S THROWN, and that rule's damage buff
## makes it hit harder: x(1 + a quarter of the buff), at most x2 (`mirror_cap` of life). So a
## +200% rule comes back at x1.5, and nothing comes back above a third of the player's life.
## That makes what it copies a choice: land a cast whose rule carries no damage (a bait rule, like
## a bare registry.add(target)) while it charges, and the mirror it throws is the plain one. Or
## just step off the spot. Only one mirror is in the air at a time, whoever threw it.
##     "DIFF: ENEMIES NEARBY"     a new rule fired: this whole cast lands
##     "NO DIFF"                  the same rule as last time, or none
##     "LOADOUT COPIED"           the skill or script set changed, and it doesn't care
##     "MIRRORING: ..."           charging a mirror of the rule it copied
##     "MIRROR x1.5"              thrown, with the copied rule's buff

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "DIFF"
const HINT := "Give one skill two WHEN rules so each cast fires a different one. It throws back the rule it copied last, buff and all: let it copy a rule with no damage while it charges, or dodge."
## Its tag and body (EnemyTrait): a split double image, magenta on one side and cyan on the other.
const LOCK_COLOR := Color(1.0, 0.45, 0.8)
const LOCK_SHAPE := "split"
const LOCK_AURA := 2                 # EnemySilhouette.AURA_DIFF
## Longest rule text on the tag; the hover plate shows it whole.
const TAG_MAX := 22

const COL_DIFF := Color(0.3, 0.95, 1.0)
const COL_SAME := Color(1.0, 0.3, 0.3)
const COL_COPY := Color(1.0, 0.75, 0.3)
const NO_DIFF_GAP := 1.2
const COPY_GAP := 2.5
const LAST_WORDS := "WHATEVER'S OUT THERE, WE MEET IT MOVING."
const COL_MIRROR := Color(1.0, 0.45, 0.8)
## How far the player can be for it to start a mirror (it doesn't throw at nobody).
const MIRROR_RANGE := 22.0
const MIRROR_SPEED := 9.0                        # m/s: slow enough to step out of its way
const MIRROR_RADIUS := 1.6                       # m around where it lands

## Seconds between mirrors (from one throw to the next charge).
@export var mirror_every := 5.0
## Seconds it charges first: the tell, and the time to feed it a bait rule.
@export var mirror_charge := 1.2
## Share of the player's maximum life a mirror of a rule with no damage buff takes...
@export_range(0.0, 0.5, 0.01) var mirror_damage := 0.15
## ...and the most any mirror takes, however big the copied buff (x2 at most).
@export_range(0.0, 0.8, 0.01) var mirror_cap := 0.30
## How much of the copied rule's damage buff the mirror carries (a quarter: +200% -> x1.5).
const BUFF_SHARE := 0.25

## When the mirror in the air now lands, for every DIFF lock: one at a time, whoever threw it.
static var _mirror_until := 0.0

var _copied := ""                                # the rules of the last cast it copied
var _copied_buff := 0.0                          # that cast's damage buff (+2.0 = +200%)
var _landing := ""                               # the cast landing now (HitFacts.root_id): all its hits count
var _loadout := ""
var _copy_at := -10.0
var _next_mirror := 0.0                          # when it may start charging again
var _charging: MeshInstance3D = null             # the orb on it while it charges
var _charge_end := 0.0


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	var hp := enemy.get("health") as HealthComponent
	if hp != null:
		hp.died.connect(_on_died)


## What it last copied ("" = nothing yet), for tests and a HUD readout.
func copied() -> String:
	return _copied


## On its tag: the rule it has copied, so the next cast must fire another ("NOT ENEMIES NEARBY").
func tag_state() -> String:
	if _copied == "":
		return ""
	var s := "NOT " + _copied.replace("_", " ").replace(",", " + ").to_upper()
	return s if s.length() <= TAG_MAX else s.left(TAG_MAX - 3) + "..."


func modify_incoming(info: HitInfo) -> void:
	var f := info.facts
	if f == null:
		return
	_note_loadout(f)
	if f.root_id == _landing:                     # a loop's repeats count as the cast that started them
		return
	var key := rules_of(f)
	if key == "" or key == _copied:
		info.absorbed = true
		pop("NO DIFF", COL_SAME, NO_DIFF_GAP)
		return
	_copied = key
	_copied_buff = maxf(f.root_damage_mult - 1.0, 0.0)
	_landing = f.root_id
	say("DIFF: %s" % key.replace("_", " ").replace(",", " + ").to_upper(), COL_DIFF, 0.95)


# ---------- THE MIRROR ----------
## How hard a mirror of a rule with damage buff `buff` hits, as a share of maximum life.
func mirror_share(buff: float) -> float:
	return minf(mirror_damage * minf(1.0 + maxf(buff, 0.0) * BUFF_SHARE, 2.0), mirror_cap)


func _process(_delta: float) -> void:
	if not is_instance_valid(enemy) or SkillBehavior.is_dead(enemy) or not enemy.is_inside_tree():
		_drop_charge()
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _charging != null:
		_charging.global_position = enemy.global_position + Vector3.UP * 2.0
		if now >= _charge_end:
			_throw()
		return
	if _copied == "" or now < _next_mirror or now < _mirror_until:
		return
	var target := _target()
	if target == null:
		return
	_charging = LockBlast.make_orb(COL_MIRROR, 0.3)
	enemy.get_parent().add_child(_charging)
	_charging.global_position = enemy.global_position + Vector3.UP * 2.0
	_charging.scale = Vector3.ONE * 0.3
	_charging.create_tween().tween_property(_charging, "scale", Vector3.ONE, mirror_charge)
	_charge_end = now + mirror_charge
	_mirror_until = now + mirror_charge + 3.0          # held while it charges; set exactly on the throw
	_tell_copies("diff_charge", [mirror_charge])     # co-op: the copies show the orb charging too
	say("MIRRORING: %s" % _copied.replace("_", " ").replace(",", " + ").to_upper(), COL_MIRROR, 0.95)


## Throws the charged orb at where the player stands now, carrying the rule copied now.
func _throw() -> void:
	_tell_copies("diff_drop", [])                    # co-op: theirs goes; the flight is drawn (LockBlast.orb)
	var orb := _charging
	_charging = null
	var now := Time.get_ticks_msec() / 1000.0
	_next_mirror = now + mirror_every
	var target := _target()
	if target == null or orb == null:
		_drop_orb(orb)
		_mirror_until = 0.0
		return
	var share := mirror_share(_copied_buff)
	var to := target.global_position + Vector3.UP * 0.6
	var flight := LockBlast.orb(enemy.get_parent(), orb, orb.global_position, to, MIRROR_SPEED, MIRROR_RADIUS,
		share, func() -> void: pop("MIRROR HIT", COL_MIRROR, 0.4))
	_mirror_until = now + flight + 0.2
	say("MIRROR x%.2f" % (share / mirror_damage) if mirror_damage > 0.0 else "MIRROR", COL_MIRROR, 1.0)


## The nearest living player in range, or null.
func _target() -> Node3D:
	var best: Node3D = null
	var best_d := MIRROR_RANGE
	for p in get_tree().get_nodes_in_group("players"):
		var body := p as Node3D
		var hp := p.get("health") as HealthComponent
		if body == null or hp == null or hp.current_health <= 0.0:
			continue
		var d := body.global_position.distance_to(enemy.global_position)
		if d <= best_d:
			best = body
			best_d = d
	return best


func _drop_charge() -> void:
	if _charging != null:
		_tell_copies("diff_drop", [])
		_drop_orb(_charging)
		_charging = null
		_mirror_until = 0.0


static func _drop_orb(orb: MeshInstance3D) -> void:
	if orb != null and is_instance_valid(orb):
		orb.queue_free()


## RECALL swaps this lock out mid-fight: an orb still charging goes with it.
func _exit_tree() -> void:
	_drop_charge()
	_drop_orb(_copy_orb)


# ---------- CO-OP: A GUEST'S COPY ----------
## The orb charging on the host's Diff, shown on the copy: on the enemy itself (nothing runs on a
## copy per frame, so it rides along as a child). The throw is drawn by Coop.show_orb.
var _copy_orb: MeshInstance3D


func _copy_message(what: String, args: Array) -> void:
	match what:
		"diff_charge":
			_drop_orb(_copy_orb)
			var seconds := clampf(float(args[0]) if not args.is_empty() else mirror_charge, 0.1, 10.0)
			_copy_orb = LockBlast.make_orb(COL_MIRROR, 0.3)
			_copy_orb.top_level = false
			enemy.add_child(_copy_orb)
			_copy_orb.position = Vector3.UP * 2.0
			_copy_orb.scale = Vector3.ONE * 0.3
			_copy_orb.create_tween().tween_property(_copy_orb, "scale", Vector3.ONE, seconds)
		"diff_drop":
			_drop_orb(_copy_orb)
			_copy_orb = null


## The WHEN rules that fired for this hit's cast, as text that's the same for the same rules.
static func rules_of(f: HitFacts) -> String:
	var fired: Array = f.fired.duplicate()
	fired.sort()
	return ",".join(PackedStringArray(fired))


## It copies whatever hits it: its next attack is that skill. A swap only earns a taunt.
func _note_loadout(f: HitFacts) -> void:
	if f.gem == null:
		return
	var gem: SkillGemDefinition = f.gem
	var now_loadout := "%s|%d" % [gem.id, maxi(f.script_set, 0)]   # a hologram (-1) counts as set 0
	if now_loadout == _loadout:
		return
	if _loadout != "":
		var now := Time.get_ticks_msec() / 1000.0
		if now - _copy_at >= COPY_GAP:
			_copy_at = now
			say("LOADOUT COPIED", COL_COPY, 0.95)
	_loadout = now_loadout
	var caster := _enemy_skills()
	if caster != null:
		caster.copy_skill(gem)


## The Mimic goes out in Brack's voice. A husk just stops.
func _on_died() -> void:
	if str(enemy.get_meta(&"enemy_id", "")) != "the_mimic":
		return
	say(LAST_WORDS, COL_DIFF, 1.1)
	QuestItems.toast(get_tree(), "IN BRACK'S VOICE:\n\"Whatever's out there, we meet it moving.\"", COL_DIFF)


## EnemySpawner adds this after the traits, so it's looked up when needed.
func _enemy_skills() -> EnemySkills:
	for c in enemy.get_children():
		if c is EnemySkills:
			return c
	return null
