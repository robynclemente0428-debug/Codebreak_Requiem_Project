@tool
class_name ConnectivityChecker
extends RefCounted

static func validate(grid: GridData, a: Vector2i, b: Vector2i) -> bool:
	var visited: Dictionary = {}
	var queue: Array = [a]
	visited[a] = true
	
	while queue.size() > 0:
		var current = queue.pop_front()
		if current == b:
			return true
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next = current + dir
			if grid.in_bounds(next) and not visited.has(next) and grid.get_tile(next) != GridData.Tile.WALL:
				visited[next] = true
				queue.append(next)
	
	return false

static func validate_all(grid: GridData, start: Vector2i, targets: Array) -> bool:
	var visited := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var nxt: Vector2i = cur + dir
			if grid.in_bounds(nxt) and not visited.has(nxt) and grid.get_tile(nxt) != GridData.Tile.WALL:
				visited[nxt] = true
				queue.append(nxt)
	for t in targets:
		if not visited.has(t):
			return false
	return true
