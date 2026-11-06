class_name DiffLock
extends EnemyTrait
## DIFF (The Mimic at Mirror Dock, and the Mirror Husks of the Dangling Quarter): it copies what
## hits it and compares each cast with the last one it copied. A cast where the same WHEN rule
## fired is an empty diff, and does nothing. A cast where a different rule fired lands, and is
## copied in turn. A cast where no rule fired has nothing to compare. Swapping skills or script
## sets doesn't help, since it copies the swap: only a script that branches inside itself gets
## through, with one skill and two WHEN rules on different conditions.
##     "DIFF: ENEMIES NEARBY"     a new rule fired: this whole cast lands
##     "NO DIFF"                  the same rule as last time, or none
##     "LOADOUT COPIED"           the skill or script set changed, and it doesn't care

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "DIFF"
const HINT := "Swapping won't fool it. Give one skill two WHEN rules so each cast fires a different one."

const COL_DIFF := Color(0.3, 0.95, 1.0)
const COL_SAME := Color(1.0, 0.3, 0.3)
const COL_COPY := Color(1.0, 0.75, 0.3)
const NO_DIFF_GAP := 1.2
const COPY_GAP := 2.5
const LAST_WORDS := "WHATEVER'S OUT THERE, WE MEET IT MOVING."

var _copied := ""                                # the rules of the last cast it copied
var _landing: Object = null                      # the cast landing now: all its hits count
var _loadout := ""
var _copy_at := -10.0


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	var hp := enemy.get("health") as HealthComponent
	if hp != null:
		hp.died.connect(_on_died)


## What it last copied ("" = nothing yet), for tests and a HUD readout.
func copied() -> String:
	return _copied


func modify_incoming(info: HitInfo) -> void:
	if info.cast == null or not info.cast.is_valid():
		return
	_note_loadout(info)
	var root := _root_of(info.cast)
	if root == _landing:
		return
	var key := rules_of(info.cast)
	if key == "" or key == _copied:
		info.absorbed = true
		pop("NO DIFF", COL_SAME, NO_DIFF_GAP)
		return
	_copied = key
	_landing = root
	say("DIFF: %s" % key.replace("_", " ").replace(",", " + ").to_upper(), COL_DIFF, 0.95)


## The WHEN rules that fired for this cast, as text that's the same for the same rules.
static func rules_of(cast: SkillCast) -> String:
	var fired: Array = ProgramSupport.fired_conditions(cast)
	fired.sort()
	return ",".join(PackedStringArray(fired))


## A loop's repeats, and a cast's follow-ups, count as the cast that started them.
func _root_of(cast: SkillCast) -> Object:
	var runner := cast.extra.get(ProgramSupport.LOOP_KEY) as ProgramLoopRunner
	return runner.root if runner != null and runner.root != null else cast


## It copies whatever hits it: its next attack is that skill. A swap only earns a taunt.
func _note_loadout(info: HitInfo) -> void:
	if info.cast.skill == null or info.cast.skill.gem == null:
		return
	var gem: SkillGemDefinition = info.cast.skill.gem
	var skills := info.cast.caster.get("skills") as SkillComponent
	var now_loadout := "%s|%d" % [gem.id, skills.script_set if skills != null else 0]
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
