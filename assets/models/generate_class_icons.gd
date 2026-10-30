@tool
extends EditorScript
## Open this script and press File > Run (Ctrl+Shift+X).
## Paints one icon per class into res://assets/icons/classes/<id>.png.
## It never creates .tres files. If APPLY_TAGLINES is true it also sets the
## tagline on your EXISTING ClassData files (matched by id or display name).

const ICON_DIR := "res://assets/icons/classes/"
const CLASS_DIR := "res://data/classes/"
const APPLY_TAGLINES := true

const TAGLINES := {
	&"raider": "Crushes defenses head-on",
	&"rogue": "Fast hands, faster exits",
	&"enchanter": "Rewrites reality with code",
	&"gladiator": "Armored, agile, undefeated",
	&"paladin": "Firewall made flesh",
	&"assassin": "Breaches systems from range",
}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ICON_DIR)

	for id in TAGLINES:
		var path := ICON_DIR + String(id) + ".png"
		var err := ClassIconPainter.paint(id).save_png(path)
		print("%s  %s" % ["saved" if err == OK else "FAILED (%d)" % err, path])

	if APPLY_TAGLINES:
		_apply_taglines()

	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	print("Done.")


func _apply_taglines() -> void:
	var matched := {}
	for file in DirAccess.get_files_at(CLASS_DIR):
		if not file.ends_with(".tres"):
			continue
		var path := CLASS_DIR + file
		var data := load(path) as ClassData
		if data == null:
			continue
		var key := StringName(String(data.id).to_lower())
		if not TAGLINES.has(key):
			key = StringName(data.display_name.to_lower())
		if not TAGLINES.has(key):
			continue
		data.tagline = TAGLINES[key]
		if ResourceSaver.save(data, path) == OK:
			matched[key] = true
			print("tagline set: %s" % path)
	for id in TAGLINES:
		if not matched.has(id):
			print("no existing .tres matched '%s' (tagline not applied)" % id)
