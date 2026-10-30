class_name ClassRegistry
extends RefCounted
## Looks up ClassData by id. Scans res://data/classes/ once and caches the result.

const CLASS_DIR := 'res://data/classes/'

static var _by_id: Dictionary = {}
static var _loaded := false


static func find(class_id: String) -> ClassData:
	_ensure_loaded()
	return _by_id.get(class_id)


static func all() -> Array[ClassData]:
	_ensure_loaded()
	var out: Array[ClassData] = []
	for c in _by_id.values():
		out.append(c)
	out.sort_custom(func(a: ClassData, b: ClassData): return a.sort_order < b.sort_order)
	return out


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for file_name in DirAccess.get_files_at(CLASS_DIR):
		# Exported builds list resources as '.tres.remap'
		var clean := file_name.trim_suffix('.remap')
		if not clean.ends_with('.tres'):
			continue
		var res := load(CLASS_DIR + clean)
		if res is ClassData:
			_by_id[String(res.id)] = res
