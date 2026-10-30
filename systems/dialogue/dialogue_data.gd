class_name DialogueData
extends Resource

@export_multiline var source: String = ""

var _parsed: Dictionary = {}
var _is_parsed := false

func get_nodes() -> Dictionary:
	if not _is_parsed:
		_parsed = DialogueParser.parse(source)
		_is_parsed = true
	return _parsed
