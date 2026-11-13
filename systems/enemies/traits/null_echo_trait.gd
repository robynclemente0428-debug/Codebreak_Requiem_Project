class_name NullEcho
extends EnemyTrait
## NULL ECHO (Act IV, every zone: NullEchoDirector places them). The Null copies the player.
## An Echo copies the first skill it SEES the player cast (within SEE_RANGE): the gem, its
## supports and that skill's running script, and from then on fights with it (EnemySkills).
## The Weaver's Loom's Echoes copy the first two skills they see.
##
## A copy, and a reference. The script's own lines are a COPY, frozen as they were: change your
## script and the Echo's doesn't. But a  call name()  line is copied as the call, not the
## routine's lines, so an Echo calls YOUR routines.gd (SkillComponent.routines, the same list).
## Edit a routine and every Echo calling it changes at once, mid-fight:
##   buff a routine          you and every Echo calling it get it (theirs at a quarter: below)
##   gut it                  hollow for both, unless you no longer call it yourself
##   empty a routine an Echo still calls (or break it)
##                           NULL REFERENCE: its call points at nothing. It crashes: no casting
##                           for CRASH_SECONDS and CRASH_DAMAGE of its life, then it fights on
##                           with the bare skill until the routine is whole again.
## So the deep play is a decoy: a skill whose script calls a routine you don't need, cast first so
## the Echoes copy it, then empty that routine.
##
## Conditions run in the Echo's own context: for it, "enemies" are players (enemies_nearby(3)
## rarely fires), my_life_below reads its life, its registry is its own.
## Fair damage: an Echo hits with its own level's stats, never your weapon. Its script's damage
## buffs come along at a quarter (x2 at most), and no hit takes more than HIT_CAP of the target's
## life, so a huge build can't come back as a one-shot.
##     "COPIED: STRIKE"                 it saw a cast and took it
##     "NULL REFERENCE: cash_in()"      a routine it calls is empty or broken: it crashes

const LOCK_NAME := "NULL ECHO"
const HINT := "It copies the first skill it sees you cast, script and all. Lead with a feint. Its calls point at YOUR routines.gd: empty a routine it calls and it crashes."
const LOCK_COLOR := Color(0.78, 0.5, 1.0)
const LOCK_SHAPE := "diamond"
const LOCK_AURA := 2                 # EnemySilhouette.AURA_DIFF: a split double image
const BANNER := false
const TAG_MAX := 26

const SEE_RANGE := 16.0
const CRASH_SECONDS := 4.0
const CRASH_DAMAGE := 0.25
const BUFF_SHARE := 0.25
const BUFF_MAX := 2.0
const HIT_CAP := 0.15
const CAST_EVERY := 2.5              # seconds between its own casts once it has copied
const COL_COPY := Color(0.78, 0.5, 1.0)
const COL_CRASH := Color(1.0, 0.35, 0.35)
const COPIED_EVENT := "echo_copied"
const CRASH_EVENT := "echo_crashed"

## How many different skills it copies (the Loom's Echoes: 2).
var copies := 1
## The Mirror Forge's champion: its copy also calls all of your routines, every cast.
var calls_all := false

var _copied: Array = []              # [{"gem": id, "skill": SkillInstance, "broken": bool}]
var _version := -1                   # the player's SkillComponent.routines_version last built against
var _skills_node: EnemySkills


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	GameEvents.happened.connect(_on_event)


func _exit_tree() -> void:
	if GameEvents.happened.is_connected(_on_event):
		GameEvents.happened.disconnect(_on_event)


## On its tag: what it copied, and the routines it calls ("STRIKE + cash_in()").
func tag_state() -> String:
	if _copied.is_empty():
		return "WATCHING"
	var bits: Array = []
	for c in _copied:
		bits.append(str(c["gem"]).replace("_", " ").to_upper())
	var calls := called_routines()
	var s := " / ".join(PackedStringArray(bits))
	var names: Array = []
	var routines := _routines()
	for i in calls:
		names.append((routines[i] as ProgramRoutine).routine_name + "()" if i < routines.size() else "?()")
	if not names.is_empty():
		s += " + " + ", ".join(PackedStringArray(names))
	return s if s.length() <= TAG_MAX else s.left(TAG_MAX - 3) + "..."


## The routine indices its copied scripts call (for the routine editor's CALLED BY line).
func called_routines() -> Array:
	var out: Array = []
	for c in _copied:
		var p: SkillProgram = (c["skill"] as SkillInstance).program
		if p == null:
			continue
		for i in p.called_routines():
			if not i in out:
				out.append(i)
	return out


## Living Echoes in the tree that call routine `index`.
static func callers_of(tree: SceneTree, index: int) -> int:
	var n := 0
	if tree == null:
		return 0
	for e in tree.get_nodes_in_group(&"enemies"):
		if not ("traits" in e) or SkillBehavior.is_dead(e):
			continue
		for t in e.traits:
			if t is NullEcho and index in (t as NullEcho).called_routines():
				n += 1
	return n


# ---------- COPYING ----------
func _on_event(kind: String, target: String, _amount: int) -> void:
	if kind != "cast" or _copied.size() >= copies or not is_instance_valid(enemy) or SkillBehavior.is_dead(enemy):
		return
	var player := get_tree().get_first_node_in_group("players") as Node3D
	if player == null or player.global_position.distance_to(enemy.global_position) > SEE_RANGE:
		return
	var sk := player.get("skills") as SkillComponent
	if sk == null:
		return
	var index: int = sk.bindings.get(StringName(target), -1)
	if index < 0 or index >= sk.sockets.size() or sk.sockets[index].gem == null:
		return
	var sock: SkillComponent.Socket = sk.sockets[index]
	var gem: SkillGemDefinition = sock.gem.definition.skill_gem
	for c in _copied:
		if c["gem"] == gem.id:
			return                                   # it has this one: it waits for another
	var skill := SkillInstance.new()
	skill.gem = gem
	for item in sock.supports:
		if item.definition.support_gem != null:
			skill.supports.append(item.definition.support_gem)
	var running := sk.get_program(index)
	skill.program = running.duplicate_program() if running != null else null   # its own lines: a copy
	if calls_all:
		_call_everything(skill)
	skill.routines = sk.routines                     # its calls: a reference to yours
	skill.rank = Ranks.LADDER.size() - 1             # enemies have no rank or budget
	skill.bonus_points = 100.0
	skill.rebuild()
	var entry := {"gem": gem.id, "skill": skill, "broken": false}
	_copied.append(entry)
	_version = sk.routines_version
	_runner().add_copied(skill)
	say("COPIED: %s" % gem.id.replace("_", " ").to_upper(), COL_COPY, 1.0)
	GameEvents.report(COPIED_EVENT, gem.id)
	if _is_broken(entry):                            # it copied a call to a routine already empty
		entry["broken"] = true
		_crash(entry)


## The Mirror Forge's champion: an always rule that calls each of your routines.
func _call_everything(skill: SkillInstance) -> void:
	if skill.program == null:
		skill.program = SkillProgram.new()
	var rule := ProgramRule.new()
	for i in ProgramRoutine.MAX_ROUTINES:
		rule.effects.append(ProgramEffect.make_call(i))
	skill.program.rules.append(rule)


func _runner() -> EnemySkills:
	if is_instance_valid(_skills_node):
		return _skills_node
	for c in enemy.get_children():
		if c is EnemySkills:
			_skills_node = c
	if _skills_node == null:
		_skills_node = EnemySkills.new()
		_skills_node.name = "EnemySkills"
		enemy.add_child(_skills_node)
		_skills_node.setup(enemy, enemy.get("stats"), [])
	_skills_node.skill_cooldown = CAST_EVERY
	_skills_node.cooldown_jitter = 1.0
	return _skills_node


# ---------- THE REFERENCE ----------
## Your routines changed: every copied script that calls one is built again against them.
func _process(_delta: float) -> void:
	if _copied.is_empty() or not is_instance_valid(enemy) or SkillBehavior.is_dead(enemy):
		return
	var player := get_tree().get_first_node_in_group("players")
	var sk := player.get("skills") as SkillComponent if player != null else null
	if sk == null or sk.routines_version == _version:
		return
	_version = sk.routines_version
	for c in _copied:
		var skill: SkillInstance = c["skill"]
		if skill.program == null or not skill.program.has_calls():
			continue
		skill.routines = sk.routines
		skill.rebuild()
		var broken := _is_broken(c)
		if broken and not bool(c["broken"]):
			_crash(c)
		elif not broken and bool(c["broken"]):
			pop("REFERENCE RESTORED", COL_COPY, 0.5)
		c["broken"] = broken


## True when a routine this copy calls is empty or broken (its call points at nothing).
func _is_broken(c: Dictionary) -> bool:
	var skill: SkillInstance = c["skill"]
	if skill.program == null or not skill.program.has_calls():
		return false
	var routines := _routines()
	for i in skill.program.called_routines():
		if i >= routines.size() or not (routines[i] as ProgramRoutine).problem().is_empty():
			return true
	return false


func _crash(c: Dictionary) -> void:
	var routines := _routines()
	var called := "?"
	for i in (c["skill"] as SkillInstance).program.called_routines():
		if i >= routines.size() or not (routines[i] as ProgramRoutine).problem().is_empty():
			called = (routines[i] as ProgramRoutine).routine_name if i < routines.size() else "routine_%d" % (i + 1)
			break
	say("NULL REFERENCE: %s()" % called, COL_CRASH, 1.25)
	_runner().stun(CRASH_SECONDS)
	var ai = enemy.get("ai")
	if ai != null and "busy_time" in ai:
		ai.busy_time = CRASH_SECONDS
	var hp := enemy.get("health") as HealthComponent
	if hp != null:
		hp.take_damage(max_health() * CRASH_DAMAGE, true)
	GameEvents.report(CRASH_EVENT, called)


func _routines() -> Array:
	var player := get_tree().get_first_node_in_group("players") if is_inside_tree() else null
	var sk := player.get("skills") as SkillComponent if player != null else null
	return sk.routines if sk != null else []


# ---------- FAIR DAMAGE ----------
## Its script's damage buffs at a quarter (x2 at most), and never more than HIT_CAP of a life.
func on_outgoing(info: HitInfo) -> void:
	if info.cast != null:
		var mult := maxf(info.cast.damage_mult, 1.0)
		if mult > 1.0:
			info.damage *= minf(1.0 + (mult - 1.0) * BUFF_SHARE, BUFF_MAX) / mult
	var stats := info.target.get("stats") as StatComponent if info.target != null else null
	if stats != null:
		info.damage = minf(info.damage, stats.get_stat(StatTypes.Stat.MAX_HEALTH) * HIT_CAP)
