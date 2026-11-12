class_name NewBlocks
extends RefCounted
## NEW badges in the SCRIPTING editor's snippets list: a block a rank just unlocked (Ranks.LOCKED_BLOCKS:
## loops, the Registry, if, call, sorting...) shows NEW until the player has hovered it long enough
## to read its hint, or clicked or dragged it (SkillScriptTab._snippet). Each snippet goes away on
## its own: seeing "for range()" doesn't clear "while".
##
## Kept in the character's save like the NEW LOCK cards (LockTags), in every party member's data:
##   SEEN_KEY    snippet ids already seen, "<block>|<snippet text>" ("loop|for range()")
##   KNOWN_KEY   blocks known from before this feature: the first time a save is looked at, every
##               block unlocked by a rank BELOW the one held is marked known, so an old save only
##               shows NEW for its current rank's blocks, and a new character for every rank it earns.
## Blocks lent by Sudo's sandbox (Ranks.lent) show NEW there too: that is where they are met.

const SEEN_KEY := "blocks_seen"
const KNOWN_KEY := "blocks_known"


## The Ranks.LOCKED_BLOCKS id a palette snippet's drag data stands for, "" if it is never locked.
static func block_of(data: Dictionary) -> String:
	var id := ""
	match str(data.get("kind", "")):
		"loop", "break":
			id = "loop"
		"condition":
			id = "cond:" + str(data.get("type", ""))
		"set_write", "member", "size", "compare_op":
			id = "knob:" + String(ScriptRegisters.WRITE_KNOB)
		"branch":
			id = "if"
		"call":
			id = "call"
		"sort":
			id = "sort"
		"position":
			id = "cond:registry_pos"
		"effect":
			id = "knob:" + str(data.get("knob", ""))
	return id if Ranks.LOCKED_BLOCKS.has(id) else ""


static func item_id(block: String, text: String) -> String:
	return "%s|%s" % [block, text]


## True when this snippet should wear a NEW badge.
static func is_new(tree: SceneTree, block: String, text: String) -> bool:
	if block == "":
		return false
	var data := _data(tree)
	if data.is_empty():
		return false
	if block in (data.get(KNOWN_KEY, []) as Array):
		return false
	return not item_id(block, text) in (data.get(SEEN_KEY, []) as Array)


## The player has seen it: into every party member's save (kept with the next save).
static func mark_seen(tree: SceneTree, block: String, text: String) -> void:
	var save = _save_manager(tree)        # untyped: SaveManager is an autoload by path
	if save == null or block == "":
		return
	var id := item_id(block, text)
	for slot in save.party:
		var d: Dictionary = save.get_data(slot)
		var seen: Array = d.get(SEEN_KEY, [])
		if not id in seen:
			seen.append(id)
		d[SEEN_KEY] = seen


## The playing character's save data, with KNOWN_KEY filled in the first time ({} without a save).
static func _data(tree: SceneTree) -> Dictionary:
	var save = _save_manager(tree)        # untyped: SaveManager is an autoload by path
	if save == null or save.party.is_empty():
		return {}
	var d: Dictionary = save.get_data(save.party[0])
	if not d.has(KNOWN_KEY):
		var rank := Ranks.of_player(tree)
		var known: Array = []
		for block in Ranks.LOCKED_BLOCKS:
			var at := _rank_index(Ranks.unlocks(block))
			if at >= 0 and at < rank:
				known.append(block)
		for slot in save.party:
			(save.get_data(slot) as Dictionary)[KNOWN_KEY] = known.duplicate()
	return d


static func _rank_index(rank_name: String) -> int:
	for i in Ranks.LADDER.size():
		if Ranks.LADDER[i]["name"] == rank_name:
			return i
	return -1


static func _save_manager(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("SaveManager") if tree != null else null
