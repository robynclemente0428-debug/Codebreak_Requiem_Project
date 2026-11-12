extends Node
## Tries hard to make the top-centre messages land on each other, and reports when they do.
## Run this scene from the editor (F6). No world and no save: the real message widgets are built
## on an empty screen (QuestTracker's feed, AreaClearedBanner, the Null Law banner, ExamHud's big
## line, LockTags' NEW LOCK card), and two stand-in panels play the strip (the tutorial banner
## and the dock defense panel, which only show inside a real quest).
##
## A timeline fires them all at once, in bursts, and while the strip grows, shrinks and hides. It
## runs once at each UI scale in `ui_scales` (the Settings UI size: 1.5 lays the UI out on a
## 1280 x 720 canvas, 2.0 on 960 x 540). Every frame it measures what's on screen and checks:
##   OVERLAP          two messages' rects cross
##   TWO HEADS        more than one headline showing at once
##   OFF SCREEN       something past an edge of the screen
##   INTO SKILL BAR   something over the bottom SKILL_BAR px (the skill bar)
##   FEED TOO LOW     a feed line below Announcer.column_bottom() (into the lock banner's place)
## and lists each headline asked for, when it showed, and any that never did.
## Results go to the Output panel and to announce_test_results.txt beside this script. Your own
## UI size setting is put back when it finishes; nothing is saved.

const NullLawBannerScript := preload("res://systems/world/null_law_banner.gd")
const RESULTS := "res://tools/announce_test/announce_test_results.txt"
const FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"

## Game speed while it runs (tweens and Announcer's clock both follow it).
@export var speed := 2.0
## Seconds of game time per UI scale (then it waits for the last messages to clear).
@export var length := 40.0
## The UI sizes to run at, one after another.
@export var ui_scales: Array[float] = [1.0, 1.5, 2.0]
## Rects closer than this (px) still count as apart (anti-aliased edges).
const SLACK := 1.0
## The skill bar's height above the bottom of the screen (SkillBar: 64 px slots, 26 px up).
const SKILL_BAR := 90.0                   # px

var _t := 0.0
var _pass := -1                           # index into ui_scales
var _draining := false                    # the timeline is done; waiting for the screen to clear
var _events: Array = []                   # [time, label, Callable], soonest first
var _hud: Control
var _tracker: QuestTracker
var _law: Control
var _exam: ExamHud
var _locks: LockTags
var _strip_a: PanelContainer              # stand-in: the tutorial banner
var _strip_a_sub: Label
var _strip_b: PanelContainer              # stand-in: the dock defense panel
var _font: Font
var _found := {}                          # check -> {what -> {"first": t, "frames": n}}
var _asked: Array[String] = []            # headlines asked for, in order
var _shown := {}                          # headline -> [times it came up]
var _was_showing := {}                    # headline -> showing last frame
var _frames := 0
var _report: PackedStringArray = []
var _all_ok := true
var _user_scale := 1.0
var _finished := false


func _ready() -> void:
	_font = load(FONT)
	Engine.time_scale = speed
	TutorialHints.enabled = false          # the stand-in plays it
	# Settings puts your UI size back whenever the window changes: not while this runs
	var root := get_tree().root
	_user_scale = root.content_scale_factor
	if root.size_changed.is_connected(Settings._apply_ui_scale):
		root.size_changed.disconnect(Settings._apply_ui_scale)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_hud)
	_tracker = QuestTracker.new()
	_hud.add_child(_tracker)
	_law = NullLawBannerScript.new()
	_hud.add_child(_law)
	_locks = LockTags.new()
	_hud.add_child(_locks)
	_exam = ExamHud.new()
	add_child(_exam)
	_strip_a = _stand_in("SCRIPT YOUR SKILL: open the skills menu [K]", 860.0, 20)
	_strip_a_sub = _strip_a.get_child(0).get_child(1)
	_strip_b = _stand_in("HOLD THE DOCK", 460.0, 19)
	(_strip_b.get_child(0).get_child(1) as Label).text = "Hardfault loading... 40%\nNull left: 12"
	Announcer.add_to_strip(_strip_a, 0)
	Announcer.add_to_strip(_strip_b, 10)
	# Measured just before each frame is drawn: after every message has placed itself and every
	# container has laid out its children, so it's what the player sees
	RenderingServer.frame_pre_draw.connect(_measure)
	_next_pass()


## A panel like the strip's messages: a title and a second line, centred, `width` wide.
func _stand_in(title: String, width: float, layer_n: int) -> PanelContainer:
	var layer := CanvasLayer.new()
	layer.layer = layer_n
	add_child(layer)
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.08, 0.9)
	sb.border_color = Color(0.3, 0.95, 0.6)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	p.add_child(v)
	for i in 2:
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", _font)
		l.add_theme_font_size_override("font_size", 20 if i == 0 else 15)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = width - 24.0
		l.text = title if i == 0 else ""
		v.add_child(l)
	layer.add_child(p)
	return p


# ---------- PASSES ----------
func _next_pass() -> void:
	_pass += 1
	if _pass >= ui_scales.size():
		_finish()
		return
	get_tree().root.content_scale_factor = ui_scales[_pass]
	_t = 0.0
	_draining = false
	_found = {}
	_asked.clear()
	_shown.clear()
	_was_showing.clear()
	_frames = 0
	_strip_a.visible = false
	_strip_b.visible = false
	_strip_a_sub.text = "Rules make a skill fire on its own when their condition holds."
	_events.clear()
	_plan()
	print("[ANNOUNCE TEST] UI scale %.1f: %d events over %.0f s at x%.1f" % [
			ui_scales[_pass], _events.size(), length, speed])


## Nothing on screen or waiting: the next pass can start clean.
func _screen_clear() -> bool:
	var got := _on_screen()
	var waiting: Array = Announcer.get("_queue")
	var lock_queue: Array = _locks.get("_queue")
	return (got[0] as Dictionary).is_empty() and waiting.is_empty() and lock_queue.is_empty() \
			and not Announcer.headline_bottom() >= 0.0


# ---------- THE TIMELINE ----------
func _plan() -> void:
	_at(0.3, "strip: banner + dock panel", func() -> void:
		_strip_a.visible = true
		_strip_b.visible = true)
	# Everything at once
	_at(1.0, "ALL AT ONCE: area cleared, null law, 2 new locks, 4 toasts", func() -> void:
		_area_cleared("The Spillway")
		_null_law("life_inverted")
		_new_lock("ECHO")
		_new_lock("REFLECT")
		_toast("NEW QUEST: CLEAR THE SPILLWAY")
		_toast("THE NULL ARE AT THE POWER CORE\nIf it falls: the lights go out")
		_toast("QUEST READY: CLEAR THE SPILLWAY")
		_toast("RECOVERED: SIGNAL KEY"))
	_at(1.2, "same toast twice (should count up)", func() -> void:
		_toast("RECOVERED: SIGNAL KEY")
		_toast("RECOVERED: SIGNAL KEY"))
	# The exam takes the slot from whatever is up
	_at(2.0, "exam: RUN IN 3 (interrupts)", func() -> void: _flash("RUN IN 3"))
	_at(3.0, "exam: RUN IN 2", func() -> void: _flash("RUN IN 2"))
	_at(4.0, "exam: RUN IN 1", func() -> void: _flash("RUN IN 1"))
	_at(5.0, "exam: wave name with a note", func() -> void:
		_flash("WAVE 1 // SWARM\nMany weak enemies at once: an area rule earns its keep."))
	# The strip changes height while a headline and the feed are up
	_at(6.0, "strip: banner grows to 3 lines", func() -> void:
		_strip_a_sub.text = "Rules make a skill fire on its own when their condition holds. " \
				+ "Pick a condition, set its number, and watch the rule light up when it fires. " \
				+ "Spend script points to make the skill stronger while the rule holds.")
	_at(7.0, "convoy burst: 6 toasts in 0.5 s", func() -> void:
		for i in 6:
			_toast_later(i * 0.1, "COMMS AT %d%%\nThe Null are in the hold." % (90 - i * 10)))
	_at(9.0, "strip: dock panel hides", func() -> void: _strip_b.visible = false)
	_at(10.0, "null law changes (replaces the waiting one)", func() -> void: _null_law("near_is_far"))
	_at(10.5, "area cleared again", func() -> void: _area_cleared("The Undercroft"))
	_at(14.0, "strip: banner hides, dock panel back", func() -> void:
		_strip_a.visible = false
		_strip_b.visible = true)
	_at(14.5, "new lock + toasts while the strip moves", func() -> void:
		_new_lock("CHECKSUM")
		_toast("QUEST COMPLETE: CLEAR THE SPILLWAY")
		_toast("BEACON ONLINE: WARD 3"))
	_at(16.0, "everything at once with no strip", func() -> void:
		_strip_b.visible = false
		_area_cleared("The Last Mile")
		_null_law("life_inverted")
		_flash("EXECUTE")
		for i in 4:
			_toast("CRATE TAGGED\nKill the markers before the sweep, or it's deleted."))
	_at(22.0, "strip: both back while the queue drains", func() -> void:
		_strip_a.visible = true
		_strip_b.visible = true)
	_at(length - 1.0, "strip: both hide", func() -> void:
		_strip_a.visible = false
		_strip_b.visible = false)
	_events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


func _at(time: float, label: String, what: Callable) -> void:
	_events.append([time, label, what])


func _area_cleared(area: String) -> void:
	_asked.append("area_cleared")
	AreaClearedBanner.announce(get_tree(), area, "+1 SCRIPT POINT ON EVERY SKILL")


func _null_law(id: String) -> void:
	_asked.append("null_law")
	_law.call("show_law", id)
	_law.call("announce", id)


func _new_lock(lock_name: String) -> void:
	_asked.append("new_lock:" + lock_name)
	(_locks.get("_queue") as Array).append({"name": lock_name, "hint": "Hit it with something it hasn't seen.",
			"color": Color(0.3, 0.95, 1.0), "shape": "square", "enemy": "Echo Wisp"})


func _flash(text: String) -> void:
	_asked.append("exam")
	_exam.call("_show_flash", text, ExamHud.ACCENT, 0.8 if text.begins_with("RUN") else 1.6)


func _toast(text: String) -> void:
	QuestItems.toast(get_tree(), text)


func _toast_later(delay: float, text: String) -> void:
	get_tree().create_timer(delay).timeout.connect(_toast.bind(text))


# ---------- EACH FRAME ----------
func _process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	var w := get_viewport().get_visible_rect().size.x
	for p in [_strip_a, _strip_b]:
		p.reset_size()                     # shrink to the text, like the real banner does
		p.position.x = roundf((w - p.size.x) * 0.5)
	while not _events.is_empty() and _events[0][0] <= _t:
		var e: Array = _events.pop_front()
		print("[ANNOUNCE TEST] %5.2f  %s" % [_t, e[1]])
		(e[2] as Callable).call()
	if _t >= length and not _draining:
		_draining = true
		_end_pass()
	if _draining and (_screen_clear() or _t > length + 30.0):
		_next_pass()


## What's on screen now, as {name: Rect2} (screen px), and which of those are headlines.
func _on_screen() -> Array:
	var rects := {}
	var heads: Array[String] = []
	# (a strip panel at modulate 0 has stepped aside for a headline: Announcer)
	if _strip_a.is_visible_in_tree() and _strip_a.modulate.a > 0.02:
		rects["tutorial banner"] = _strip_a.get_global_rect()
	if _strip_b.is_visible_in_tree() and _strip_b.modulate.a > 0.02:
		rects["dock panel"] = _strip_b.get_global_rect()
	var feed := _tracker.get("_feed") as VBoxContainer
	var i := 0
	for line in feed.get_children():
		var l := line as Label
		if l != null and l.visible and not l.is_queued_for_deletion() and l.modulate.a > 0.02:
			rects["toast %d" % i] = _text_rect(l)
			i += 1
	for b in get_tree().get_nodes_in_group("area_cleared_banner"):
		var band := b.get("_band") as Control
		if not b.is_queued_for_deletion() and band != null and band.modulate.a > 0.02:
			# The band as drawn (not its labels): it opens from its centre line over its first OPEN seconds
			var open := ease(clampf(float(b.get("_t")) / AreaClearedBanner.OPEN, 0.0, 1.0), 0.4)
			var h := AreaClearedBanner.BAND_H * open
			var top: float = b.call("_centre_y") - h * 0.5 - 8.0
			rects["AREA CLEARED"] = Rect2(0.0, top, band.size.x, h)
			heads.append("area_cleared")
	var big := _law.get("_big") as Control
	if big.modulate.a > 0.02:
		rects["NULL LAW line"] = big.get_global_rect()
		heads.append("null_law")
	var flash := _exam.get("_flash") as Label
	if flash.modulate.a > 0.02:
		rects["exam line"] = _text_rect(flash)
		heads.append("exam")
	var card := _locks.get("_card") as Control
	if card.visible and card.modulate.a > 0.02:
		rects["NEW LOCK " + str(_locks.get("_card_lock"))] = card.get_global_rect()
		heads.append("new_lock:" + str(_locks.get("_card_lock")))
	return [rects, heads]


## The part of a centred label its text covers (its rect spans the screen).
func _text_rect(l: Label) -> Rect2:
	var r := l.get_global_rect()
	var font := l.get_theme_font("font")
	var w := 0.0
	for line in l.text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1,
				l.get_theme_font_size("font_size")).x)
	w = minf(w, r.size.x)
	return Rect2(r.position.x + (r.size.x - w) * 0.5, r.position.y, w, r.size.y)


func _measure() -> void:
	if _finished or _draining or _pass < 0 or not is_inside_tree():
		return
	_frames += 1
	var got := _on_screen()
	var rects: Dictionary = got[0]
	var heads: Array = got[1]
	var names := rects.keys()
	for a in range(names.size()):
		for b in range(a + 1, names.size()):
			var na: String = names[a]
			var nb: String = names[b]
			if na.begins_with("toast") and nb.begins_with("toast"):
				continue                     # lines of the one feed
			var ra := rects[na] as Rect2
			var rb := rects[nb] as Rect2
			if ra.size.y <= SLACK * 2.0 or rb.size.y <= SLACK * 2.0:
				continue                     # the band's first frame, before it opens
			if ra.grow(-SLACK).intersects(rb.grow(-SLACK)):
				_count("OVERLAP", "%s | %s" % [na, nb])
	if heads.size() > 1:
		_count("TWO HEADS", " + ".join(heads))
	var screen := get_viewport().get_visible_rect().size
	for n in names:
		var r := rects[n] as Rect2
		if r.end.y > screen.y + SLACK or r.position.y < -SLACK or r.position.x < -SLACK \
				or r.end.x > screen.x + SLACK:
			_count("OFF SCREEN", n)
		elif r.end.y > screen.y - SKILL_BAR + SLACK:
			_count("INTO SKILL BAR", "%s (bottom %d of %d)" % [n, roundi(r.end.y), roundi(screen.y)])
		if n.begins_with("toast") and r.end.y > Announcer.column_bottom() + SLACK:
			_count("FEED TOO LOW", n)
	for h in heads:
		if not _was_showing.get(h, false):
			if not _shown.has(h):
				_shown[h] = []
			_shown[h].append(snappedf(_t, 0.01))
	_was_showing.clear()
	for h in heads:
		_was_showing[h] = true


func _count(check: String, what: String) -> void:
	if not _found.has(check):
		_found[check] = {}
	var into: Dictionary = _found[check]
	if not into.has(what):
		into[what] = {"first": snappedf(_t, 0.01), "frames": 0}
		print("[ANNOUNCE TEST] %5.2f  !! %s: %s" % [_t, check, what])
	into[what]["frames"] += 1


# ---------- REPORT ----------
const CHECKS := ["OVERLAP", "TWO HEADS", "OFF SCREEN", "INTO SKILL BAR", "FEED TOO LOW"]


func _end_pass() -> void:
	var screen := get_viewport().get_visible_rect().size
	_report.append("== UI SCALE %.1f  (canvas %d x %d, %d frames measured)" % [
			ui_scales[_pass], roundi(screen.x), roundi(screen.y), _frames])
	var ok := true
	for check in CHECKS:
		var found: Dictionary = _found.get(check, {})
		_report.append("%s: %s" % [check, "none" if found.is_empty() else str(found.size())])
		for k in found:
			_report.append("  %s  (first at %.2f s, %d frames)" % [k, found[k]["first"], found[k]["frames"]])
		ok = ok and found.is_empty()
	_report.append("SHOWN: " + ", ".join(_shown.keys().map(func(h: String) -> String:
		return "%s %s" % [h, _shown[h]])))
	var never: Array[String] = []
	for h in _asked:
		if not _shown.has(h) and not never.has(h):
			never.append(h)
	_report.append("NEVER SHOWN: " + (", ".join(never) if not never.is_empty() else "none"))
	_report.append("PASS" if ok else "FAIL")
	_report.append("")
	_all_ok = _all_ok and ok


func _finish() -> void:
	_finished = true
	if RenderingServer.frame_pre_draw.is_connected(_measure):
		RenderingServer.frame_pre_draw.disconnect(_measure)
	Engine.time_scale = 1.0
	TutorialHints.enabled = true
	var root := get_tree().root
	root.content_scale_factor = _user_scale
	if not root.size_changed.is_connected(Settings._apply_ui_scale):
		root.size_changed.connect(Settings._apply_ui_scale)
	_report.insert(0, "ANNOUNCE TEST  (%.0f s per UI scale at x%.1f)\n" % [length, speed])
	_report.append("RESULT: " + ("PASS" if _all_ok else "FAIL"))
	var text := "\n".join(_report)
	print(text)
	var f := FileAccess.open(RESULTS, FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
