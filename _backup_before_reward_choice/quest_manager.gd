class_name QuestManager
extends Node
## Lives on the Player as a child node. Tracks active and completed quests,
## listens to GameEvents, and hands out rewards.

signal quest_started(state: QuestState)
signal quest_updated(state: QuestState)
signal quest_ready(state: QuestState)        # all objectives done, waiting for turn-in
signal quest_completed(state: QuestState)

## Every quest in the game is found in this folder, so you never fill an array by hand.
@export_dir var quest_folder: String = "res://data/quests/"

var catalog: Dictionary = {}                 # id -> QuestDefinition
var active: Dictionary = {}                  # id -> QuestState
var completed_ids: Array[String] = []

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
	if not q.reward_items.is_empty():
		if inv == null or inv.capacity - inv.items.size() < q.reward_items.size():
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
	return {"active": list, "completed": completed_ids}


## Call with GameEvents.muted = true around the load, as in Player._ready().
func from_dict(d: Dictionary) -> void:
	active.clear()
	completed_ids.clear()
	for id in d.get("completed", []):
		completed_ids.append(str(id))
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
			# The quest's objectives changed since this save: progress can't be matched up
			# by position, so it starts over (crediting anything already done).
			push_warning("QuestManager: %s changed since this save, its progress was reset" % q.id)
			for i in q.objectives.size():
				if q.objectives[i].already_met(_player):
					s.progress[i] = q.objectives[i].required
			_check_ready(s)
		active[q.id] = s
		quest_updated.emit(s)
