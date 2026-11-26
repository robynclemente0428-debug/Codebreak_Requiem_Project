class_name ScriptRegisters
extends RefCounted

const WRITE_OPS := ["add", "remove", "sort"]
const MEMBER_WRITES := 2
const SORT_KEYS := ["age", "hp", "max_hp", "distance"]
const POSITIONS := ["[0]", "[1]", "[2]", "[-1]", "[:2]", "[:3]"]
const READ_KEYS := ["target", "size"]
const MEMBER_OPS := ["in", "not in"]
const OPS := ["<", ">", "<=", ">=", "==", "!="]
const MAX_VALUE := 99
const WRITE_KNOB := &"var"
const CLEAR_AFTER := 10.0
const RAMP_PER_STEP := 5
const RAMP_COST_SLOW := 0.3
const RAMP_COST_FAST := 0.6
const GROW_KNOBS: Array[StringName] = [&"radius", &"range_bonus", &"arc_angle", &"range", &"spread", &"speed", &"leech", &"barrier", &"guard"]

static var _knobs: Array[SkillKnob] = []


static func knobs() -> Array[SkillKnob]:
	if _knobs.is_empty():
		var k := SkillKnob.new()
		k.id = WRITE_KNOB
		k.display_name = "registry"
		k.kind = SkillKnob.Kind.VARIABLE
		k.step = 1.0
		k.min_steps = 0
		k.max_steps = 9999
		k.cost_per_step = 0.0
		k.unit = ""
		_knobs.append(k)
	return _knobs


static func is_write(knob_id: StringName) -> bool:
	return knob_id == WRITE_KNOB


static func is_sort(e: ProgramEffect) -> bool:
	return e != null and is_write(e.knob) and e.write_op() == "sort"


static func sort_text(sort_by: int) -> String:
	var n := SORT_KEYS.size() * 2
	var s := posmod(sort_by, n)
	return "key=%s%s" % [SORT_KEYS[s / 2], ", reverse=true" if s % 2 == 1 else ""]


const SORT_ENDS := {"age": ["oldest", "newest"], "hp": ["lowest-hp", "highest-hp"],
	"max_hp": ["frailest", "toughest"], "distance": ["nearest", "farthest"]}
const POSITION_WORDS := {"[0]": "first", "[1]": "2nd", "[2]": "3rd", "[-1]": "last",
	"[:2]": "first 2", "[:3]": "first 3"}


static func position_meaning(pos: int, sort_by: int) -> String:
	var s := posmod(sort_by, SORT_KEYS.size() * 2)
	var ends: Array = SORT_ENDS[SORT_KEYS[s / 2]]
	var front: String = ends[1 if s % 2 == 1 else 0]
	var back: String = ends[0 if s % 2 == 1 else 1]
	match POSITIONS[posmod(pos, POSITIONS.size())]:
		"[1]":
			return "the 2nd " + front
		"[2]":
			return "the 3rd " + front
		"[-1]":
			return "the " + back
		"[:2]":
			return "the 2 " + front
		"[:3]":
			return "the 3 " + front
	return "the " + front


static func sort_meaning(sort_by: int) -> String:
	var s := posmod(sort_by, SORT_KEYS.size() * 2)
	var rev := s % 2 == 1
	match SORT_KEYS[s / 2]:
		"hp":
			return "most life left first" if rev else "least life left first"
		"max_hp":
			return "toughest first (most maximum life)" if rev else "frailest first (least maximum life)"
		"distance":
			return "farthest from you first" if rev else "nearest to you first"
	return "newest first (the last one added)" if rev else "oldest first (the first one added)"


static func raises(e: ProgramEffect) -> bool:
	return is_write(e.knob) and e.write_op() == "add"


static func can_grow(knob: SkillKnob) -> bool:
	return knob != null and not knob.always_only \
			and (knob.kind == SkillKnob.Kind.DAMAGE or GROW_KNOBS.has(knob.id))


static func ramp_steps(count: int, value: int, room: int) -> float:
	return clampf(float(count) * value / RAMP_PER_STEP, 0.0, float(maxi(room, 0)))


static func ramp_reach(value: int, room: int) -> int:
	return ceili(float(room) * RAMP_PER_STEP / maxi(value, 1))


static func ramp_cost_share(value: int, room: int) -> float:
	if room <= 1:
		return RAMP_COST_FAST
	return lerpf(RAMP_COST_SLOW, RAMP_COST_FAST, clampf(float(value - 1) / (room - 1), 0.0, 1.0))


static func compare(value: int, op: String, n: int) -> bool:
	match op:
		"<": return value < n
		">": return value > n
		"<=": return value <= n
		">=": return value >= n
		"==": return value == n
		"!=": return value != n
	return false


static func entry_key(target: Node) -> Variant:
	if target == null or not is_instance_valid(target) or target.is_in_group(&"breakables"):
		return null
	return target.get_instance_id()


static func has(store: Dictionary, target: Node) -> bool:
	var at: Variant = entry_key(target)
	return at != null and store.has(at)


static func write(store: Dictionary, e: ProgramEffect, target: Node) -> bool:
	var at: Variant = entry_key(target)
	if at == null or e.write_op() == "sort":
		return false
	if e.write_op() == "add":
		if store.has(at) or SkillBehavior.is_dead(target):
			return false
		store[at] = true
		return true
	return store.erase(at)


static func size_of(store: Dictionary) -> int:
	prune(store)
	return store.size()


static func ordered(store: Dictionary, sort_by: int, from: Node3D) -> Array:
	prune(store)
	var ids: Array = store.keys()
	var s := posmod(sort_by, SORT_KEYS.size() * 2)
	var key: String = SORT_KEYS[s / 2]
	var rev := s % 2 == 1
	if key == "age":
		if rev:
			ids.reverse()
		return ids
	var value := {}
	for i in ids.size():
		value[ids[i]] = [_sort_value(instance_from_id(ids[i]) as Node, key, from), i]
	ids.sort_custom(func(a, b) -> bool:
		var va: Array = value[a]
		var vb: Array = value[b]
		if not is_equal_approx(float(va[0]), float(vb[0])):
			return (float(va[0]) > float(vb[0])) if rev else (float(va[0]) < float(vb[0]))
		return int(va[1]) < int(vb[1]))
	return ids


static func _sort_value(node: Node, key: String, from: Node3D) -> float:
	if node == null:
		return 0.0
	match key:
		"hp", "max_hp":
			var h := node.get("health") as HealthComponent
			if h == null:
				return 0.0
			if key == "hp":
				return h.current_health
			return h.stats.get_stat(StatTypes.Stat.MAX_HEALTH) if h.stats != null else h.current_health
		"distance":
			var n3 := node as Node3D
			return n3.global_position.distance_to(from.global_position) if n3 != null and is_instance_valid(from) else 0.0
	return 0.0


static func at_position(index: int, count: int, pos: int) -> bool:
	if index < 0 or count <= 0:
		return false
	match POSITIONS[posmod(pos, POSITIONS.size())]:
		"[0]": return index == 0
		"[1]": return index == 1
		"[2]": return index == 2
		"[-1]": return index == count - 1
		"[:2]": return index < 2
		"[:3]": return index < 3
	return false


static func is_slice(pos: int) -> bool:
	return POSITIONS[posmod(pos, POSITIONS.size())].begins_with("[:")


static func prune(store: Dictionary) -> void:
	for k in store.keys():
		var node := instance_from_id(k) as Node if k is int else null
		if node == null or not node.is_inside_tree() or SkillBehavior.is_dead(node):
			store.erase(k)
