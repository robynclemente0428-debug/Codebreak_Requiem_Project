@tool
extends EditorScript
## One-time tool. Open this in the Script editor and choose File > Run (Ctrl+Shift+X).
## Re-running overwrites the .tres files, so change the table below rather than
## hand-editing stats in the Inspector. (Icons set by hand will be reset.)

const OUT_DIR := 'res://data/classes/'

# Each class gets 40 attribute points to start with (placeholder balance).
const CLASSES := [
	{'id': 'raider', 'name': 'Raider', 'str': 24, 'dex': 8, 'int': 8,
		'desc': 'A brute who wins by standing still and hitting harder.'},
	{'id': 'rogue', 'name': 'Rogue', 'str': 8, 'dex': 24, 'int': 8,
		'desc': 'Fast and precise, always one step ahead of the fight.'},
	{'id': 'enchanter', 'name': 'Enchanter', 'str': 8, 'dex': 8, 'int': 24,
		'desc': 'Bends raw power into skills that hit far above their weight.'},
	{'id': 'gladiator', 'name': 'Gladiator', 'str': 16, 'dex': 16, 'int': 8,
		'desc': 'Strong and quick, built for the arena.'},
	{'id': 'paladin', 'name': 'Paladin', 'str': 16, 'dex': 8, 'int': 16,
		'desc': 'Armoured and focused, part warrior and part spellcaster.'},
	{'id': 'assassin', 'name': 'Assassin', 'str': 8, 'dex': 16, 'int': 16,
		'desc': 'Cunning and agile, striking with skill instead of force.'},
]

# Model for each class: a .glb or .tscn path. Leave '' until you have one.
const MODELS := {
	'raider': '',
	'rogue': 'res://scenes/player/models/rogue_model.tscn',
	'enchanter': '',
	'gladiator': '',
	'paladin': '',
	'assassin': '',
}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var order := 0
	for row in CLASSES:
		var c := ClassData.new()
		c.id = row['id']
		c.display_name = row['name']
		c.description = row['desc']
		c.strength = row['str']
		c.dexterity = row['dex']
		c.intelligence = row['int']
		c.starting_skill_id = 'strike'
		c.sort_order = order
		order += 1

		var model_path: String = MODELS.get(row['id'], '')
		if model_path != '' and ResourceLoader.exists(model_path):
			c.model_scene = load(model_path)

		var path: String = OUT_DIR + row['id'] + '.tres'
		var err := ResourceSaver.save(c, path)
		if err != OK:
			push_error('Could not save %s: %s' % [path, error_string(err)])
		else:
			print('Saved ', path)

	EditorInterface.get_resource_filesystem().scan()
