class_name SkillComponent
extends Node
## Path of Exile 2 style skills.
##  - Skill gems are ITEMS. Each is socketed into one of the skill sockets below.
##  - Support gems are items too. They are socketed into a skill's own support slots.
##  - Each socketed skill can be bound to one input action (attack, skill_1, ...).
## Add as a child node of the player. This replaces the old equipped_skills list.

## Every action a skill can be bound to. These must exist in the Input Map.
const ACTIONS: Array[StringName] = [&"attack", &"attack_2", &"skill_1", &"skill_2", &"skill_3", &"skill_4"]

@export var socket_count: int = 6

## One skill socket: the skill gem item, its support gem items, and the runtime skill built from them.
class Socket extends RefCounted:
	var gem: ItemInstance
	var supports: Array[ItemInstance] = []
	var skill: SkillInstance
	## The player's program for this skill (null = none). The active script set's program.
	var program: SkillProgram
	## This skill's program in each script set (null = none). sets[script_set] is `program`,
	## or a program that no longer fits (it stays stored, and the skill runs without it).
	var sets: Array = []

	func _init() -> void:
		sets.resize(SkillComponent.SCRIPT_SETS)

var sockets: Array[Socket] = []
var bindings: Dictionary = {}          # action (StringName) -> socket index

## Script sets: every skill keeps one program per set, and the whole set swaps at once
## (the script_set key, or the tabs in the SCRIPTING editor). One set for swarms, one for
## tough single targets... Sets start empty; copy_set() copies another set into the current one.
const SCRIPT_SETS := 3
## Default set names. Players can rename sets (rename_set); set_label() gives the name to show.
const SET_NAMES := ["A", "B", "C"]
const SET_NAME_MAX := 10
## No swapping with a living enemy this close (metres): sets are chosen between fights.
const COMBAT_RANGE := 12.0
var script_set := 0
var set_names := PackedStringArray(SET_NAMES)

## Script library (rank ARCHITECT, Ranks.PERKS "library"): named programs kept apart from the
## sets, to load onto the same skill again later (into another set, or after a gem swap).
## Each entry: {"name": String, "gem": skill gem id, "program": SkillProgram.to_dict()}. Saved.
const LIBRARY_SIZE := 12
const LIBRARY_NAME_MAX := 14
var library: Array = []

## Sudo's sandbox (ExamChamber): the exam's skills are fixed, so no gem or support can be
## socketed or taken out while this is on. See snapshot() / restore() / strip_for_exam().
var sandbox_locked := false

## Fired after any socketing, unsocketing or rebinding, so UI can refresh.
signal changed
## Fired after the script set changes (`changed` fires too).
signal script_set_changed(index: int)


func _ready() -> void:
	for i in socket_count:
		sockets.append(Socket.new())
	_watch_rank.call_deferred()


## Passing a rank exam changes the limits (Ranks.PERKS), so every skill rebuilds.
func _watch_rank() -> void:
	var qm := get_parent().get("quests") as QuestManager
	if qm != null and not qm.quest_completed.is_connected(_on_quest_completed):
		qm.quest_completed.connect(_on_quest_completed)


func _on_quest_completed(_state: QuestState) -> void:
	refresh_rank()


## The owner's rank (Ranks.LADDER index).
func rank() -> int:
	return Ranks.of(get_parent())


## Re-checks every skill's program with the current rank's limits: programs that didn't fit
## before (too many rules for a lower rank) apply now.
func refresh_rank() -> void:
	var r := rank()
	for s in sockets:
		if s.skill != null:
			s.skill.rank = r
	_apply_set()
	changed.emit()


# ---------- USING SKILLS ----------
## The skill bound to an action, or null if the key has nothing on it.
func get_skill(action: StringName) -> SkillInstance:
	var index: int = bindings.get(action, -1)
	if index < 0 or index >= sockets.size():
		return null
	return sockets[index].skill


## The action a socket is bound to, or &"" if it isn't bound.
func action_of(index: int) -> StringName:
	for action in bindings:
		if bindings[action] == index:
			return action
	return &""


# ---------- BINDING ----------
## A skill can only sit on one key, so binding it moves it. Whatever was on the key is replaced.
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


# ---------- SKILL GEMS ----------
## Socket a skill gem item into an EMPTY skill socket. Pass the inventory to take the item out of it.
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

## Returns the skill gem AND all its supports to the backpack. Fails if there isn't room for all of them.
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


# ---------- SUPPORT GEMS ----------
## True if this support gem item can go into the skill in that socket right now.
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
			return false                        # no duplicate supports on one skill
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


# ---------- PROGRAMS ----------
## Checks a program against the socketed skill's limits without applying it (for live UI).
func preview_program(index: int, program: SkillProgram) -> ProgramValidation:
	if index < 0 or index >= sockets.size() or sockets[index].gem == null:
		var v := ProgramValidation.new()
		v.add_error("No skill in this socket.")
		return v
	return program.validate(program_limits_for(index))


## Knobs, budget and tiers for the skill in a socket, including its supports' knobs.
func program_limits_for(index: int) -> SkillProgramLimits:
	if index < 0 or index >= sockets.size() or sockets[index].skill == null:
		return null
	return sockets[index].skill.get_program_limits()


## Applies a program to a socket if it is valid. Returns the check result either way, so the
## editor can show what is wrong. Pass null to remove the program.
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


## Quest events for an applied program (see data/quests). Loading a save mutes GameEvents,
## so only programs the player applies count.
##   program_applied      skill gem id ("strike")
##   program_applied_tag  each gem tag ("melee", "area", "projectile", ...)
##   program_condition    each condition used ("enemies_nearby", "every_nth_cast", ...)
##   program_nested       a rule with two or more conditions ("when a and b")
##   program_branches     two or more WHEN rules on one skill
##   program_efficient    the efficiency tier earned ("lean", "elegant")
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
	for rule in s.program.rules:
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
	var v := s.skill.program_validation
	if v != null and v.tier != null:
		GameEvents.report("program_efficient", v.tier.display_name.to_lower())


# ---------- SCRIPT SETS ----------
## Swaps every skill to its program in set `index`. Returns "" when done, or why not.
## force: skip the combat check (loading a save).
func switch_script_set(index: int, force := false) -> String:
	if index < 0 or index >= SCRIPT_SETS:
		return "NO SUCH SET"
	if index == script_set:
		return ""
	if not force and not set_unlocked(index):
		return "RANK %s UNLOCKS SET %s" % [Ranks.first_with("sets", index + 1), SET_NAMES[index]]
	if not force and in_combat():
		return "ENEMIES NEARBY: SWAP SETS BETWEEN FIGHTS"
	script_set = index
	_apply_set()
	GameEvents.report("script_set", SET_NAMES[index])        # quests see the fixed letter
	script_set_changed.emit(index)              # first, so the editor drops the old set's drafts
	changed.emit()
	return ""


## Copies every skill's program in set `from` into the current set (replacing what is there).
func copy_set(from: int) -> void:
	if from < 0 or from >= SCRIPT_SETS or from == script_set or not set_unlocked(from):
		return
	for s in sockets:
		if s.gem != null:
			s.sets[script_set] = (s.sets[from] as SkillProgram).duplicate_program() if s.sets[from] != null else null
	_apply_set()
	script_set_changed.emit(script_set)
	changed.emit()


## Runs each skill with its program in the current set (none if the set has none for it, or
## it no longer fits).
func _apply_set() -> void:
	for i in sockets.size():
		var s := sockets[i]
		if s.gem == null:
			continue
		var next: SkillProgram = s.sets[script_set]
		s.program = null
		if next != null:
			# supports removed while this set was put away take their rules with them
			next.prune_owners(s.supports.map(func(it: ItemInstance) -> String: return it.definition.support_gem.id))
			if preview_program(i, next).valid:
				s.program = next
		_rebuild(s)


## How many script sets the owner's rank lets them use (Ranks.PERKS "sets"): A, then B, then C.
## Programs in a locked set stay stored; they come back once the rank unlocks it.
func sets_unlocked() -> int:
	return clampi(int(Ranks.perk(rank(), "sets")), 1, SCRIPT_SETS)


func set_unlocked(index: int) -> bool:
	return index >= 0 and index < sets_unlocked()


## The name a set shows: the player's name for it, or its letter.
func set_label(index: int) -> String:
	if index < 0 or index >= SCRIPT_SETS:
		return "?"
	return set_names[index] if index < set_names.size() and set_names[index] != "" else SET_NAMES[index]


## Renames a set ("SWARM", "BOSS"...). Upper case, at most SET_NAME_MAX letters; an empty
## name puts the letter back.
func rename_set(index: int, new_name: String) -> void:
	if index < 0 or index >= SCRIPT_SETS:
		return
	if set_names.size() < SCRIPT_SETS:
		set_names.resize(SCRIPT_SETS)
	var clean := new_name.strip_edges().to_upper().left(SET_NAME_MAX)
	set_names[index] = clean if clean != "" else SET_NAMES[index]
	changed.emit()


## For the save, and back.
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


# ---------- EXAM SANDBOX ----------
## Everything about the skills, by reference, to put back exactly with restore().
func snapshot() -> Dictionary:
	var socks: Array = []
	for s in sockets:
		socks.append({"gem": s.gem, "supports": s.supports.duplicate(), "sets": s.sets.duplicate(),
				"program": s.program})
	return {"sockets": socks, "bindings": bindings.duplicate(), "script_set": script_set,
			"set_names": set_names.duplicate()}


func restore(snap: Dictionary) -> void:
	var socks: Array = snap.get("sockets", [])
	for i in mini(socks.size(), sockets.size()):
		var s := sockets[i]
		var saved: Dictionary = socks[i]
		s.gem = saved["gem"]
		s.supports.assign(saved["supports"])
		s.sets = (saved["sets"] as Array).duplicate()
		s.program = null
		if s.gem != null:
			_rebuild(s)                         # the skill first: _apply_set checks programs against it
		else:
			s.skill = null
	bindings = (snap.get("bindings", {}) as Dictionary).duplicate()
	script_set = int(snap.get("script_set", 0))
	set_names = PackedStringArray(snap.get("set_names", SET_NAMES))
	_apply_set()                                # each skill runs its program in the restored set
	RollbackWatch.sync(self)
	script_set_changed.emit(script_set)
	changed.emit()


## The exam loadout: the same skill gems on the same keys, without supports or scripts.
func strip_for_exam() -> void:
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


# ---------- SCRIPT LIBRARY ----------
func has_library() -> bool:
	return Ranks.perk(rank(), "library")


## The library's entries for the skill in a socket (same skill gem), oldest first.
func library_for(index: int) -> Array:
	if index < 0 or index >= sockets.size() or sockets[index].gem == null:
		return []
	var gem_id := sockets[index].gem.definition.skill_gem.id
	return library.filter(func(e: Dictionary) -> bool: return e.get("gem", "") == gem_id)


## Saves `program` for the skill in a socket under `entry_name` (the same name replaces it).
## Returns "" when saved, or why not.
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


## A fresh copy of an entry's program for the skill in a socket: rules of supports that
## aren't socketed there now are left out.
func library_program(index: int, entry: Dictionary) -> SkillProgram:
	var p := SkillProgram.from_dict(entry.get("program", {}))
	if index >= 0 and index < sockets.size() and sockets[index].gem != null:
		p.prune_owners(sockets[index].supports.map(func(it: ItemInstance) -> String: return it.definition.support_gem.id))
	return p


## From the save: keeps only well-formed entries.
func restore_library(saved: Array) -> void:
	library.clear()
	for e in saved:
		if e is Dictionary and e.get("name") is String and e.get("gem") is String and e.get("program") is Dictionary:
			library.append(e)
		if library.size() >= LIBRARY_SIZE:
			break


## True when no skill has a program in set `index`.
func set_is_empty(index: int) -> bool:
	for s in sockets:
		if s.gem != null and s.sets[index] != null:
			return false
	return true


## True when any skill has a program in any set (the HUD only shows sets once scripting starts).
func uses_scripts() -> bool:
	for s in sockets:
		for p in s.sets:
			if p != null:
				return true
	return false


## A living enemy within COMBAT_RANGE of the owner.
func in_combat() -> bool:
	var me := get_parent() as Node3D
	if me == null or not me.is_inside_tree():
		return false
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var hp := e.get("health") as HealthComponent
		if e is Node3D and hp != null and hp.current_health > 0.0 \
				and (e as Node3D).global_position.distance_to(me.global_position) <= COMBAT_RANGE:
			return true
	return false


## For the save: each set's program as a dictionary (or null).
func sets_to_list(index: int) -> Array:
	var out: Array = []
	for p in sockets[index].sets:
		out.append((p as SkillProgram).to_dict() if p != null and (p as SkillProgram).has_rules() else null)
	return out


## From the save: fills every set of a socket, then applies the active set's program.
## Returns the active program's check (null when it has none).
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


# ---------- INTERNAL ----------
## Builds the runtime SkillInstance from the socketed gem items.
func _rebuild(s: Socket) -> void:
	var skill := SkillInstance.new()
	skill.gem = s.gem.definition.skill_gem
	var support_ids: Array = []
	for item in s.supports:
		skill.supports.append(item.definition.support_gem)
		support_ids.append(item.definition.support_gem.id)
	if s.program != null:
		s.program.prune_owners(support_ids)        # a removed support takes its rules with it
	skill.program = s.program
	skill.class_trait = _class_trait()
	skill.rank = rank()
	skill.rebuild()
	s.skill = skill
	_apply_trait_rule_bonuses()
	RollbackWatch.sync(self)


## The owning character's class trait, or null.
func _class_trait() -> ClassTrait:
	var cd = get_parent().get("class_data")
	return (cd as ClassData).get_trait() if cd is ClassData else null


## Paladin / Rogue: bonuses from the rules in every applied (valid) program.
func _apply_trait_rule_bonuses() -> void:
	var t := _class_trait()
	var stats := get_parent().get("stats") as StatComponent
	if t == null or stats == null:
		return
	var always_rules := 0
	var total_rules := 0
	for sock in sockets:
		if sock.skill == null or sock.program == null or sock.skill.program_validation == null \
				or not sock.skill.program_validation.valid:
			continue
		for r in sock.program.rules:
			total_rules += 1
			if r.is_always():
				always_rules += 1
	t.apply_rule_bonuses(stats, always_rules, total_rules)
