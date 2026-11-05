class_name EchoLock
extends EnemyTrait
## ECHO (the Hollow Choir, and the Echo Wisps of the Static Mire): it learns the pattern of the
## attack that gets through, the skill and the script set it was cast with, and then shrugs that
## pattern off. A new pattern lands for up to `learn_window` seconds (or until its burst ends),
## then it is cached in turn. No single attack works twice in a row: switch skills, or switch
## script sets (the script_set key) so the same skill runs a different program.
##     "PATTERN LEARNED: STRIKE / SET A"     the pattern that just hit it is cached
##     "PATTERN CACHED: STRIKE / SET A"      a hit with the cached pattern (absorbed, now and then)

const COL_LEARN := Color(1.0, 0.75, 0.3)
const COL_CACHED := Color(1.0, 0.3, 0.3)

## A pattern that gets through is cached this long after its first hit at the latest...
@export var learn_window := 1.4
## ...or as soon as it stops hitting for this long.
@export var learn_gap := 0.6

var _cached := ""
var _pending := ""
var _pending_since := 0.0
var _pending_last := 0.0


## The cached pattern ("" = none yet), for tests and a HUD readout.
func cached() -> String:
	return _cached


func modify_incoming(info: HitInfo) -> void:
	var p := pattern_of(info)
	if p == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if p == _cached:
		info.absorbed = true
		pop("PATTERN CACHED: %s" % _label(p), COL_CACHED, 1.2)
		return
	if p != _pending:
		if _pending != "":
			_learn()                                    # two new patterns at once: the older is cached
		_pending = p
		_pending_since = now
	_pending_last = now


func _process(_delta: float) -> void:
	if _pending == "" or not is_instance_valid(enemy):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _pending_since > learn_window or now - _pending_last > learn_gap:
		_learn()


func _learn() -> void:
	_cached = _pending
	_pending = ""
	say("PATTERN LEARNED: %s" % _label(_cached), COL_LEARN, 0.95)


## "strike|0": the skill gem and the script set (index) of the player who cast it.
## "" for hits that aren't from a player's skill.
func pattern_of(info: HitInfo) -> String:
	if info.cast == null or info.cast.skill == null or info.cast.skill.gem == null:
		return ""
	var sk := _skills_of(info.cast.caster if info.cast.is_valid() else null)
	return "%s|%d" % [info.cast.skill.gem.id, sk.script_set if sk != null else 0]


func _skills_of(caster: Node) -> SkillComponent:
	if caster != null and caster.get("skills") is SkillComponent:
		return caster.get("skills")
	var p := get_tree().get_first_node_in_group("players")      # a hologram: its owner's sets
	return p.get("skills") as SkillComponent if p != null else null


## "STRIKE / SET A"
func _label(p: String) -> String:
	var bits := p.split("|")
	var set_i := int(bits[1]) if bits.size() > 1 else 0
	var sk := _skills_of(null)
	var set_name: String = sk.set_names[set_i] if sk != null and set_i < sk.set_names.size() else str(set_i)
	return "%s / SET %s" % [bits[0].to_upper(), set_name.to_upper()]
