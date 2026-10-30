extends Node
## Autoload: ItemDatabase
const ITEM_DIR := "res://data/items/"   # point at the folder(s) holding your item .tres files

var _items: Dictionary = {}

func _ready() -> void:
	_scan(ITEM_DIR)

func _scan(dir_path: String) -> void:
	for d in DirAccess.get_directories_at(dir_path):
		_scan(dir_path.path_join(d))
	for f in DirAccess.get_files_at(dir_path):
		var clean := f.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			var res := load(dir_path.path_join(clean))
			if res is ItemDefinition:
				_items[res.id] = res

func get_item(id: String) -> ItemDefinition:
	return _items.get(id)


## Every item definition that was found, in no particular order.
func all_items() -> Array:
	return _items.values()
