extends Node

const STRIP_TOP := 96.0
const GAP := 10.0
const HEADLINE_MIN := 230.0
const FEED_MIN := 215.0
const BASE_HEIGHT := 1080.0

const OPACITY := 0.85

const LOW := 0
const NORMAL := 10
const HIGH := 20
const URGENT := 30

var _strip: Array[Dictionary] = []
var _strip_bottom := -1.0
var _strip_aside := false
var _current: Dictionary = {}
var _queue: Array[Dictionary] = []
var _clock := 0.0
var _free_at := 0.0
const HANDOFF := 0.15
const PLACE_AFTER := 101
const FEED_AFTER := PLACE_AFTER + 1
var _tail_bottom := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = PLACE_AFTER - 1


func _process(delta: float) -> void:
	if not get_tree().paused:
		_clock += delta
		if not _current.is_empty() and (_clock >= _current["until"] or not _alive(_current)):
			_release()
		_queue = _queue.filter(func(h: Dictionary) -> bool:
			return _alive(h) and (h["wait"] < 0.0 or _clock - h["asked"] <= h["wait"]))
		if _current.is_empty() and not _queue.is_empty() and _clock >= _free_at:
			_start(_queue.pop_front())
	_layout_strip(delta)


func screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func fit(px: float) -> float:
	return roundf(px * minf(1.0, screen_size().y / BASE_HEIGHT))


func column_bottom() -> float:
	return screen_size().y - BOTTOM_RESERVE


const BOTTOM_RESERVE := 270.0


func _gap() -> float:
	return maxf(4.0, fit(GAP))


func add_to_strip(node: Control, order: int) -> void:
	for s in _strip:
		if s["node"] == node:
			s["order"] = order
			return
	_strip.append({"node": node, "order": order})
	_strip.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])


func strip_bottom() -> float:
	return _strip_bottom


func _layout_strip(delta: float) -> void:
	_strip = _strip.filter(func(s: Dictionary) -> bool: return is_instance_valid(s["node"]))
	var gap := _gap()
	var y := fit(STRIP_TOP)
	var any := false
	for s in _strip:
		var node: Control = s["node"]
		if not node.is_inside_tree() or not _shown(node):
			continue
		if not is_equal_approx(node.global_position.y, y):
			node.global_position.y = y
		y += maxf(node.size.y, node.get_combined_minimum_size().y) + gap
		any = true
	var bottom := y - gap if any else -1.0
	_strip_aside = any and not _current.is_empty() \
			and maxf(fit(HEADLINE_MIN), bottom + gap * 2.0) + float(_current["height"]) > column_bottom()
	_strip_bottom = -1.0 if _strip_aside else bottom
	for s in _strip:
		var node: Control = s["node"]
		if _strip_aside:
			node.modulate.a = 0.0
		elif node.modulate.a < 1.0:
			node.modulate.a = minf(1.0, node.modulate.a + delta * 5.0)


static func _shown(node: CanvasItem) -> bool:
	if not node.is_visible_in_tree():
		return false
	var p := node.get_parent()
	while p != null:
		if p is CanvasLayer and not (p as CanvasLayer).visible:
			return false
		p = p.get_parent()
	return true


func headline(key: StringName, priority: int, seconds: float, show: Callable,
		hide := Callable(), wait := 8.0, keep := false) -> void:
	var h := {"key": key, "priority": priority, "seconds": seconds, "show": show, "hide": hide,
			"wait": wait, "keep": keep, "asked": _clock, "until": 0.0, "height": DEFAULT_HEIGHT}
	if not _current.is_empty() and _current["key"] == key:
		_start(h)
		return
	_queue = _queue.filter(func(q: Dictionary) -> bool: return q["key"] != key)
	if _current.is_empty() and _clock >= _free_at:
		_start(h)
		return
	if not _current.is_empty() and priority > int(_current["priority"]):
		_interrupt()
		_start(h)
		return
	var i := 0
	while i < _queue.size() and int(_queue[i]["priority"]) >= priority:
		i += 1
	_queue.insert(i, h)


const DEFAULT_HEIGHT := 60.0


func headline_done(key: StringName) -> void:
	if not _current.is_empty() and _current["key"] == key:
		_release()
	else:
		_queue = _queue.filter(func(q: Dictionary) -> bool: return q["key"] != key)


func set_headline_height(key: StringName, height: float) -> void:
	if not _current.is_empty() and _current["key"] == key \
			and not is_equal_approx(float(_current["height"]), height):
		_current["height"] = height
		_layout_strip(0.0)


func is_showing(key: StringName) -> bool:
	return not _current.is_empty() and _current["key"] == key


func headline_top() -> float:
	var y := fit(HEADLINE_MIN)
	return maxf(y, _strip_bottom + _gap() * 2.0) if _strip_bottom >= 0.0 else y


func headline_bottom() -> float:
	return -1.0 if _current.is_empty() else headline_top() + float(_current["height"])


func _release() -> void:
	_tail_bottom = headline_bottom()
	_current = {}
	_free_at = _clock + HANDOFF


func _start(h: Dictionary) -> void:
	_current = h
	h["until"] = _clock + float(h["seconds"])
	var show: Callable = h["show"]
	if show.is_valid():
		var got = show.call()
		if (got is float or got is int) and float(got) > 0.0:
			h["height"] = float(got)
	_layout_strip(0.0)


func _interrupt() -> void:
	var was := _current
	_current = {}
	var hide: Callable = was["hide"]
	if hide.is_valid():
		hide.call()
	if was["keep"] and _alive(was):
		was["asked"] = _clock
		_queue.push_front(was)


static func _alive(h: Dictionary) -> bool:
	var show: Callable = h["show"]
	return show.is_valid() and (show.get_object() == null or is_instance_valid(show.get_object()))


static func see_through(node: Node) -> void:
	var items: Array = node.find_children("*", "CanvasItem", true, false)
	if node is CanvasItem:
		items.append(node)
	for item in items:
		(item as CanvasItem).self_modulate.a = OPACITY


func feed_top() -> float:
	var gap := _gap()
	var y := fit(FEED_MIN)
	if _strip_bottom >= 0.0:
		y = maxf(y, _strip_bottom + gap * 2.0)
	var hb := headline_bottom()
	if hb < 0.0 and _clock < _free_at:
		hb = _tail_bottom
	if hb >= 0.0:
		y = maxf(y, hb + gap * 1.5)
	return y


func feed_room() -> float:
	return maxf(0.0, column_bottom() - feed_top())
