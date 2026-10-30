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
	## The player's program for this skill (null = none).
	var program: SkillProgram

var sockets: Array[Socket] = []
var bindings: Dictionary = {}          # action (StringName) -> socket index

## Fired after any socketing, unsocketing or rebinding, so UI can refresh.
signal changed


func _ready() -> void:
	for i in socket_count:
		sockets.append(Socket.new())


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
	if s.gem != null or item == null or item.definition == null or item.definition.skill_gem == null:
		return false
	if inventory != null and not inventory.remove_item(item):
		return false
	s.gem = item
	s.supports.clear()
	s.program = null
	_rebuild(s)
	GameEvents.report("socket_skill", item.definition.id)
	changed.emit()
	return true

## Returns the skill gem AND all its supports to the backpack. Fails if there isn't room for all of them.
func unsocket_skill(index: int, inventory: InventoryComponent) -> bool:
	if index < 0 or index >= sockets.size():
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
	for a in bindings.keys():
		if bindings[a] == index:
			bindings.erase(a)
	for item in returning:
		inventory.add_item(item)
	changed.emit()
	return true


# ---------- SUPPORT GEMS ----------
## True if this support gem item can go into the skill in that socket right now.
func can_socket_support(index: int, item: ItemInstance) -> bool:
	if index < 0 or index >= sockets.size():
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
	if index < 0 or index >= sockets.size() or inventory.is_full():
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
			_rebuild(sockets[index])
			changed.emit()
		return null
	var result := preview_program(index, program)
	if result.valid:
		var s := sockets[index]
		s.program = program
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
	skill.rebuild()
	s.skill = skill
	_apply_trait_rule_bonuses()


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
