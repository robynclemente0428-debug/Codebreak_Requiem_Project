class_name FragmentLock
extends EnemyTrait
## FRAGMENTED: Act V's memory comes back in pieces, and pieces only fit back in order. Fragments
## near each other (PACK_RADIUS) are one pack, ordered by the life they have left, least first.
## Only the first in that order takes full damage; every other one takes OUT_OF_ORDER of a hit.
## Kill one out of order and the pack REFRAGMENTS: the rest heal REFRAG_HEAL of their life.
## Fragments start at different integrity (START_MIN to full), so the order is there from the
## first hit, and its tag says each one's place: "[0] of 4" is the one to hit.
## The answer is the Defragmenter rank's sorting, which orders the same way:
##     always:                       registry.add(target)
##                                   registry.sort(key=hp)
##     when target is registry[0]:   damage += 60%
## Before that rank it is beaten by hand: follow the tags and hit [0].
## A dungeon threat ("fragmented", DungeonThreats: The Stack Trace, every enemy) and the Root
## Process's adds (RootPhases), and the Defragmenter exam's samples.

const COL := Color(1.0, 0.84, 0.42)          # the Architects' gold

## A lock (EnemyTrait): its tag, hover plate row and NEW LOCK card.
const LOCK_NAME := "FRAGMENTED"
const HINT := "Only the fragment with the least life left takes full damage. Hit them in order: [0] first. registry.sort(key=hp) with registry[0] does it for you."
const LOCK_COLOR := COL
const LOCK_SHAPE := "square"
const BANNER := false                        # it pops on hits: the tag is enough

const GROUP := &"fragment_locks"
## Fragments within this many metres of each other are one pack.
const PACK_RADIUS := 12.0
## Share of a hit an out-of-order fragment takes.
const OUT_OF_ORDER := 0.3
## A fragment killed out of order heals the rest of its pack this share of their maximum life.
const REFRAG_HEAL := 0.2
## Fragments start between this share of their life and full.
const START_MIN := 0.45

## Whether the last hit found this fragment out of order (its death then refragments the pack).
var _out_of_order := false

## Events for the Defragmenter exam (ExamChamber, ExamSpec.required_order), the player's hits only:
##   "fragment_hit"     "in_order" / "out_of_order"   every hit that landed
##   "fragment_killed"  "in_order" / "out_of_order"   a kill (out of order refragments the pack)
const HIT_EVENT := "fragment_hit"
const KILL_EVENT := "fragment_killed"


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	add_to_group(GROUP)
	_scatter.call_deferred()


## Starts at a random integrity, so the pack has an order before anyone hits it.
func _scatter() -> void:
	var h := _health_of(enemy)
	var top := max_health()
	if h == null or top <= 0.0:
		return
	h.current_health = top * randf_range(START_MIN, 1.0)
	h.health_changed.emit(h.current_health, top)


## The living fragments of this one's pack (itself included), least life first; ties by age.
func pack() -> Array:
	var out: Array = []
	if not is_instance_valid(enemy) or not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(GROUP):
		var f := n as FragmentLock
		if f == null or not is_instance_valid(f.enemy) or SkillBehavior.is_dead(f.enemy):
			continue
		if f.enemy.global_position.distance_to(enemy.global_position) <= PACK_RADIUS:
			out.append(f)
	out.sort_custom(func(a: FragmentLock, b: FragmentLock) -> bool:
		var ha := a.life()
		var hb := b.life()
		if not is_equal_approx(ha, hb):
			return ha < hb
		return a.enemy.get_instance_id() < b.enemy.get_instance_id())
	return out


func life() -> float:
	var h := _health_of(enemy)
	return h.current_health if h != null else 0.0


## [place in its pack's order, pack size]. A fragment alone is [0, 1].
func place() -> Vector2i:
	var p := pack()
	return Vector2i(maxi(p.find(self), 0), maxi(p.size(), 1))


func tag_state() -> String:
	var p := place()
	if p.y <= 1:
		return ""
	return "[%d] of %d" % [p.x, p.y]


func modify_incoming(info: HitInfo) -> void:
	var p := place()
	_out_of_order = p.x > 0
	if not _out_of_order:
		return
	info.damage *= OUT_OF_ORDER
	pop("OUT OF ORDER  [%d]" % p.x, Color(COL, 0.85), 1.0)


func after_hit(info: HitInfo) -> void:
	if info.absorbed:
		return
	var by_player := info.facts != null and info.facts.by_player   # not an enemy's own skill
	var how := "out_of_order" if _out_of_order else "in_order"
	if by_player:
		GameEvents.report(HIT_EVENT, how)
		if info.killed:
			GameEvents.report(KILL_EVENT, how)
	if info.killed and _out_of_order:
		_refragment()


## Killed out of order: the rest of the pack heals.
func _refragment() -> void:
	var healed := false
	for f in pack():
		if f == self:
			continue
		var h := _health_of(f.enemy)
		if h != null:
			h.heal(f.max_health() * REFRAG_HEAL)
			healed = true
	if healed:
		say("REFRAGMENTED", Color(1.0, 0.45, 0.35))


static func _health_of(node: Node) -> HealthComponent:
	return node.get("health") as HealthComponent if is_instance_valid(node) else null
