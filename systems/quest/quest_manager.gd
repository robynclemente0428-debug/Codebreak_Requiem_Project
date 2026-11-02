class_name QuestManager
extends Node
## Lives on the Player as a child node. Tracks active and completed quests,
## listens to GameEvents, and hands out rewards.

signal quest_started(state: QuestState)
signal quest_updated(state: QuestState)
signal quest_ready(state: QuestState)        # all objectives done, waiting for turn-in
signal quest_completed(state: QuestState)
## A "pick a support gem" reward is waiting, or was just claimed (see pending_choices).
signal reward_choice_changed
## A quest item was picked up or a ward beacon reached for the first time (see recover()).
signal item_recovered(id: String)

## Every quest in the game is found in this folder, so you never fill an array by hand.
@export_dir var quest_folder: String = "res://data/quests/"

var catalog: Dictionary = {}                 # id -> QuestDefinition
var active: Dictionary = {}                  # id -> QuestState
var completed_ids: Array[String] = []
## Quests turned in whose support gem choice hasn't been picked yet. Saved, so quitting before
## picking doesn't lose the reward; RewardChoice opens whenever this isn't empty.
var pending_choices: Array[String] = []
## Quest items and places the player has recovered: keys that open sealed portals, ward
## beacons. Kept apart from quest progress, so one found before its quest was taken still
## counts (RecoverObjective credits it). Saved. Names and hints: QuestItems.
var recovered: Array[String] = []
## Best grade on each rank exam (ExamSpec): rank id -> 0 PASS, 1 MERIT, 2 DISTINCTION. Saved.
## Retaking an exam only ever raises it.
var exam_grades: Dictionary = {}
## Quest ids that were renamed: old saves load them under the new id.
## exam_engineer was Act I's advanced exam before it became the Architect exam. Drop that entry
## before an Act IV quest takes the id exam_engineer again.
const RENAMED := {"exam_engineer": "exam_architect"}

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
		# exported builds list .tres files with a .remap suffix, so handle both
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


# ---------- QUERIES (for NPCs and UI) ----------
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
	return true


func has_recovered(id: String) -> bool:
	return recovered.has(id)


## Records a quest item or beacon (once) and tells the quests about it ("recover" events).
func recover(id: String) -> void:
	if id == "" or recovered.has(id):
		return
	recovered.append(id)
	item_recovered.emit(id)
	GameEvents.report("recover", id)


## Records an exam result. Returns true if it's a new best.
func record_exam(rank: String, grade: int) -> bool:
	if exam_grades.has(rank) and int(exam_grades[rank]) >= grade:
		return false
	exam_grades[rank] = grade
	return true


## The best grade on that exam, or -1 if it hasn't been passed.
func exam_grade(rank: String) -> int:
	return int(exam_grades.get(rank, -1))


# ---------- STARTING ----------
func start_by_id(id: String) -> bool:
	return start(get_def(id))


func start(q: QuestDefinition) -> bool:
	if not can_start(q):
		return false
	var s := QuestState.new(q)

	# Credit anything the player has already done (e.g. the item is already equipped).
	_credit_already_met(s)

	active[q.id] = s
	quest_started.emit(s)
	_check_ready(s)
	return true


# ---------- PROGRESS ----------
func _on_event(kind: String, target: String, amount: int) -> void:
	# copy the values: completing a quest can start the next one while we loop
	for s: QuestState in active.values().duplicate():
		if s.status != QuestState.Status.ACTIVE:
			continue
		if s.handle_event(kind, target, amount):
			_credit_already_met(s)
			quest_updated.emit(s)
			_check_ready(s)


## Marks objectives the player has already done (already_met()) as complete. In an ordered
## quest this only looks at the current step and stops at the first one still to do, so a step
## done early (the weapon equipped while the quest was still on "move around") is credited
## as soon as the quest reaches it, instead of waiting for an event that already happened.
## Returns true if anything was credited.
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


# ---------- TURN IN ----------
## Called by a quest-giver NPC. Returns "" on success, otherwise a message for the player.
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
	GameEvents.report("quest_done", id)     # lets other quests depend on this one finishing
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


# ---------- SAVE / LOAD ----------
func to_dict() -> Dictionary:
	var list := []
	for s: QuestState in active.values():
		list.append(s.to_dict())
	return {"active": list, "completed": completed_ids, "pending_choices": pending_choices,
		"recovered": recovered.duplicate(), "exam_grades": exam_grades.duplicate()}


# ---------- TUTORIAL GUARD ----------
## The tutorial needs the class's starting skill gem, so until these quests are turned in the
## player can't discard or sell their last copy of it.
const TUTORIAL_QUESTS: Array[String] = ["tut_basics", "q00_proximity_trigger"]


func tutorial_finished() -> bool:
	for id in TUTORIAL_QUESTS:
		if catalog.has(id) and not is_completed(id):
			return false
	return true


## "" when `item` may be thrown away (discarded or sold), otherwise a message for the player.
func keep_reason(item: ItemInstance) -> String:
	if item == null or tutorial_finished():
		return ""
	var cd = _player.get("class_data")
	if cd == null or cd.starting_skill_gem == null or item.definition != cd.starting_skill_gem:
		return ""
	if _copies_owned(item.definition) > 1:
		return ""                                # another copy stays behind for the tutorial
	return "NEEDED FOR THE TUTORIAL: FINISH IT FIRST"


## Copies of an item in the backpack and in skill sockets.
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


# ---------- SUPPORT GEM CHOICE ----------
## The skill gem the player's class starts with (its starting_skill_gem), or, if the class has
## none, the skill in the first socket. null if neither exists.
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


## Support gem items that fit the starting skill: same rule as socketing (a support fits when one
## of its allowed tags is on the skill). Sorted by name.
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
			continue                     # above the player's rank (For Loop before ARCHITECT)
		for t in item.support_gem.allowed_tags:
			if t in skill.tags:
				out.append(item)
				break
	out.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool:
		return a.support_gem.display_name < b.support_gem.display_name)
	return out


## Gives the picked support gem for the oldest waiting choice. Returns "" on success, otherwise
## a message for the player.
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


## Call with GameEvents.muted = true around the load, as in Player._ready().
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
	for id in d.get("completed", []):
		completed_ids.append(RENAMED.get(str(id), str(id)))
	for id in d.get("pending_choices", []):
		pending_choices.append(str(id))
	for e in d.get("active", []):
		var q := get_def(RENAMED.get(str(e.get("id", "")), str(e.get("id", ""))))
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
			# The quest's objectives changed since this save: progress can't be matched up
			# by position, so it starts over (crediting anything already done).
			push_warning("QuestManager: %s changed since this save, its progress was reset" % q.id)
			for i in q.objectives.size():
				if q.objectives[i].already_met(_player):
					s.progress[i] = q.objectives[i].required
			_check_ready(s)
		active[q.id] = s
		quest_updated.emit(s)
