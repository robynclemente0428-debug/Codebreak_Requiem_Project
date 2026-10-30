class_name ItemCatalog
extends RefCounted
## Finds every ItemDefinition .tres under ITEM_ROOT, once, and hands out the ones that fit a
## dungeon level. No autoload needed: the first call scans, later calls reuse the result.
##
##     var pool := ItemCatalog.for_level(dungeon_level, 20)           # no gems
##     var pool := ItemCatalog.for_level(5, 20, true)                 # gems too
##     var pool := ItemCatalog.for_level(5, 20, false, ["res://data/items/weapons/"])

## Folder that holds your item definitions. Sub-folders are searched too.
const ITEM_ROOT := "res://data/items/"

static var _all: Array[ItemDefinition] = []
static var _loaded := false


## Every item definition found, lowest item level first.
static func all() -> Array[ItemDefinition]:
	if not _loaded:
		reload()
	return _all


## Scans the folders again (use it from a tool script if you add items while the game runs).
static func reload() -> void:
	_all.clear()
	_scan(ITEM_ROOT, _all)
	_all.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool:
		return a.item_level < b.item_level)
	_loaded = true
	print("[ItemCatalog] %d item definitions found under %s" % [_all.size(), ITEM_ROOT])


## Items that can drop at `level`: item_level <= level and item_level >= level - window.
## include_gems:  skill and support gems are skipped unless this is true.
## folders:       only items whose file sits under one of these paths. Empty = everywhere.
static func for_level(level: int, window: int = 20, include_gems: bool = false,
		folders: PackedStringArray = PackedStringArray()) -> Array[ItemDefinition]:
	var out: Array[ItemDefinition] = []
	for def in all():
		if def.item_level > level or def.item_level < level - window:
			continue
		if not include_gems and (def.skill_gem != null or def.support_gem != null):
			continue
		if not folders.is_empty() and not _in_folders(def, folders):
			continue
		out.append(def)
	return out


static func _in_folders(def: ItemDefinition, folders: PackedStringArray) -> bool:
	for f in folders:
		if def.resource_path.begins_with(f):
			return true
	return false


static func _scan(path: String, out: Array[ItemDefinition]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("ItemCatalog: cannot open %s" % path)
		return
	for sub in dir.get_directories():
		_scan(path.path_join(sub), out)
	for file in dir.get_files():
		# In an exported game the files are listed as "name.tres.remap"
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var res := load(path.path_join(name))
		if res is ItemDefinition:
			out.append(res)
