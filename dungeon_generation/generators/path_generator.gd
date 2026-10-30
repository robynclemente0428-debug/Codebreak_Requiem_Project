@tool
class_name PathGenerator
extends RefCounted

static func generate(grid: GridData, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> Array:
	var path: Array = [a]
	var current = a
	var max_steps = grid.width * grid.height
	
	while current != b and max_steps > 0:
		max_steps -= 1
		var dir = _choose_direction(current, b, rng)
		var next = current + dir
		if grid.in_safe_bounds(next):
			current = next
		path.append(current)
		
	return path

static func _choose_direction(current: Vector2i, target: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var options = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var weighted: Array = []
	
	for dir in options:
		var next = current + dir
		var dist_now = current.distance_to(target)
		var dist_next = next.distance_to(target)
		var weight = 3 if dist_next < dist_now else 1
		for i in weight:
			weighted.append(dir)
	
	return weighted[rng.randi() % weighted.size()]
