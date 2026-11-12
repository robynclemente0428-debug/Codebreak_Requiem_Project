class_name QuestRoutes
extends RefCounted
## Where an active quest's next step happens, and which way out of this area leads there: the
## minimap rings that portal (or the convoy's route terminal) in quest gold.
##
## The areas are the scenes under AREAS. Each is read once as text: its portals' target_area /
## routed_area make the map between them (edges), and what it holds says what happens there:
##   kill, blobs_freed   the enemy's file is in it (a boss placed in the scene)
##   kill_at             "enemy@area": the area named
##   enter_area          the area named
##   talk                its npc_id is in it, or the NPC's own scene is
##   recover             the item's id is in it (a crate's drops_key, a pickup's key_id...)
##   exam_passed         Sudo (talk)
## A quest ready to turn in leads to its giver (metadata/giver).
## From the area the player is in, a breadth-first walk over the portals finds the nearest place
## with a step to do; the portals that start that walk are the ones to ring. A step in this very
## area isn't routed: its own markers (enemies, NPCs, keys) already show it.
## An area with a route terminal (the convoy, the Quarantine Yard...) also leads to every stop of
## its act: a way that starts there gives TERMINAL as its first step, and the terminal is ringed.
## Text scenes only: in an export that turned them binary, nothing is found and nothing is ringed.

const AREAS := ["res://scenes/map"]
const NPCS := "res://scenes/npc"
const TERMINAL_SCENE := "route_terminal.tscn"
## The first step of a way that starts at this area's route terminal (first_hops).
const TERMINAL := "@terminal"
static var _texts := {}                         # scene path -> its text
static var _edges := {}                         # scene path -> [scene paths its portals lead to]
static var _terminal_edges := {}                # scene path -> [its act's stops, by route terminal]
static var _by_name := {}                       # file base name -> scene path
static var _npc_scenes := {}                    # npc_id -> [NPC scene paths that hold it]
static var _found := {}                         # "kind|target" -> [scene paths]
static var _link_re: RegEx


## A scene path either way it's written (res:// or uid://), as res://.
static func normal(path: String) -> String:
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return path


## The areas the player should head for next, for every active quest: {scene path: quest title}.
## Steps in `here` are left out.
static func goals(qm: QuestManager, here: String) -> Dictionary:
	_index()
	var out := {}
	if qm == null:
		return out
	for s in qm.active.values():
		var st := s as QuestState
		var places: Array = []
		if st.status == QuestState.Status.READY_TO_TURN_IN:
			places = _scenes_for("talk", _npc_of(str(st.def.get_meta(&"giver", ""))))
			if here in places:
				places = []                            # the giver is right here (Sudo is in every hub)
		elif st.status == QuestState.Status.ACTIVE:
			for i in st.def.objectives.size():
				if st.objective_done(i):
					continue
				var o: Objective = st.def.objectives[i]
				var step := _scenes_for(o.kind, o.target)
				if not here in step:                   # a step that can be done here isn't routed away
					places.append_array(step)
				if st.def.ordered:
					break                              # later steps don't count yet
		for p in places:
			if p != here and not out.has(p):
				out[p] = st.def.title
	return out


## The first steps out of `here` toward the nearest of `goals`: {next scene path: quest title}.
## Empty when no portal path leads to any of them.
static func first_hops(here: String, goals_: Dictionary) -> Dictionary:
	_index()
	var out := {}
	if goals_.is_empty() or not _edges.has(here):
		return out
	var first := {here: ""}                         # scene -> the step out of `here` that reached it
	var frontier: Array = [here]
	while not frontier.is_empty() and out.is_empty():
		var next: Array = []
		for at in frontier:
			for pair in [[_edges.get(at, []), false], [_terminal_edges.get(at, []), true]]:
				for to in pair[0]:
					if first.has(to):
						continue
					if at == here:
						first[to] = TERMINAL if pair[1] else to
					else:
						first[to] = first[at]
					next.append(to)
					if goals_.has(to):
						out[first[to]] = goals_[to]    # every goal at the nearest distance counts
		frontier = next
	return out


## The scenes where an objective of `kind` with `target` happens.
static func _scenes_for(kind: String, target: String) -> Array:
	_index()
	if target == "":
		return []
	if kind == "exam_passed":
		return _scenes_for("talk", "sudo")
	var key := "%s|%s" % [kind, target]
	if _found.has(key):
		return _found[key]
	var out: Array = []
	match kind:
		"enter_area":
			if _by_name.has(target):
				out.append(_by_name[target])
		"kill_at":
			var parts := target.split("@")
			if parts.size() == 2 and _by_name.has(parts[1]):
				out.append(_by_name[parts[1]])
		"kill", "blobs_freed":
			out = _holding(["/enemies/%s.tres\"" % target])
		"talk":
			var needles: Array = ["npc_id = \"%s\"" % target]
			for npc_scene in _npc_scenes.get(target, []):
				needles.append("\"%s\"" % npc_scene)
			out = _holding(needles)
		"recover":
			out = _holding(["\"%s\"" % target])
	_found[key] = out
	return out


static func _holding(needles: Array) -> Array:
	var out: Array = []
	for path in _texts:
		var text: String = _texts[path]
		for n in needles:
			if text.contains(str(n)):
				out.append(path)
				break
	return out


## "The Last Log" -> "last_log", "Sudo" -> "sudo": a quest giver's npc_id.
static func _npc_of(giver: String) -> String:
	var id := giver.strip_edges().to_lower().replace(" ", "_")
	return id.trim_prefix("the_")


# ---------- THE INDEX ----------
static func _index() -> void:
	if not _texts.is_empty():
		return
	_link_re = RegEx.new()
	_link_re.compile("(?:target_area|routed_area) = \"([^\"]+)\"")
	for root in AREAS:
		_read_dir(root, _texts)
	for path in _texts:
		_by_name[str(path).get_file().get_basename()] = path
		var links: Array = []
		for m in _link_re.search_all(_texts[path]):
			var to := normal(m.get_string(1))
			if to != "" and to != path and not to in links:
				links.append(to)
		_edges[path] = links
		if str(_texts[path]).contains(TERMINAL_SCENE):
			var act := Waypoints.act_of_scene(path)
			var stops: Array = []
			if act != null:
				for w in act.waypoints:
					var to := normal(w.scene)
					if to != "" and to != path:
						stops.append(to)
			_terminal_edges[path] = stops
	var npcs := {}
	_read_dir(NPCS, npcs)
	var id_re := RegEx.new()
	id_re.compile("npc_id = \"([a-z_]+)\"")
	for path in npcs:
		for m in id_re.search_all(npcs[path]):
			var list: Array = _npc_scenes.get(m.get_string(1), [])
			if not path in list:
				list.append(path)
			_npc_scenes[m.get_string(1)] = list


static func _read_dir(dir_path: String, into: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_read_dir(dir_path.path_join(sub), into)
	for f in dir.get_files():
		if f.get_extension() != "tscn":
			continue
		var path := dir_path.path_join(f)
		var text := FileAccess.get_file_as_string(path)
		if text != "":
			into[path] = text
