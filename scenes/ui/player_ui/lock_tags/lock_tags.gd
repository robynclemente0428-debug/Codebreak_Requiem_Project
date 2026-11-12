class_name LockTags
extends Control
## Lock tags: a small tag over every puzzle enemy near the player, one per lock (EnemyTrait with
## a LOCK_NAME), so you know what an enemy needs before you hit it:
##        (o) ECHO  NOT STRIKE/A          <> REFLECT  ZAP 8
##          Echo Wisp                       Corrupted Raider
## Each tag is the lock's icon (a shape, so it reads without colour), its name in its colour, and
## what it knows right now (EnemyTrait.tag_state) in red. It flashes whenever the lock speaks.
## Ordinary enemies get no tag, so a tag alone says "think before you hit this". Act bosses get
## none either: they have the lock banner (LockBanner).
##
## Drawn in the window like the rest of the HUD, not in the low-res game view, so the text stays
## sharp under the retro filter. AreaManager adds it to the StimLayer, under the other panels.
##
## NEW LOCK: the first time a character comes near a lock (within NEAR metres), a card introduces
## it above the player: its icon and name, the enemy it was met on, and how to beat it (its HINT,
## shown here whatever the rank: this is the lesson). The enemy's tag pulses while the card is up.
## Met locks are kept in the character's save (SAVE_KEY), so each card shows once. Two new locks
## at once (a rare with two) queue, one card after the other. Its X button closes it early.
## The card is an Announcer headline: it waits while AREA CLEARED or a Null Law is up, sits at
## headline_top(), and if a more important headline cuts it short it shows again afterwards.

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const FONT_SIZE := 13
## Tags show fully within NEAR metres of the player and fade out by FAR.
const NEAR := 11.0
const FAR := 16.0
## Metres above the top of the enemy's body.
const ABOVE := 0.45
const PAD := Vector2(6.0, 3.0)
const ICON := 10.0
const GAP := 5.0                      # icon to name, name to state
const BETWEEN := 6.0                  # tag to tag, when an enemy has more than one lock
const FLASH := 0.45                   # seconds a tag flashes after its lock speaks
const COL_BG := Color(0.02, 0.05, 0.08, 0.82)
const COL_STATE := Color(1.0, 0.45, 0.45)
## Locks this character has met (their LOCK_NAMEs), in its save: each NEW LOCK card shows once.
const SAVE_KEY := "locks_met"
## The NEW LOCK card: its width, and how long it holds.
const CARD_WIDTH := 460.0
const CARD_HOLD := 7.0

var _font: Font
var _container: SubViewportContainer
var _viewport: SubViewport
var _locks := {}                      # enemy instance id -> Array of its lock traits
var _tags: Array[Dictionary] = []     # this frame's tags, drawn in _draw()
var _met := {}                        # LOCK_NAME -> true (loaded from the save once)
var _met_loaded := false
var _met_slot: Variant = null         # whose save _met came from
var _queue: Array[Dictionary] = []    # NEW LOCK cards waiting their turn
var _card: IntroCard
var _card_lock := ""                  # the lock the card is introducing ("" = none)
var _card_info := {}                  # what the card is showing (back to the queue if cut short)
var _card_asked := false              # waiting for Announcer's headline slot
const CARD_HEADLINE := &"new_lock"    # its Announcer headline key


func _ready() -> void:
	process_priority = Announcer.PLACE_AFTER       # places itself after Announcer's layout
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	if _font == null:
		_font = ThemeDB.fallback_font
	_card = IntroCard.new()
	_card.build(_font, CARD_WIDTH, Callable(self, "draw_icon"))
	Announcer.see_through(_card)
	add_child(_card)


func _process(_delta: float) -> void:
	var had := not _tags.is_empty()
	_tags.clear()
	_collect()
	if had or not _tags.is_empty():
		queue_redraw()
	_update_card()


func _collect() -> void:
	if not _find_view():
		return
	var cam := _viewport.get_camera_3d()
	var player := get_tree().get_first_node_in_group("players") as Node3D
	if cam == null or player == null:
		return
	var ratio := _container.size / Vector2(_viewport.size)
	var origin := _container.global_position - global_position
	var seen := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Node3D
		if enemy == null or not enemy.is_inside_tree() or not enemy.is_visible_in_tree():
			continue
		var id := enemy.get_instance_id()
		seen[id] = true
		if enemy.get_meta(&"act_boss", false):
			continue
		var locks: Array = _locks_of(enemy, id)
		if locks.is_empty():
			continue
		var hp := enemy.get("health") as HealthComponent
		if hp != null and hp.current_health <= 0.0:
			continue
		var flat := enemy.global_position - player.global_position
		var dist := Vector2(flat.x, flat.z).length()
		if dist > FAR:
			continue
		var head := enemy.global_position + Vector3.UP * (_top_of(enemy) + ABOVE)
		if cam.is_position_behind(head):
			continue
		var at := cam.unproject_position(head) * ratio + origin
		var alpha := 1.0 - smoothstep(NEAR, FAR, dist)
		if dist <= NEAR:
			for t in locks:
				if is_instance_valid(t):
					_meet(t as EnemyTrait, enemy)
		_add_row(locks, at, alpha)
	for id in _locks.keys():              # forget enemies that are gone
		if not seen.has(id):
			_locks.erase(id)


## One row of tags, centred over `at` (the point above the enemy's head).
func _add_row(locks: Array, at: Vector2, alpha: float) -> void:
	var row: Array[Dictionary] = []
	var total := 0.0
	for t in locks:
		if not is_instance_valid(t):
			continue
		var lock := t as EnemyTrait
		var flash := clampf(1.0 - lock.spoke_ago() / FLASH, 0.0, 1.0)
		if _card_lock != "" and lock.lock_name() == _card_lock:     # the lock the card is about
			flash = maxf(flash, 0.35 + 0.35 * sin(Time.get_ticks_msec() / 1000.0 * 7.0))
		var tag := {
			"name": lock.lock_name(),
			"state": lock.tag_state(),
			"color": lock.lock_color(),
			"shape": lock.lock_shape(),
			"flash": flash,
			"alpha": alpha,
		}
		tag["w"] = _width(tag)
		row.append(tag)
		total += tag["w"]
	if row.is_empty():
		return
	total += BETWEEN * (row.size() - 1)
	var x := at.x - total * 0.5
	var h := _height()
	for tag in row:
		tag["rect"] = Rect2(Vector2(x, at.y - h).round(), Vector2(tag["w"], h))
		x += tag["w"] + BETWEEN
		_tags.append(tag)


func _draw() -> void:
	for tag in _tags:
		_draw_tag(tag)


func _draw_tag(tag: Dictionary) -> void:
	var r: Rect2 = tag["rect"]
	var a: float = tag["alpha"]
	var flash: float = tag["flash"]
	var col: Color = tag["color"]
	var grow := flash * 2.0                                  # a quick swell when the lock speaks
	var box := r.grow(grow)
	draw_rect(box, Color(COL_BG, COL_BG.a * a))
	draw_rect(box, Color(col.lerp(Color.WHITE, flash * 0.6), (0.75 + 0.25 * flash) * a), false, 1.0)
	var x := r.position.x + PAD.x
	var mid := r.position.y + r.size.y * 0.5
	draw_icon(self, tag["shape"], Rect2(x, mid - ICON * 0.5, ICON, ICON), Color(col, a))
	x += ICON + GAP
	var base := r.position.y + PAD.y + _font.get_ascent(FONT_SIZE)
	_text(tag["name"], Vector2(x, base), Color(col.lerp(Color.WHITE, flash * 0.7), a))
	var state: String = tag["state"]
	if state != "":
		x += _font.get_string_size(tag["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + GAP
		_text(state, Vector2(x, base), Color(COL_STATE.lerp(Color.WHITE, flash * 0.5), a))


func _text(s: String, pos: Vector2, col: Color) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color(0, 0, 0, 0.8 * col.a))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)


func _width(tag: Dictionary) -> float:
	var w := PAD.x * 2.0 + ICON + GAP + _font.get_string_size(tag["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	if tag["state"] != "":
		w += GAP + _font.get_string_size(tag["state"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	return ceilf(w)


func _height() -> float:
	return ceilf(_font.get_height(FONT_SIZE) + PAD.y * 2.0)


## A lock's icon in `r`, as an outline shape: the same on the tags and the hover plate.
##   ring     two circles, one inside the other (ECHO)
##   split    two squares out of step (DIFF)
##   hex      a hexagon (FIREWALLED)
##   diamond  a diamond (REFLECT)
##   square   anything else
static func draw_icon(canvas: CanvasItem, shape: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.5
	match shape:
		"ring":
			canvas.draw_arc(c, s, 0.0, TAU, 20, col, 1.5, true)
			canvas.draw_arc(c, s * 0.45, 0.0, TAU, 14, col, 1.5, true)
		"split":
			var k := s * 0.75
			canvas.draw_rect(Rect2(c - Vector2(s, s), Vector2(k, k) * 2.0 - Vector2.ONE), Color(1.0, 0.3, 0.75, col.a), false, 1.5)
			canvas.draw_rect(Rect2(c - Vector2(s, s) + Vector2(s - k, s - k) * 2.0 + Vector2.ONE, Vector2(k, k) * 2.0 - Vector2.ONE), Color(0.3, 0.95, 1.0, col.a), false, 1.5)
		"hex":
			var pts := PackedVector2Array()
			for i in 7:
				var ang := TAU * i / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(ang), sin(ang)) * s)
			canvas.draw_polyline(pts, col, 1.5, true)
		"diamond":
			canvas.draw_polyline(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0),
					c + Vector2(0, s), c + Vector2(-s, 0), c + Vector2(0, -s)]), col, 1.5, true)
		_:
			canvas.draw_rect(Rect2(c - Vector2(s, s) * 0.85, Vector2(s, s) * 1.7), col, false, 1.5)


## ---- NEW LOCK ----

## The player is near `lock` on `enemy`: the first time this character meets that lock, queue its card.
func _meet(lock: EnemyTrait, enemy: Node3D) -> void:
	var lock_id: String = lock.lock_name()
	_load_met()
	if lock_id == "" or _met.has(lock_id):
		return
	_met[lock_id] = true
	_save_met(lock_id)
	_queue.append({
		"name": lock_id,
		"hint": lock.lock_hint(),
		"color": lock.lock_color(),
		"shape": lock.lock_shape(),
		"enemy": str(enemy.get_meta(&"base_name", enemy.get("display_name"))),
	})


func _update_card() -> void:
	if _card.busy():
		_place_card()
		return
	if _card_lock != "":                  # it just finished (faded or closed)
		Announcer.headline_done(CARD_HEADLINE)
		_card_lock = ""
		_card_info = {}
	if _queue.is_empty() or _card_asked:
		return
	_card_asked = true
	Announcer.headline(CARD_HEADLINE, Announcer.NORMAL, CARD_HOLD + 0.85, _show_card, _cut_card, -1.0)


## Announcer's slot is ours: the next card in the queue goes up.
func _show_card() -> float:
	_card_asked = false
	if _queue.is_empty():
		Announcer.headline_done.call_deferred(CARD_HEADLINE)
		return 0.0
	_card_info = _queue.pop_front()
	_card_lock = _card_info["name"]
	_card.show_lock(_card_info, CARD_HOLD)
	_place_card()
	return _card.size.y


## A more important headline took the slot: the card goes, and waits to show again.
func _cut_card() -> void:
	_card.stop()
	if not _card_info.is_empty():
		_queue.push_front(_card_info)
	_card_info = {}
	_card_lock = ""


func _place_card() -> void:
	_card.position = Vector2(roundf((size.x - _card.size.x) * 0.5),
			roundf(Announcer.headline_top() - get_global_rect().position.y))
	Announcer.set_headline_height(CARD_HEADLINE, _card.size.y)   # it settles after a frame


## The met locks of the character playing (loaded again if another character is picked).
func _load_met() -> void:
	var save = _save_manager()
	var slot: Variant = null if save == null or save.party.is_empty() else save.party[0]
	if _met_loaded and slot == _met_slot:
		return
	_met_loaded = true
	_met_slot = slot
	_met.clear()
	if slot == null:
		return
	for lock_id in save.get_data(slot).get(SAVE_KEY, []):
		_met[str(lock_id)] = true


## Into every party member's save, like TutorialHints' lessons (kept with the next save).
func _save_met(lock_id: String) -> void:
	var save = _save_manager()
	if save == null:
		return
	for slot in save.party:
		var data: Dictionary = save.get_data(slot)
		var met: Array = data.get(SAVE_KEY, [])
		if not lock_id in met:
			met.append(lock_id)
		data[SAVE_KEY] = met


func _save_manager() -> Node:
	return get_tree().root.get_node_or_null("SaveManager")


## The NEW LOCK card: fades in, holds, fades out. Only its X button takes the mouse; it closes the
## card early.
class IntroCard extends PanelContainer:
	var _style: StyleBoxFlat
	var _icon: CardIcon
	var _name: Label
	var _enemy: Label
	var _hint: Label
	var _tween: Tween
	var _busy := false

	func build(font: Font, width: float, icon_drawer: Callable) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		custom_minimum_size.x = width
		_style = StyleBoxFlat.new()
		_style.bg_color = Color(0.02, 0.05, 0.08, 0.92)
		_style.set_border_width_all(2)
		_style.corner_radius_top_right = 10
		_style.corner_radius_bottom_left = 10
		_style.content_margin_left = 16
		_style.content_margin_right = 16
		_style.content_margin_top = 12
		_style.content_margin_bottom = 12
		add_theme_stylebox_override("panel", _style)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 4)
		add_child(box)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(top)
		var head := _label(font, 14, Color(0.62, 0.80, 0.86))
		head.text = "// NEW LOCK //"
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(head)
		# The only part of the card that takes the mouse: the rest lets clicks through to the world.
		var close := Button.new()
		close.text = "X"
		close.flat = true
		close.focus_mode = Control.FOCUS_NONE
		close.mouse_filter = Control.MOUSE_FILTER_STOP
		close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		close.tooltip_text = "Close"
		close.custom_minimum_size = Vector2(26, 22)
		close.add_theme_font_override("font", font)
		close.add_theme_font_size_override("font_size", 16)
		close.add_theme_color_override("font_color", Color(0.62, 0.80, 0.86))
		close.add_theme_color_override("font_hover_color", Color.WHITE)
		close.add_theme_color_override("font_pressed_color", Color(1.0, 0.45, 0.45))
		close.pressed.connect(dismiss)
		top.add_child(close)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		_icon = CardIcon.new()
		_icon.drawer = icon_drawer
		_icon.custom_minimum_size = Vector2(26, 26)
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_icon)
		_name = _label(font, 30, Color.WHITE)
		row.add_child(_name)
		_enemy = _label(font, 14, Color(0.62, 0.80, 0.86))
		box.add_child(_enemy)
		_hint = _label(font, 17, Color(0.85, 0.96, 1.0))
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hint.custom_minimum_size.x = width - 32.0
		box.add_child(_hint)
		var more := _label(font, 13, Color(0.55, 0.78, 0.85))
		more.text = "Its tag shows what it knows right now. Point at it for details."
		more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		more.custom_minimum_size.x = width - 32.0
		box.add_child(more)

	func busy() -> bool:
		return _busy

	## The close button: a quick fade, then the next card (if one is waiting) can show.
	func dismiss() -> void:
		if not _busy:
			return
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", 0.0, 0.15)
		_tween.tween_callback(func() -> void:
			visible = false
			_busy = false)

	## Gone at once (another headline took its place).
	func stop() -> void:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		visible = false
		_busy = false

	func show_lock(info: Dictionary, hold: float) -> void:
		var col: Color = info["color"]
		_style.border_color = Color(col, 0.9)
		_icon.shape = info["shape"]
		_icon.col = col
		_icon.queue_redraw()
		_name.text = info["name"]
		_name.add_theme_color_override("font_color", col)
		_enemy.text = "on %s" % info["enemy"]
		_hint.text = info["hint"]
		_hint.visible = info["hint"] != ""
		reset_size()
		visible = true
		modulate.a = 0.0
		_busy = true
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", 1.0, 0.25)
		_tween.tween_interval(hold)
		_tween.tween_property(self, "modulate:a", 0.0, 0.6)
		_tween.tween_callback(func() -> void:
			visible = false
			_busy = false)

	func _label(font: Font, fsize: int, col: Color) -> Label:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", fsize)
		l.add_theme_color_override("font_color", col)
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		return l


## The lock's icon on the card, bigger: the same shapes as the tags.
class CardIcon extends Control:
	var shape := "square"
	var col := Color.WHITE

	var drawer: Callable                  # LockTags.draw_icon

	func _draw() -> void:
		if drawer.is_valid():
			drawer.call(self, shape, Rect2(Vector2.ONE * 2.0, size - Vector2.ONE * 4.0), col)


## The enemy's lock traits (cached: an enemy's traits don't change after it spawns).
func _locks_of(enemy: Node3D, id: int) -> Array:
	if _locks.has(id):
		return _locks[id]
	var out: Array = []
	var traits = enemy.get("traits")
	if traits is Array:
		for t in traits:
			if t is EnemyTrait and (t as EnemyTrait).is_lock():
				out.append(t)
	_locks[id] = out
	return out


## Height of the top of the enemy's body above its feet (its collision cylinder).
func _top_of(enemy: Node3D) -> float:
	var body := enemy.get("collision") as CollisionShape3D
	if body != null and body.shape is CylinderShape3D:
		return body.position.y + (body.shape as CylinderShape3D).height * 0.5
	return 1.8


func _find_view() -> bool:
	if _viewport != null and is_instance_valid(_viewport) and is_instance_valid(_container):
		return true
	var scene := get_tree().current_scene
	if scene == null:
		return false
	_container = scene.find_child("SubViewportContainer", true, false) as SubViewportContainer
	if _container == null:
		return false
	for child in _container.get_children():
		if child is SubViewport:
			_viewport = child
			return true
	return false
