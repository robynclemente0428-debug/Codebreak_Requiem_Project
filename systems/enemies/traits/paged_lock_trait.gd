class_name PagedLock
extends EnemyTrait
## PAGED (The Page File, Act V: every enemy, DungeonThreats "paged"). Where the Core sends what it
## can't hold. A page stays in memory only while something REFERENCES it: an enemy that isn't in
## any of your skills' registries pages out for OUT_SECONDS of every RESIDENT + OUT_SECONDS (each
## on its own clock), and while it's out, it isn't there: your hits pass through it, and it stands
## still. One that's in a registry stays resident.
## So the answer is the registry: a  registry.add(target)  line that runs as you open on a pack,
## or kernel.gd's  when enemy_spotted: registry.add(target), which references everything you meet.
## The registry forgets after a while out of combat (ScriptRegisters.CLEAR_AFTER), like always.
##     "PAGED OUT"      it's out of memory: the hit passed through
##     tag: REFERENCED / PAGED OUT

const LOCK_NAME := "PAGED"
const HINT := "A page stays in memory only while something references it. Put it in your registry (registry.add(target), or kernel.gd's when enemy_spotted line) and it can't page out."
const LOCK_COLOR := Color(0.55, 0.9, 1.0)
const LOCK_SHAPE := "hex"
const BANNER := false

const RESIDENT := 4.0
const OUT_SECONDS := 2.0
const CHECK_EVERY := 0.2
const FADE := 0.75                   # how see-through a paged-out enemy is
const COL_OUT := Color(0.55, 0.9, 1.0)

var _t := 0.0
var _out := false
var _referenced := false
var _check := 0.0
var _meshes: Array = []


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	_t = randf() * (RESIDENT + OUT_SECONDS)          # every page on its own clock
	_collect_meshes.call_deferred()


func _collect_meshes() -> void:
	if not is_instance_valid(enemy):
		return
	var model := enemy.get("model") as Node
	_meshes = (model if model != null else enemy).find_children("*", "GeometryInstance3D", true, false)


func tag_state() -> String:
	if _referenced:
		return "REFERENCED"
	return "PAGED OUT" if _out else ""


func _process(delta: float) -> void:
	if not is_instance_valid(enemy) or SkillBehavior.is_dead(enemy):
		if _out:
			_page(false)
		return
	_check -= delta
	if _check <= 0.0:
		_check = CHECK_EVERY
		_referenced = _is_referenced()
	if _referenced:
		if _out:
			_page(false)
		_t = 0.0
		return
	_t += delta
	if not _out and _t >= RESIDENT:
		_page(true)
	elif _out and _t >= OUT_SECONDS:
		_page(false)


func _page(out: bool) -> void:
	_out = out
	_t = 0.0
	for m in _meshes:
		if is_instance_valid(m):
			(m as GeometryInstance3D).transparency = FADE if out else 0.0
	if out:
		var ai = enemy.get("ai")
		if ai != null and "busy_time" in ai:
			ai.busy_time = OUT_SECONDS                # out of memory: it isn't doing anything
		for c in enemy.get_children():
			if c is EnemySkills:
				(c as EnemySkills).stun(OUT_SECONDS)


func modify_incoming(info: HitInfo) -> void:
	if _out:
		info.absorbed = true
		pop("PAGED OUT", COL_OUT, 0.8)


## True when any of the player's skills has this enemy in its registry.
func _is_referenced() -> bool:
	var player := get_tree().get_first_node_in_group("players")
	var sk := player.get("skills") as SkillComponent if player != null else null
	if sk == null:
		return false
	for s in sk.sockets:
		if s.program != null and ScriptRegisters.has(s.program.state().registers, enemy):
			return true
	return false
