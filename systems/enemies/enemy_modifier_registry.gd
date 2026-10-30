extends Node

var all_modifiers: Array[EnemyModifierDefinition] = []

func _ready() -> void:
	var dir = DirAccess.open("res://data/enemy_modifiers/")
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			all_modifiers.append(load("res://data/enemy_modifiers/" + file_name))

func roll_modifiers(enemy_def: EnemyDefinition, rarity: String) -> Array[EnemyModifierDefinition]:
	var count: int = {"normal": 0, "magic": 1, "rare": randi_range(2,3), "champion": randi_range(4,5)}[rarity]	
	var pool = all_modifiers.filter(func(m):
		return _tags_overlap(m.tags, enemy_def.allowed_modifier_tags)
	)
	var chosen: Array[EnemyModifierDefinition] = []
	for i in count:
		if pool.is_empty():
			break
		var pick = _weighted_pick(pool)
		chosen.append(pick)
		pool.erase(pick) # no duplicate mods on one enemy
	return chosen

func _tags_overlap(a: Array, b: Array) -> bool:
	for t in a:
		if t in b:
			return true
	return false

func _weighted_pick(pool: Array[EnemyModifierDefinition]) -> EnemyModifierDefinition:
	var total := 0
	for m in pool: total += m.weight
	var roll := randi_range(0, total - 1)
	for m in pool:
		roll -= m.weight
		if roll < 0:
			return m
	return pool[0]
	
