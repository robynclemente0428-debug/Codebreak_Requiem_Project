class_name StimHud
extends Control
## Stims in play: the hotkeys (stim_1 / stim_2, keys 1 and 2 by default, rebindable in
## Settings > Controls), restoring life / mana, charges from kills, and the HUD gauges that
## sit between the life bar and the skill hotbar.
##
##  - Using a stim spends its per-use charges and restores its amount over its duration
##    (instantly if the duration is 0). The same stim can't be used again while it's working.
##  - Every enemy kill adds charges to both equipped stims: StimRoller.CHARGES_PER_KILL by the
##    enemy's rarity, times the stim's own gain. Stims "of Reserves" also refill slowly.
##  - Arriving in a town refills every stim (TownArea calls refill_all()).
##
## AreaManager adds this node; nothing to place in main.tscn.

const ACTIONS: Array[StringName] = [&"stim_1", &"stim_2"]
const DEFAULT_KEYS: Array[int] = [KEY_1, KEY_2]
const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_LIFE := Color(1.0, 0.30, 0.37)
const COL_MANA := Color(0.30, 0.64, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const GAUGE := Vector2(46, 150)
const GAP := 14.0
## The least space kept between the gauges and the life bar or the hotbar (px).
const MIN_GAP := 16.0

var _font: Font
var _active: Dictionary = {}        # slot -> {"left": amount still to restore, "rate": per second, "until": msec}
var _flash: Dictionary = {}         # slot -> msec until a "not enough charges" flash ends
var _regen_carry: Dictionary = {}   # slot -> fractional charges from "of Reserves"


func _enter_tree() -> void:
	add_to_group("stim_hud")


func _ready() -> void:
	_font = load(DEFAULT_FONT) if ResourceLoader.exists(DEFAULT_FONT) else null
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom-left, right next to the life bar (re-checked every frame in _follow_life_bar)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 490.0
	offset_right = offset_left + GAUGE.x * 2.0 + GAP + 8.0
	offset_bottom = -20.0
	offset_top = offset_bottom - (GAUGE.y + 44.0)
	for i in ACTIONS.size():
		if not InputMap.has_action(ACTIONS[i]):                 # in case project.godot lacks them
			InputMap.add_action(ACTIONS[i])
			var ev := InputEventKey.new()
			ev.physical_keycode = DEFAULT_KEYS[i]
			InputMap.action_add_event(ACTIONS[i], ev)
	GameEvents.happened.connect(_on_game_event)


func _player() -> Node:
	return get_tree().get_first_node_in_group("players")


func _stim(slot: int) -> ItemInstance:
	var p := _player()
	if p == null or p.get("equipment") == null:
		return null
	var item: ItemInstance = p.equipment.get_equipped(slot)
	if item != null and item.definition.is_stim() and not item.stim_roll.has("amount"):
		StimRoller.recompute(item)
	return item if item != null and item.definition.is_stim() else null


# ---------- USING ----------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	for i in ACTIONS.size():
		if event.is_action_pressed(ACTIONS[i]):
			use(EquipmentSlots.STIM_SLOTS[i])
			get_viewport().set_input_as_handled()
			return


## Uses the stim in `slot`. Returns false (and flashes the gauge) if it can't.
func use(slot: int) -> bool:
	var p := _player()
	var item := _stim(slot)
	if p == null or item == null or get_tree().paused:
		return false
	if p.get("input_locked") == true:
		return false                                       # talking, typing a name...
	var health: HealthComponent = p.get("health")
	if health == null or health.current_health <= 0.0:
		return false
	var per_use: int = item.stim_roll["per_use"]
	if item.charges < per_use or _active.has(slot):
		_flash[slot] = Time.get_ticks_msec() + 350
		return false
	item.charges -= per_use
	var amount: float = item.stim_roll["amount"]
	var duration: float = item.stim_roll["duration"]
	if duration <= 0.0:
		_restore(item, amount)
	else:
		_active[slot] = {"left": amount, "rate": amount / duration,
				"until": Time.get_ticks_msec() + int(duration * 1000.0)}
	GameEvents.report("use_stim", item.definition.id)
	return true


func _restore(item: ItemInstance, amount: float) -> void:
	var p := _player()
	if p == null or amount <= 0.0:
		return
	if item.definition.stim.kind == StimDefinition.Kind.HEALTH:
		p.health.heal(amount)
	else:
		p.mana.restore(amount)


## Keeps the gauges centred in the gap between the life bar and the skill hotbar, so the space
## on each side is the same and moving either one moves them too. With no hotbar, or too little
## room between the two, they sit MIN_GAP right of the life bar.
func _follow_life_bar() -> void:
	var hp := get_tree().get_first_node_in_group("hp_hud") as Control
	if hp == null or not hp.is_visible_in_tree():
		return
	var r := hp.get_global_rect()
	var w := offset_right - offset_left
	var x := r.end.x + MIN_GAP
	var bar := get_tree().get_first_node_in_group("skill_bar") as Control
	if bar != null and bar.is_visible_in_tree():
		var room := bar.get_global_rect().position.x - r.end.x
		if room >= w + MIN_GAP * 2.0:
			x = r.end.x + (room - w) * 0.5
	position = Vector2(x, r.end.y - size.y + 4.0).round()
	size = Vector2(w, size.y)


func _process(delta: float) -> void:
	_follow_life_bar()
	var p := _player()
	var dead: bool = p == null or p.health.current_health <= 0.0
	for slot in _active.keys():
		var item := _stim(slot)
		var e: Dictionary = _active[slot]
		if item == null or dead:
			_active.erase(slot)                            # unequipped or died: the effect stops
			continue
		var step: float = minf(e["rate"] * delta, e["left"])
		_restore(item, step)
		e["left"] -= step
		if e["left"] <= 0.001:
			_active.erase(slot)
	# "of Reserves": slow passive refill
	for slot in EquipmentSlots.STIM_SLOTS:
		var item := _stim(slot)
		if item == null or float(item.stim_roll.get("regen", 0.0)) <= 0.0 or get_tree().paused:
			continue
		_regen_carry[slot] = _regen_carry.get(slot, 0.0) + float(item.stim_roll["regen"]) * delta
		if _regen_carry[slot] >= 1.0:
			_add_charges(item, floorf(_regen_carry[slot]))
			_regen_carry[slot] -= floorf(_regen_carry[slot])
	queue_redraw()


# ---------- CHARGES ----------
func _on_game_event(kind: String, target: String, _amount: int) -> void:
	if kind != "kill_rarity":
		return
	var base: float = StimRoller.CHARGES_PER_KILL.get(target, 1.0)
	for slot in EquipmentSlots.STIM_SLOTS:
		var item := _stim(slot)
		if item != null:
			_add_charges(item, base * float(item.stim_roll.get("gain", 1.0)))


## Whole charges are added at once; a stim's fractional gain (e.g. x1.6) is kept between kills.
func _add_charges(item: ItemInstance, amount: float) -> void:
	var carry: float = item.get_meta("charge_carry", 0.0) + amount
	var whole := floori(carry)
	item.set_meta("charge_carry", carry - whole)
	item.charges = mini(item.charges + whole, int(item.stim_roll["max_charges"]))


## Fills every equipped stim (towns call this).
func refill_all() -> void:
	for slot in EquipmentSlots.STIM_SLOTS:
		var item := _stim(slot)
		if item != null:
			item.charges = int(item.stim_roll["max_charges"])


# ---------- DRAWING ----------
func _draw() -> void:
	for i in EquipmentSlots.STIM_SLOTS.size():
		var slot: int = EquipmentSlots.STIM_SLOTS[i]
		var x := 4.0 + i * (GAUGE.x + GAP)
		_draw_gauge(Rect2(Vector2(x, 22.0), GAUGE), slot, i)


func _draw_gauge(r: Rect2, slot: int, index: int) -> void:
	var item := _stim(slot)
	var key := GemText.key_label(ACTIONS[index])
	# hotkey above the gauge
	if _font:
		draw_string(_font, Vector2(r.position.x, r.position.y - 6.0), key,
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, COL_DIM)
	var c := 8.0
	var poly := PackedVector2Array([
		r.position + Vector2(c, 0), r.position + Vector2(r.size.x, 0),
		r.position + Vector2(r.size.x, r.size.y - c), r.position + Vector2(r.size.x - c, r.size.y),
		r.position + Vector2(0, r.size.y), r.position + Vector2(0, c)])
	var outline := PackedVector2Array(poly)
	outline.append(poly[0])
	if item == null:                                     # empty slot
		draw_colored_polygon(poly, Color(0.02, 0.05, 0.09, 0.35))
		draw_polyline(outline, Color(COL_DIM, 0.25), 1.5, true)
		if _font:
			draw_string(_font, r.position + Vector2(0, r.size.y * 0.5 + 6.0), "-",
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, Color(COL_DIM, 0.4))
		return

	var col := COL_LIFE if item.definition.stim.kind == StimDefinition.Kind.HEALTH else COL_MANA
	var max_c: int = item.stim_roll["max_charges"]
	var per_use: int = item.stim_roll["per_use"]
	var usable: bool = item.charges >= per_use
	var flashing: bool = Time.get_ticks_msec() < int(_flash.get(slot, 0))
	draw_colored_polygon(poly, Color(0.02, 0.05, 0.09, 0.75))

	# fill from the bottom
	var inner := r.grow(-4.0)
	var frac := clampf(float(item.charges) / float(max_c), 0.0, 1.0)
	var fill_h := inner.size.y * frac
	var fill_col := Color(col, 0.85 if usable else 0.35)
	draw_rect(Rect2(inner.position.x, inner.end.y - fill_h, inner.size.x, fill_h), fill_col)
	# one tick per use, so you can count uses at a glance
	var uses := int(max_c / per_use)
	for u in range(1, uses + 1):
		var y := inner.end.y - inner.size.y * float(u * per_use) / float(max_c)
		if y > inner.position.y + 1.0:
			draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(0, 0, 0, 0.55), 2.0)

	var border := col
	if flashing:
		border = Color(1.0, 0.2, 0.2)
	if _active.has(slot):                                # working: pulsing glow
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0)
		draw_polyline(outline, Color(col, 0.25 + 0.35 * pulse), 9.0, true)
	draw_polyline(outline, Color(border, 1.0 if usable else 0.45), 2.0, true)

	if _font:
		var text := "%d/%d" % [item.charges, max_c]
		var at := Vector2(r.position.x - 8.0, r.end.y + 16.0)
		draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 16.0, 14, 5, Color(0, 0, 0, 0.85))
		draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 16.0, 14,
				Color(col.lightened(0.25), 1.0) if usable else COL_DIM)
