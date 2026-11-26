class_name QuestManager
extends Node

signal quest_started(state: QuestState)
signal quest_updated(state: QuestState)
signal quest_ready(state: QuestState)
signal quest_completed(state: QuestState)
signal reward_choice_changed
signal item_recovered(id: String)
signal budget_changed

@export_dir var quest_folder: String = "res://data/quests/"

var catalog: Dictionary = {}
var active: Dictionary = {}
var completed_ids: Array[String] = []
var pending_choices: Array[String] = []
var recovered: Array[String] = []
var exam_grades: Dictionary = {}
var deeds: Dictionary = {}
const DEED_KINDS: Array[String] = ["kill", "kill_at", "enter_area", "clear_area", "act_boss",
		"hull_breach", "salvage", "stop_finished", "blobs_freed", "yard_sweep", "sweep_lost", "crate_restored", "crate_mourned", "kernel_null", "kernel_merge", "kernel_overwrite", "kernel_terminate", "ending", "said"]

var _player: Node


func _ready() -> void:
	_player = get_parent()
	_scan_catalog()
	GameEvents.happened.connect(_on_event)


func _scan_catalog() -> void:
	catalog.clear()
	var dir := DirAccess.open(quest_folder)
	if dir == null:
		push_warning("QuestManager: folder not found: %s" % quest_folder)
		return
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var q := load(quest_folder.path_join(name)) as QuestDefinition
		if q == null:
			continue
		if q.id == "":
			push_warning("QuestManager: %s has no id, skipped" % name)
			continue
		catalog[q.id] = q


func get_def(id: String) -> QuestDefinition:
	return catalog.get(id)


func is_active(id: String) -> bool:
	return active.has(id)


func is_completed(id: String) -> bool:
	return completed_ids.has(id)


func get_state(id: String) -> QuestState:
	return active.get(id)


func ready_to_turn_in() -> Array[QuestState]:
	var out: Array[QuestState] = []
	for s: QuestState in active.values():
		if s.status == QuestState.Status.READY_TO_TURN_IN:
			out.append(s)
	return out


func can_start(q: QuestDefinition) -> bool:
	if q == null or active.has(q.id) or completed_ids.has(q.id):
		return false
	for pre in q.prerequisite_quest_ids:
		if not completed_ids.has(pre):
			return false
	return _act_allows(q)


func _act_allows(q: QuestDefinition) -> bool:
	var act := str(q.get_meta("act", ""))
	if act == "" or not is_inside_tree():
		return true
	var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
	var town := am.current_area as TownArea if am != null else null
	return town == null or town.act == act


func has_recovered(id: String) -> bool:
	return recovered.has(id)


func recover(id: String) -> void:
	if id == "" or recovered.has(id):
		return
	recovered.append(id)
	item_recovered.emit(id)
	GameEvents.report("recover", id)


func deed_count(kind: String, target: String) -> int:
	return int(deeds.get("%s:%s" % [kind, target], 0))


func record_exam(rank: String, grade: int) -> bool:
	if exam_grades.has(rank) and int(exam_grades[rank]) >= grade:
		return false
	exam_grades[rank] = grade
	budget_changed.emit()
	return true


func exam_grade(rank: String) -> int:
	return int(exam_grades.get(rank, -1))


func start_by_id(id: String) -> bool:
	return start(get_def(id))


func start(q: QuestDefinition) -> bool:
	if not can_start(q):
		return false
	var s := QuestState.new(q)

	_credit_already_met(s)

	active[q.id] = s
	quest_started.emit(s)
	_check_ready(s)
	return true


func _on_event(kind: String, target: String, amount: int) -> void:
	if kind in DEED_KINDS and target != "":
		var key := "%s:%s" % [kind, target]
		var first := not deeds.has(key)
		deeds[key] = int(deeds.get(key, 0)) + amount
		if first and (kind == ScriptBudget.CLEAR_DEED or kind == ScriptBudget.BOSS_DEED):
			budget_changed.emit()
	for s: QuestState in active.values().duplicate():
		if s.status != QuestState.Status.ACTIVE:
			continue
		if s.handle_event(kind, target, amount):
			_credit_already_met(s)
			quest_updated.emit(s)
			_check_ready(s)


func _credit_already_met(s: QuestState) -> bool:
	var credited := false
	for i in s.def.objectives.size():
		if s.objective_done(i):
			continue
		var obj := s.def.objectives[i]
		if obj.already_met(_player):
			s.progress[i] = obj.required
			credited = true
		elif s.def.ordered:
			break
	return credited


func _check_ready(s: QuestState) -> void:
	if s.status == QuestState.Status.ACTIVE and s.all_done():
		s.status = QuestState.Status.READY_TO_TURN_IN
		quest_ready.emit(s)


func turn_in(id: String) -> String:
	var s: QuestState = active.get(id)
	if s == null or s.status != QuestState.Status.READY_TO_TURN_IN:
		return "QUEST NOT READY"
	var q := s.def

	var inv: InventoryComponent = _player.get("inventory")
	var slots_needed := q.reward_items.size() + (1 if q.reward_support_choice else 0)
	if slots_needed > 0:
		if inv == null or inv.capacity - inv.items.size() < slots_needed:
			return "BACKPACK FULL"

	if q.reward_credits > 0 and _player.get("currency") != null:
		_player.currency.add(q.reward_credits)
	for def in q.reward_items:
		inv.add_item(_make_reward_item(def))

	s.status = QuestState.Status.COMPLETED
	active.erase(id)
	completed_ids.append(id)
	quest_completed.emit(s)
	GameEvents.report("quest_done", id)
	if q.reward_support_choice and not support_choices().is_empty():
		pending_choices.append(id)
		reward_choice_changed.emit()

	if q.next_quest != null:
		start(q.next_quest)
	return ""


func _make_reward_item(def: ItemDefinition) -> ItemInstance:
	if def.is_gem():
		return ItemInstance.make_gem(def)
	return ItemGenerator.generate_item(def, def.item_level, "normal")


func to_dict() -> Dictionary:
	var list := []
	for s: QuestState in active.values():
		list.append(s.to_dict())
	return {"active": list, "completed": completed_ids, "pending_choices": pending_choices,
		"recovered": recovered.duplicate(), "exam_grades": exam_grades.duplicate(),
		"deeds": deeds.duplicate()}


const TUTORIAL_QUESTS: Array[String] = ["tut_basics", "q00_proximity_trigger"]


func tutorial_finished() -> bool:
	for id in TUTORIAL_QUESTS:
		if catalog.has(id) and not is_completed(id):
			return false
	return true


func keep_reason(item: ItemInstance) -> String:
	if item == null or tutorial_finished():
		return ""
	var cd = _player.get("class_data")
	if cd == null or cd.starting_skill_gem == null or item.definition != cd.starting_skill_gem:
		return ""
	if _copies_owned(item.definition) > 1:
		return ""
	return "NEEDED FOR THE TUTORIAL: FINISH IT FIRST"


func _copies_owned(def: ItemDefinition) -> int:
	var n := 0
	var inv: InventoryComponent = _player.get("inventory")
	if inv != null:
		for it in inv.items:
			if it != null and it.definition == def:
				n += 1
	var skills: SkillComponent = _player.get("skills")
	if skills != null:
		for s in skills.sockets:
			if s.gem != null and s.gem.definition == def:
				n += 1
	return n


func starting_skill() -> SkillGemDefinition:
	var cd = _player.get("class_data")
	if cd != null and cd.starting_skill_gem != null and cd.starting_skill_gem.skill_gem != null:
		return cd.starting_skill_gem.skill_gem
	var skills: SkillComponent = _player.get("skills")
	if skills != null:
		for s in skills.sockets:
			if s.gem != null:
				return s.gem.definition.skill_gem
	return null


func support_choices() -> Array[ItemDefinition]:
	var out: Array[ItemDefinition] = []
	var skill := starting_skill()
	if skill == null:
		return out
	for def in ItemDatabase.all_items():
		var item := def as ItemDefinition
		if item == null or item.support_gem == null:
			continue
		if not Ranks.allows(Ranks.index_of(self), "gem:" + item.support_gem.id):
			continue
		for t in item.support_gem.allowed_tags:
			if t in skill.tags:
				out.append(item)
				break
	out.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool:
		return a.support_gem.display_name < b.support_gem.display_name)
	return out


func claim_choice(def: ItemDefinition) -> String:
	if pending_choices.is_empty():
		return "NOTHING TO CLAIM"
	if def == null or not (def in support_choices()):
		return "THAT GEM ISN'T ONE OF THE CHOICES"
	var inv: InventoryComponent = _player.get("inventory")
	if inv == null or not inv.add_item(ItemInstance.make_gem(def)):
		return "BACKPACK FULL: MAKE ROOM, THEN PICK"
	pending_choices.remove_at(0)
	reward_choice_changed.emit()
	return ""


func from_dict(d: Dictionary) -> void:
	active.clear()
	completed_ids.clear()
	pending_choices.clear()
	recovered.clear()
	exam_grades.clear()
	var grades: Dictionary = d.get("exam_grades", {})
	for k in grades:
		exam_grades[str(k)] = int(grades[k])
	for id in d.get("recovered", []):
		recovered.append(str(id))
	if recovered.has("dock_held") and not recovered.has("outpost_evacuated"):
		recovered.append("outpost_evacuated")
	deeds.clear()
	var saved_deeds: Dictionary = d.get("deeds", {})
	for k in saved_deeds:
		deeds[str(k)] = int(saved_deeds[k])
	for id in d.get("completed", []):
		completed_ids.append(str(id))
	for id in d.get("pending_choices", []):
		pending_choices.append(str(id))
	for e in d.get("active", []):
		var q := get_def(str(e.get("id", "")))
		if q == null:
			push_warning("QuestManager: saved quest %s no longer exists, dropped" % str(e.get("id", "")))
			continue
		var s := QuestState.new(q)
		var saved: Array = e.get("progress", [])
		if saved.size() == s.progress.size():
			for i in saved.size():
				s.progress[i] = int(saved[i])
			s.status = int(e.get("status", QuestState.Status.ACTIVE))
		else:
			push_warning("QuestManager: %s changed since this save, its progress was reset" % q.id)
			for i in q.objectives.size():
				if q.objectives[i].already_met(_player):
					s.progress[i] = q.objectives[i].required
			_check_ready(s)
		active[q.id] = s
		quest_updated.emit(s)
