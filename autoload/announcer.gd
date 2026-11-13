extends Node
## Decides where and when on-screen messages appear, so they never land on each other. It draws
## nothing itself: each message keeps its own look and animation, and asks here for its place.
## The top centre of the screen is one column, laid out every frame from the top down:
##
##   STRIP     messages that stay up while they apply (the tutorial banner, the dock defense
##             panel), stacked in `order`, each under the one before. add_to_strip().
##   HEADLINE  one big moment at a time (AREA CLEARED, an exam wave, a
##             NEW LOCK card), under the strip. headline() queues it by priority: a more
##             important one takes the slot at once, otherwise it waits its turn.
##   FEED      the quest tracker's short lines (QUEST READY, a beacon online, convoy damage),
##             stacked under the headline while one is up, else under the strip. feed_top().
##
## The lock banner (bottom centre) and the HUD's corners are outside this column: it ends at
## column_bottom(). The UI size setting can leave as little as 960 x 540 to lay out in, so the
## column fits itself to what there is:
##   - its offsets and gaps shrink with the screen's height (fit())
##   - a feed line that doesn't fit waits, its clock stopped, until there's room
##   - a headline that doesn't fit under the strip takes its place: the strip steps aside
##     (hidden) until the headline is over

## Px from the top of the screen where the strip starts (on a 1080 px tall screen).
const STRIP_TOP := 96.0
## Space between strip items, and between the strip, the headline and the feed (at 1080).
const GAP := 10.0
## The headline never sits higher than this (at 1080; it was centred at 30% of the screen).
const HEADLINE_MIN := 230.0
## The feed never sits higher than this (at 1080).
const FEED_MIN := 215.0
## The screen height those are for (Settings' BASE_SIZE).
const BASE_HEIGHT := 1080.0

## How solid the headlines and the feed are (1 = fully): the game shows through them a little.
## The strip (tutorial banner, dock panel) stays solid: it's read, not glanced at.
const OPACITY := 0.85

## Headline priorities. Higher replaces lower at once; equal waits its turn.
const LOW := 0
const NORMAL := 10
const HIGH := 20
const URGENT := 30

var _strip: Array[Dictionary] = []       # {"node": Control, "order": int}
var _strip_bottom := -1.0                # last frame's strip bottom (-1 = nothing in it)
var _strip_aside := false                # a headline has the strip's place (it's hidden)
var _current: Dictionary = {}            # the headline on screen ({} = none)
var _queue: Array[Dictionary] = []       # headlines waiting, most important first
var _clock := 0.0                        # seconds the game has run unpaused
var _free_at := 0.0                      # the slot takes the next headline from this time on
## Seconds between one headline ending and the next starting, so the last frames of a fade-out
## never sit under the next one.
const HANDOFF := 0.15
## process_priority for the messages that place themselves from strip_bottom(), headline_top()
## or feed_top(): after the layout here, so they never use last frame's numbers.
const PLACE_AFTER := 101
## process_priority for the feed: after the headlines, which can report a new height
## (set_headline_height) while they place themselves.
const FEED_AFTER := PLACE_AFTER + 1
var _tail_bottom := -1.0                 # the last headline's bottom, kept through HANDOFF


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After the messages have sized themselves this frame, before those that place themselves
	process_priority = PLACE_AFTER - 1


func _process(delta: float) -> void:
	if not get_tree().paused:            # headlines hold their place over a pause
		_clock += delta
		if not _current.is_empty() and (_clock >= _current["until"] or not _alive(_current)):
			_release()
		_queue = _queue.filter(func(h: Dictionary) -> bool:
			return _alive(h) and (h["wait"] < 0.0 or _clock - h["asked"] <= h["wait"]))
		if _current.is_empty() and not _queue.is_empty() and _clock >= _free_at:
			_start(_queue.pop_front())
	_layout_strip(delta)


# ---------- FITTING THE SCREEN ----------
## The screen's size to lay out in (the UI size setting shrinks it: 1280 x 720 at 1.5).
func screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size


## `px` (a distance meant for a 1080 px tall screen), for this screen: smaller when it's shorter.
func fit(px: float) -> float:
	return roundf(px * minf(1.0, screen_size().y / BASE_HEIGHT))


## Where the column must end (px from the top of the screen): above the lock banner and the
## skill bar at the bottom centre.
func column_bottom() -> float:
	return screen_size().y - BOTTOM_RESERVE


## Px kept clear at the bottom of the screen: the skill bar (90) and the lock banner over it
## (its bottom edge 190 up, about 80 tall).
const BOTTOM_RESERVE := 270.0


func _gap() -> float:
	return maxf(4.0, fit(GAP))


# ---------- STRIP ----------
## `node` stays in the strip while it's visible, its top set here each frame (it keeps its own x
## and size). Lower `order` sits higher. Leaves on its own when freed.
func add_to_strip(node: Control, order: int) -> void:
	for s in _strip:
		if s["node"] == node:
			s["order"] = order
			return
	_strip.append({"node": node, "order": order})
	_strip.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])


## Where the strip ends (px from the top of the screen), or -1 when nothing is in it (or it has
## stepped aside for a headline).
func strip_bottom() -> float:
	return _strip_bottom


## Stacks the strip from the top. If the headline showing doesn't fit between the strip and
## column_bottom(), the strip steps aside: hidden (its modulate) until the headline is over, then
## it fades back.
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
		# The height its content needs now: text set this frame grows it before it resizes
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


## Visible, including through any CanvasLayer it's on.
static func _shown(node: CanvasItem) -> bool:
	if not node.is_visible_in_tree():
		return false
	var p := node.get_parent()
	while p != null:
		if p is CanvasLayer and not (p as CanvasLayer).visible:
			return false
		p = p.get_parent()
	return true


# ---------- HEADLINE ----------
## Asks for the headline slot. When it's this one's turn, `show` is called with no arguments and
## puts the message up (placing itself at headline_top() every frame). It may return its height
## in px, for the feed to go under; otherwise the feed allows DEFAULT_HEIGHT. The slot is held
## for `seconds`, or until headline_done(key).
##
## - Another request with the same `key` replaces this one (on screen: `show` runs again).
## - A higher `priority` takes the slot at once: `hide` is called on the one showing, which is
##   dropped, or queued again if it asked `keep` (a NEW LOCK card isn't lost).
## - Waiting longer than `wait` seconds drops it (-1: waits however long it takes).
## Requests whose object (the Callable's) is freed are dropped.
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


## The height assumed for a headline whose `show` doesn't say.
const DEFAULT_HEIGHT := 60.0


## The headline `key` has finished early (faded out, closed): the next one can show.
func headline_done(key: StringName) -> void:
	if not _current.is_empty() and _current["key"] == key:
		_release()
	else:
		_queue = _queue.filter(func(q: Dictionary) -> bool: return q["key"] != key)


## The headline's height changed (a card that wrapped differently).
func set_headline_height(key: StringName, height: float) -> void:
	if not _current.is_empty() and _current["key"] == key \
			and not is_equal_approx(float(_current["height"]), height):
		_current["height"] = height
		_layout_strip(0.0)


## True while `key` has the slot.
func is_showing(key: StringName) -> bool:
	return not _current.is_empty() and _current["key"] == key


## Where a headline's top goes (px from the top of the screen): under the strip.
func headline_top() -> float:
	var y := fit(HEADLINE_MIN)
	return maxf(y, _strip_bottom + _gap() * 2.0) if _strip_bottom >= 0.0 else y


## Where the headline on screen ends, or -1 when there is none.
func headline_bottom() -> float:
	return -1.0 if _current.is_empty() else headline_top() + float(_current["height"])


## The headline on screen has finished: the next one can start after HANDOFF.
func _release() -> void:
	_tail_bottom = headline_bottom()      # its fade's last frames: the feed stays clear of them
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
	_layout_strip(0.0)                    # it may need the strip's place from this frame on


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


## Makes `node` and everything under it OPACITY see-through. It sets their self_modulate, so
## their own fades (on modulate) still run from 0 to 1 as before.
static func see_through(node: Node) -> void:
	var items: Array = node.find_children("*", "CanvasItem", true, false)
	if node is CanvasItem:
		items.append(node)
	for item in items:
		(item as CanvasItem).self_modulate.a = OPACITY


# ---------- FEED ----------
## Where the feed's top goes (px from the top of the screen): under the headline while one is
## up, else under the strip.
func feed_top() -> float:
	var gap := _gap()
	var y := fit(FEED_MIN)
	if _strip_bottom >= 0.0:
		y = maxf(y, _strip_bottom + gap * 2.0)
	var hb := headline_bottom()
	if hb < 0.0 and _clock < _free_at:
		hb = _tail_bottom                 # one just ended: its fade may still be on screen
	if hb >= 0.0:
		y = maxf(y, hb + gap * 1.5)
	return y


## Px the feed has: from feed_top() down to column_bottom(). Lines that don't fit wait.
func feed_room() -> float:
	return maxf(0.0, column_bottom() - feed_top())
