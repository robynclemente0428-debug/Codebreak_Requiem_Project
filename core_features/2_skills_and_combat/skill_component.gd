class_name SkillComponent
extends Node

const ACTIONS: Array[StringName] = [&"attack", &"attack_2", &"skill_1", &"skill_2", &"skill_3", &"skill_4"]

@export var socket_count: int = 6

class Socket extends RefCounted:
	var gem: ItemInstance
	var supports: Array[ItemInstance] = []
	var skill: SkillInstance
	var program: SkillProgram
	var sets: Array = []

	func _init() -> void:
		sets.resize(SkillComponent.SCRIPT_SETS)

var sockets: Array[Socket] = []
var bindings: Dictionary = {}

const SCRIPT_SETS := 3
const SET_NAMES := ["A", "B", "C"]
const SET_NAME_MAX := 10
var script_set := 0
var set_names := PackedStringArray(SET_NAMES)

const LIBRARY_SIZE := 12
const LIBRARY_NAME_MAX := 14
var library: Array = []

var routines: Array[ProgramRoutine] = []
var _held_routines: Array = []
var routines_version := 0

var kernel: Array[String] = []

var sandbox_locked := false

signal changed
signal script_set_changed(index: int)


func _ready() -> void:
	for i in socket_count:
		sockets.append(Socket.new())
	_watch_rank.call_deferred()


func _watch_rank() -> void:
	var qm := get_parent().get("quests") as QuestManager
	if qm != null and not qm.quest_completed.is_connected(_on_quest_completed):
		qm.quest_completed.connect(_on_quest_completed)
		qm.budget_changed.connect(refresh_rank)


func _on_quest_completed(_state: QuestState) -> void:
	refresh_rank()


var remote_limits: Dictionary = {}


func rank() -> int:
	if not remote_limits.is_empty():
		return int(remote_limits.get("rank", 0))
	return Ranks.of(get_parent())


func bonus_points() -> float:
	if not remote_limits.is_empty():
		return float(remote_limits.get("points", 0.0))
	if sandbox_locked:
		return 0.0
	return ScriptBudget.points(get_parent().get("quests") as QuestManager)


func bonus_steps() -> int:
	if not remote_limits.is_empty():
		return int(remote_limits.get("steps", 0))
	if sandbox_locked:
		return 0
	return ScriptBudget.steps(get_parent().get("quests") as QuestManager)


func refresh_rank() -> void:
	var r := rank()
	var bonus := bonus_points()
	var steps := bonus_steps()
	for s in sockets:
		if s.skill != null:
			s.skill.rank = r
			s.skill.bonus_points = bonus
			s.skill.bonus_steps = steps
	_apply_set()
	changed.emit()


func get_skill(action: StringName) -> SkillInstance:
	var index: int = bindings.get(action, -1)
	if index < 0 or index >= sockets.size():
		return null
	return sockets[index].skill


func action_of(index: int) -> StringName:
	for action in bindings:
		if bindings[action] == index:
			return action
	return &""


func bind_action(action: StringName, index: int) -> void:
	if index < 0 or index >= sockets.size() or sockets[index].gem == null:
		return
	for a in bindings.keys():
		if bindings[a] == index:
			bindings.erase(a)
	bindings[action] = index
	GameEvents.report("bind_skill", String(action))
	changed.emit()


func clear_action(action: StringName) -> void:
	if bindings.erase(action):
		changed.emit()


func socket_skill(index: int, item: ItemInstance, inventory: InventoryComponent = null) -> bool:
	if index < 0 or index >= sockets.size():
		return false
	var s := sockets[index]
	if s.gem != null or item == null or item.definition == null or item.definition.skill_gem == null \
			or sandbox_locked:
		return false
	if inventory != null and not inventory.remove_item(item):
		return false
	s.gem = item
	s.supports.clear()
	s.program = null
	s.sets.fill(null)
	_rebuild(s)
	GameEvents.report("socket_skill", item.definition.id)
	changed.emit()
	return true

func unsocket_skill(index: int, inventory: InventoryComponent) -> bool:
	if index < 0 or index >= sockets.size() or sandbox_locked:
		return false
	var s := sockets[index]
	if s.gem == null:
		return false
	var returning: Array[ItemInstance] = [s.gem]
	returning.append_array(s.supports)
	if inventory.capacity - inventory.items.size() < returning.size():
		return false
	s.gem = null
	s.supports.clear()
	s.skill = null
	s.program = null
	s.sets.fill(null)
	for a in bindings.keys():
		if bindings[a] == index:
			bindings.erase(a)
	for item in returning:
		inventory.add_item(item)
	RollbackWatch.sync(self)
	changed.emit()
	return true


func can_socket_support(index: int, item: ItemInstance) -> bool:
	if index < 0 or index >= sockets.size() or sandbox_locked:
		return false
	var s := sockets[index]
	if s.gem == null or item == null or item.definition.support_gem == null:
		return false
	var gem := s.gem.definition.skill_gem
	if s.supports.size() >= gem.max_support_slots:
		return false
	var support := item.definition.support_gem
	for other in s.supports:
		if other.definition.support_gem.id == support.id:
			return false
	for t in support.allowed_tags:
		if t in gem.tags:
			return true
	return false


func socket_support(index: int, item: ItemInstance, inventory: InventoryComponent = null) -> bool:
	if not can_socket_support(index, item):
		return false
	if inventory != null and not inventory.remove_item(item):
		return false
	var s := sockets[index]
	s.supports.append(item)
	_rebuild(s)
	GameEvents.report("socket_support", item.definition.support_gem.id)
	changed.emit()
	return true


func unsocket_support(index: int, support_index: int, inventory: InventoryComponent) -> bool:
	if index < 0 or index >= sockets.size() or inventory.is_full() or sandbox_locked:
		return false
	var s := sockets[index]
	if support_index < 0 or support_index >= s.supports.size():
		return false
	var item := s.supports[support_index]
	s.supports.remove_at(support_index)
	inventory.add_item(item)
	_rebuild(s)
	changed.emit()
	return true


func preview_program(index: int, program: SkillProgram, draft_routines: Variant = null) -> ProgramValidation:
	if index < 0 or index >= sockets.size() or sockets[index].gem == null:
		var v := ProgramValidation.new()
		v.add_error("No skill in this socket.")
		return v
	var limits := program_limits_for(index)
	if limits != null and draft_routines is Array:
		limits.routines = draft_routines
	return program.validate(limits)


func program_limits_for(index: int) -> SkillProgramLimits:
	if index < 0 or index >= sockets.size() or sockets[index].skill == null:
		return null
	return sockets[index].skill.get_program_limits()


func set_program(index: int, program: SkillProgram) -> ProgramValidation:
	if program == null:
		if index >= 0 and index < sockets.size() and sockets[index].gem != null:
			sockets[index].program = null
			sockets[index].sets[script_set] = null
			_rebuild(sockets[index])
			changed.emit()
		return null
	var result := preview_program(index, program)
	if result.valid:
		var s := sockets[index]
		s.program = program
		s.sets[script_set] = program
		_rebuild(s)
		_report_program(index)
		changed.emit()
	return result


func _report_program(index: int) -> void:
	var s := sockets[index]
	if s.program == null or s.skill == null:
		return
	var gem := s.gem.definition.skill_gem
	GameEvents.report("program_applied", gem.id)
	for t in gem.tags:
		GameEvents.report("program_applied_tag", TagTypes.name_of(TagTypes.TagGem, t))
	var conditions := {}
	var nested := false
	var branches := 0
	for rule in s.program.flat_rules():
		if not rule.is_always():
			branches += 1
		if rule.conditions.size() >= 2:
			nested = true
		for c in rule.conditions:
			conditions[c.type_id()] = true
	for type_id in conditions:
		GameEvents.report("program_condition", type_id)
	for rule in s.program.rules:
		if rule.loop != null:
			GameEvents.report("program_loop", "while" if rule.loop.mode == ProgramLoop.Mode.WHILE else "for")
	if nested:
		GameEvents.report("program_nested")
	if branches >= 2:
		GameEvents.report("program_branches")
	for routine_index in s.program.called_routines():
		GameEvents.report("program_routine", str(routine_index))
	var v := s.skill.program_validation
	if v != null and v.tier != null:
		GameEvents.report("program_efficient", v.tier.display_name.to_lower())


func switch_script_set(index: int, force := false) -> String:
	if index < 0 or index >= SCRIPT_SETS:
		return "NO SUCH SET"
	if index == script_set:
		return ""
	if not force and not set_unlocked(index):
		return "RANK %s UNLOCKS SET %s" % [Ranks.first_with("sets", index + 1), SET_NAMES[index]]
	script_set = index
	_apply_set()
	GameEvents.report("script_set", SET_NAMES[index])
	script_set_changed.emit(index)
	changed.emit()
	return ""


func copy_set(from: int) -> void:
	if from < 0 or from >= SCRIPT_SETS or from == script_set or not set_unlocked(from):
		return
	for s in sockets:
		if s.gem != null:
			s.sets[script_set] = (s.sets[from] as SkillProgram).duplicate_program() if s.sets[from] != null else null
	_apply_set()
	script_set_changed.emit(script_set)
	changed.emit()


func _apply_set() -> void:
	for i in sockets.size():
		var s := sockets[i]
		if s.gem == null:
			continue
		var next: SkillProgram = s.sets[script_set]
		s.program = null
		if next != null:
			next.prune_owners(s.supports.map(func(it: ItemInstance) -> String: return it.definition.support_gem.id))
			if preview_program(i, next).valid:
				s.program = next
		_rebuild(s)


func sets_unlocked() -> int:
	return clampi(int(Ranks.perk(rank(), "sets")), 1, SCRIPT_SETS)


func set_unlocked(index: int) -> bool:
	return index >= 0 and index < sets_unlocked()


func set_label(index: int) -> String:
	if index < 0 or index >= SCRIPT_SETS:
		return "?"
	return set_names[index] if index < set_names.size() and set_names[index] != "" else SET_NAMES[index]


func rename_set(index: int, new_name: String) -> void:
	if index < 0 or index >= SCRIPT_SETS:
		return
	if set_names.size() < SCRIPT_SETS:
		set_names.resize(SCRIPT_SETS)
	var clean := new_name.strip_edges().to_upper().left(SET_NAME_MAX)
	set_names[index] = clean if clean != "" else SET_NAMES[index]
	changed.emit()


func set_names_list() -> Array:
	var out: Array = []
	for i in SCRIPT_SETS:
		out.append(set_label(i))
	return out


func restore_set_names(saved: Array) -> void:
	set_names = PackedStringArray(SET_NAMES)
	for i in mini(saved.size(), SCRIPT_SETS):
		if saved[i] is String:
			set_names[i] = (saved[i] as String).to_upper().left(SET_NAME_MAX)


func snapshot() -> Dictionary:
	var socks: Array = []
	for s in sockets:
		socks.append({"gem": s.gem, "supports": s.supports.duplicate(), "sets": s.sets.duplicate(),
				"program": s.program})
	return {"sockets": socks, "bindings": bindings.duplicate(), "script_set": script_set,
			"set_names": set_names.duplicate(), "routines": routines.duplicate()}


func restore(snap: Dictionary) -> void:
	routines.assign(snap.get("routines", routines))
	_held_routines.clear()
	routines_version += 1
	var socks: Array = snap.get("sockets", [])
	for i in mini(socks.size(), sockets.size()):
		var s := sockets[i]
		var saved: Dictionary = socks[i]
		s.gem = saved["gem"]
		s.supports.assign(saved["supports"])
		s.sets = (saved["sets"] as Array).duplicate()
		s.program = null
		if s.gem != null:
			_rebuild(s)
		else:
			s.skill = null
	bindings = (snap.get("bindings", {}) as Dictionary).duplicate()
	script_set = int(snap.get("script_set", 0))
	set_names = PackedStringArray(snap.get("set_names", SET_NAMES))
	_apply_set()
	RollbackWatch.sync(self)
	script_set_changed.emit(script_set)
	changed.emit()


func strip_for_exam() -> void:
	_held_routines = routines.duplicate()
	routines.clear()
	routines_version += 1
	for s in sockets:
		if s.gem == null:
			continue
		s.supports.clear()
		s.sets.fill(null)
		s.program = null
		_rebuild(s)
	script_set = 0
	script_set_changed.emit(0)
	changed.emit()


func has_routines() -> bool:
	return Ranks.perk(rank(), "routines")


func set_routines(list: Array) -> void:
	routines.clear()
	routines_version += 1
	for r in list.slice(0, ProgramRoutine.MAX_ROUTINES):
		if r is ProgramRoutine:
			routines.append((r as ProgramRoutine).duplicate_routine())
	for s in sockets:
		if s.skill != null:
			s.skill.routines = routines
	_apply_set()
	changed.emit()


func callers_of(index: int) -> Array:
	var out: Array = []
	for i in sockets.size():
		var p := sockets[i].program
		if p != null and index in p.called_routines():
			out.append(i)
	return out


func routines_to_list() -> Array:
	var src: Array = _held_routines if sandbox_locked else routines
	return src.map(func(r: ProgramRoutine) -> Dictionary: return r.to_dict())


func restore_routines(saved: Array) -> void:
	routines.clear()
	routines_version += 1
	for d in saved.slice(0, ProgramRoutine.MAX_ROUTINES):
		if d is Dictionary:
			routines.append(ProgramRoutine.from_dict(d))


func has_library() -> bool:
	return Ranks.perk(rank(), "library")


func library_for(index: int) -> Array:
	if index < 0 or index >= sockets.size() or sockets[index].gem == null:
		return []
	var gem_id := sockets[index].gem.definition.skill_gem.id
	return library.filter(func(e: Dictionary) -> bool: return e.get("gem", "") == gem_id)


func library_save(index: int, entry_name: String, program: SkillProgram) -> String:
	if not has_library():
		return "RANK %s UNLOCKS THE LIBRARY" % Ranks.first_with("library")
	if index < 0 or index >= sockets.size() or sockets[index].gem == null or program == null:
		return "NO SKILL"
	if not program.has_rules():
		return "NOTHING TO SAVE"
	var clean := entry_name.strip_edges().to_upper().left(LIBRARY_NAME_MAX)
	if clean == "":
		return "NAME IT FIRST"
	var gem_id := sockets[index].gem.definition.skill_gem.id
	var entry := {"name": clean, "gem": gem_id, "program": program.to_dict()}
	for i in library.size():
		if library[i]["gem"] == gem_id and library[i]["name"] == clean:
			library[i] = entry
			return ""
	if library.size() >= LIBRARY_SIZE:
		return "LIBRARY FULL (%d): DELETE ONE FIRST" % LIBRARY_SIZE
	library.append(entry)
	return ""


func library_delete(entry: Dictionary) -> void:
	library.erase(entry)


func library_program(index: int, entry: Dictionary) -> SkillProgram:
	var p := SkillProgram.from_dict(entry.get("program", {}))
	if index >= 0 and index < sockets.size() and sockets[index].gem != null:
		p.prune_owners(sockets[index].supports.map(func(it: ItemInstance) -> String: return it.definition.support_gem.id))
	return p


func restore_library(saved: Array) -> void:
	library.clear()
	for e in saved:
		if e is Dictionary and e.get("name") is String and e.get("gem") is String and e.get("program") is Dictionary:
			library.append(e)
		if library.size() >= LIBRARY_SIZE:
			break


func set_is_empty(index: int) -> bool:
	for s in sockets:
		if s.gem != null and s.sets[index] != null:
			return false
	return true


func uses_scripts() -> bool:
	for s in sockets:
		for p in s.sets:
			if p != null:
				return true
	return false


func sets_to_list(index: int) -> Array:
	var out: Array = []
	for p in sockets[index].sets:
		out.append((p as SkillProgram).to_dict() if p != null and (p as SkillProgram).has_rules() else null)
	return out


func restore_sets(index: int, saved: Array) -> ProgramValidation:
	var s := sockets[index]
	for k in mini(saved.size(), SCRIPT_SETS):
		s.sets[k] = SkillProgram.from_dict(saved[k]) if saved[k] is Dictionary else null
	var active: SkillProgram = s.sets[script_set]
	if active == null:
		return null
	var result := set_program(index, active)
	return result


func get_program(index: int) -> SkillProgram:
	if index < 0 or index >= sockets.size():
		return null
	return sockets[index].program


func stored_program(index: int) -> SkillProgram:
	if index < 0 or index >= sockets.size() or sockets[index].gem == null:
		return null
	return sockets[index].sets[script_set]


func _rebuild(s: Socket) -> void:
	var skill := SkillInstance.new()
	skill.gem = s.gem.definition.skill_gem
	var support_ids: Array = []
	for item in s.supports:
		skill.supports.append(item.definition.support_gem)
		support_ids.append(item.definition.support_gem.id)
	if s.program != null:
		s.program.prune_owners(support_ids)
	skill.program = s.program
	skill.routines = routines
	skill.class_trait = _class_trait()
	skill.rank = rank()
	skill.bonus_points = bonus_points()
	skill.bonus_steps = bonus_steps()
	skill.owner_ref = weakref(get_parent())
	skill.rebuild()
	s.skill = skill
	_apply_trait_rule_bonuses()
	RollbackWatch.sync(self)


func _class_trait() -> ClassTrait:
	var cd = get_parent().get("class_data")
	return (cd as ClassData).get_trait() if cd is ClassData else null


func _apply_trait_rule_bonuses() -> void:
	var t := _class_trait()
	var stats := get_parent().get("stats") as StatComponent
	if t == null or stats == null:
		return
	var always_rules := 0
	var total_rules := 0
	var knob_steps := 0
	var blocks := 0
	for sock in sockets:
		if sock.skill == null or sock.program == null or sock.skill.program_validation == null \
				or not sock.skill.program_validation.valid:
			continue
		blocks += sock.skill.program_validation.actions_used
		var limits := sock.skill.get_program_limits()
		for r in sock.program.rules:
			total_rules += 1
			if r.is_always():
				always_rules += 1
			for e in r.effects:
				if ScriptRegisters.is_write(e.knob) or limits == null:
					continue
				var k := limits.get_knob(e.knob)
				if k != null and k.cost_for(e.steps) > 0.0:
					knob_steps += absi(e.steps)
	t.apply_rule_bonuses(stats, always_rules, total_rules, knob_steps, blocks)
