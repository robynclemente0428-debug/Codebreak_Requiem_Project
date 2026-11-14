class_name SkillBar
extends Control
## An always-visible row of skill slots in the HUD, one per hotkey of the skills menu.
## Shows the key, the skill, its mana cost, and a cooldown sweep after each cast.
## It ignores the mouse completely, so clicks go through to the game.
##
## Setup: add a plain Control to the Hud CanvasLayer, attach this script, set its font,
## and call bind(skills, mana) from the player.

@export var slot_size: float = 64.0
@export var slot_gap: float = 8.0
@export var accent := Color("#00E5FF")
@export var font: Font                          # leave empty to use the Courier Prime font below
@export var font_scale: float = 1.0
## Left edge of the bar measured from the middle of the screen (x), and its distance from the
## bottom edge (y). The defaults put it just to the right of the HP and mana bars.
## The bar is centred at the bottom of the screen; x nudges it sideways, y is the gap below it.
@export var offset_from_center := Vector2(0.0, 26.0)
## The player has ONE shared attack cooldown, so every slot sweeps together.
## Turn it off to sweep only the skill that was used.
@export var shared_cooldown: bool = true
@export var hide_empty_slots: bool = false
var _equip: EquipmentComponent
const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_SKILL := Color(0.30, 0.95, 0.60)
const COL_WARN := Color(1.0, 0.30, 0.37)
const COL_MANA := Color(0.35, 0.70, 1.0)

var _font: Font
var _skills: SkillComponent
var _mana: ManaComponent
var _slots: Dictionary = {}             # action -> BarSlot
var _hooks: Array = []                  # [{skill, call}] so old connections can be removed
var _tip: PanelContainer
var _tip_box: VBoxContainer
var _hover_action: StringName = &""     # the hotkey whose slot the mouse is over
var _set_label: RichTextLabel           # "SCRIPT SET  A  B  C  [X]" over the bar's left end
var _set_msg: Label                     # "SCRIPT SET B" (or why it didn't swap), fading
var _set_tween: Tween
## The bar stays centred unless the stim gauges (beside the life bar) would come closer than
## STIM_CLEARANCE px: then it moves right just enough (_shift px). A wider life bar (its UI
## scale) pushes the stims, and so the bar, along with it.
const STIM_CLEARANCE := 40.0                  # px
var _shift := 0.0


func _enter_tree() -> void:
	add_to_group("skill_bar")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	KeyBindings.load_saved()
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_layout()
	_build()


func bind(skills: SkillComponent, mana: ManaComponent, equipment: EquipmentComponent = null) -> void:
	_equip = equipment
	if _skills and _skills.changed.is_connected(_sync):
		_skills.changed.disconnect(_sync)
	_skills = skills
	_mana = mana
	if _skills:
		_skills.changed.connect(_sync)
	_sync()


func _layout() -> void:
	var count := SkillComponent.ACTIONS.size()
	var width := count * slot_size + maxi(count - 1, 0) * slot_gap
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = offset_from_center.x + _shift - width * 0.5
	offset_right = offset_from_center.x + _shift + width * 0.5
	offset_bottom = -offset_from_center.y
	offset_top = offset_bottom - slot_size


func _build() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", roundi(slot_gap))
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for action in SkillComponent.ACTIONS:
		var slot := BarSlot.new()
		slot.custom_minimum_size = Vector2(slot_size, slot_size)
		slot.accent = accent
		slot.skill_col = COL_SKILL
		slot.warn_col = COL_WARN
		slot.mana_col = COL_MANA
		slot.font = _font if _font else ThemeDB.fallback_font
		slot.font_scale = font_scale
		row.add_child(slot)
		_slots[action] = slot

	# Script sets: which one is running, over the bar's left end (only once the player scripts)
	_set_label = RichTextLabel.new()
	_set_label.bbcode_enabled = true
	_set_label.fit_content = true
	_set_label.scroll_active = false
	_set_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_set_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_label.position = Vector2(0.0, -26.0 * font_scale)
	_set_label.size = Vector2(400.0, 24.0 * font_scale)
	if _font:
		_set_label.add_theme_font_override("normal_font", _font)
	_set_label.add_theme_font_size_override("normal_font_size", roundi(14 * font_scale))
	_set_label.add_theme_constant_override("outline_size", 4)
	_set_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_set_label.visible = false
	add_child(_set_label)
	_set_msg = Label.new()
	_set_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_msg.position = Vector2(0.0, -52.0 * font_scale)
	if _font:
		_set_msg.add_theme_font_override("font", _font)
	_set_msg.add_theme_font_size_override("font_size", roundi(15 * font_scale))
	_set_msg.add_theme_constant_override("outline_size", 4)
	_set_msg.add_theme_color_override("font_outline_color", Color.BLACK)
	_set_msg.modulate.a = 0.0
	add_child(_set_msg)

	# Tooltip: top_level so it positions in screen space, and it never takes the mouse
	_tip = PanelContainer.new()
	_tip.top_level = true
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.custom_minimum_size.x = 290.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.09, 0.97)
	style.border_color = Color(accent, 0.8)
	style.set_border_width_all(1)
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_tip.add_theme_stylebox_override("panel", style)
	_tip_box = VBoxContainer.new()
	_tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_box.add_theme_constant_override("separation", 3)
	_tip.add_child(_tip_box)
	add_child(_tip)


## Re-reads which skill sits on which hotkey, and listens to those skills being used.
func _sync() -> void:
	_refresh_set()
	_hover_action = &""
	if _tip:
		_tip.visible = false
	for hook in _hooks:
		var old: SkillInstance = hook["skill"]
		if is_instance_valid(old) and old.used.is_connected(hook["call"]):
			old.used.disconnect(hook["call"])
	_hooks.clear()

	for action in SkillComponent.ACTIONS:
		var slot: BarSlot = _slots.get(action)
		if slot == null:
			continue
		var skill: SkillInstance = null
		var title := ""
		var glyph := ""
		if _skills:
			var index: int = _skills.bindings.get(action, -1)
			if index >= 0 and index < _skills.sockets.size():
				var s: SkillComponent.Socket = _skills.sockets[index]
				skill = s.skill
				if s.gem:
					title = s.gem.definition.display_name
					glyph = ItemGlyph.kind_for(s.gem.definition)
		slot.skill = skill
		slot.title = title.left(3).to_upper()
		slot.glyph = glyph
		slot.visible = not hide_empty_slots or skill != null
		if skill:
			var c := _on_skill_used.bind(action)
			skill.used.connect(c)
			_hooks.append({"skill": skill, "call": c})


func _refresh_set() -> void:
	if _set_label == null:
		return
	_set_label.visible = _skills != null and _skills.uses_scripts()
	if not _set_label.visible:
		return
	var parts := PackedStringArray()
	for i in _skills.sets_unlocked():           # locked sets (Ranks.PERKS) aren't shown
		var n: String = _skills.set_label(i)
		parts.append("[color=#%s]%s[/color]" % [(accent if i == _skills.script_set else Color(0.45, 0.55, 0.6)).to_html(false),
				"[%s]" % n if i == _skills.script_set else " %s " % n])
	_set_label.text = "[color=#8fb3bf]SCRIPT SET[/color] %s  [color=#8fb3bf][%s][/color]" % [
			"".join(parts), GemText.key_label(&"script_set")]


## After the swap key: the new set's name, or why it didn't swap (in red).
func show_set_message(why: String) -> void:
	_refresh_set()
	if _set_msg == null:
		return
	if why == "":
		_set_msg.text = "SCRIPT SET %s" % _skills.set_label(_skills.script_set)
		_set_msg.add_theme_color_override("font_color", accent)
	else:
		_set_msg.text = why
		_set_msg.add_theme_color_override("font_color", COL_WARN)
	_set_msg.modulate.a = 1.0
	if _set_tween:
		_set_tween.kill()
	_set_tween = create_tween()
	_set_tween.tween_interval(1.6)
	_set_tween.tween_property(_set_msg, "modulate:a", 0.0, 0.4)


func _on_skill_used(duration: float, action: StringName) -> void:
	for a in _slots:
		if shared_cooldown or a == action:
			(_slots[a] as BarSlot).start_cooldown(duration, a == action)


## Where the stims sit when they hug the life bar (StimHud.MIN_GAP to its right): measured from
## the life bar, not the stims themselves, which centre in whatever room the bar leaves.
func _keep_clear_of_stims() -> void:
	var want := 0.0
	var hp := get_tree().get_first_node_in_group("hp_hud") as Control
	var stims := get_tree().get_first_node_in_group("stim_hud") as Control
	if hp != null and stims != null and hp.is_visible_in_tree() and stims.is_visible_in_tree():
		var stims_right := hp.get_global_rect().end.x + StimHud.MIN_GAP \
				+ (stims.offset_right - stims.offset_left)
		var centred_left := get_global_rect().position.x - _shift
		want = maxf(0.0, stims_right + STIM_CLEARANCE - centred_left)
	if not is_equal_approx(want, _shift):
		_shift = want
		_layout()


func _process(delta: float) -> void:
	_keep_clear_of_stims()
	for action in _slots:
		var slot: BarSlot = _slots[action]
		slot.key_text = GemText.key_label(action)      # follows rebinding instantly
		slot.tick(delta)
		if slot.skill != null:
			var charge := ""
			var script_support := ProgramSupport.of(slot.skill)
			if script_support != null:
				charge = script_support.registers_badge()       # [2]: enemies in the script's registry
			if VariableStoreSupport.on_skill(slot.skill) and _skills != null:
				charge = str(VariableStoreSupport.read(_skills.get_parent(), slot.skill))
			if TryExceptSupport.on_skill(slot.skill) and _skills != null:
				var errors := TryExceptSupport.stacks_of(_skills.get_parent(), slot.skill)
				if errors > 0:
					charge = "!%d" % errors                    # Try / Except stored errors
			var oc := OverclockSupport.on_skill(slot.skill)
			if oc != null and oc.current_stacks() > 0:
				charge = "x%d" % oc.current_stacks()          # Overclock stacks
			slot.badge = charge
			slot.mana_cost = slot.skill.get_mana_cost()
			slot.affordable = slot.skill.can_afford(_mana)
			slot.usable = slot.skill.weapon_allows(_equip)
	_update_hover()


## The bar ignores the mouse so clicks reach the game, which means no hover signals.
## Instead the mouse position is checked against each slot every frame.
func _update_hover() -> void:
	var action := _action_under_mouse()
	if action == _hover_action:
		return
	_hover_action = action
	for a in _slots:
		(_slots[a] as BarSlot).hovered = a == action
	if action == &"":
		_tip.visible = false
	else:
		_show_tip(action)


func _action_under_mouse() -> StringName:
	# A panel (inventory, skills menu...) under the mouse wins over the bar.
	# The full-screen SubViewportContainer (the game world) is always "hovered", so it doesn't count.
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and not (hovered is SubViewportContainer):
		return &""
	var mouse := get_global_mouse_position()
	for action in _slots:
		var slot: BarSlot = _slots[action]
		if slot.visible and slot.skill != null and slot.get_global_rect().has_point(mouse):
			return action
	return &""


func _show_tip(action: StringName) -> void:
	var parts: Array = []
	if _skills:
		var index: int = _skills.bindings.get(action, -1)
		if index >= 0 and index < _skills.sockets.size():
			parts = GemText.skill_tip(_skills.sockets[index], action)
	if parts.is_empty():
		_tip.visible = false
		return
	for child in _tip_box.get_children():
		_tip_box.remove_child(child)
		child.queue_free()

	var inner_w := _tip.custom_minimum_size.x - 24.0     # panel width minus its left/right margins
	for part in parts:                                    # each part is [text, colour, font size]
		var l := Label.new()
		l.text = part[0]
		if _font:
			l.add_theme_font_override("font", _font)
		l.add_theme_font_size_override("font_size", roundi(part[2] * font_scale))
		l.add_theme_color_override("font_color", part[1])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = inner_w                 # gives the wrap a width to work with
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip_box.add_child(l)
	if not parts.is_empty():
		var sk: SkillInstance = _skills.sockets[_skills.bindings.get(action, -1)].skill
		if sk and not sk.weapon_allows(_equip):
			parts.append(["", Color.WHITE, 5])
			parts.append(["REQUIRES: " + sk.required_weapons_text(), COL_WARN, 14])
	# Show it invisibly for one frame so the labels can wrap, then fit and place it
	_tip.size = Vector2(_tip.custom_minimum_size.x, 0.0)
	_tip.modulate.a = 0.0
	_tip.visible = true
	await get_tree().process_frame
	if _hover_action != action:                           # mouse moved away during the wait
		return
	_tip.reset_size()

	var slot: BarSlot = _slots[action]
	var ts := _tip.size
	var screen := get_viewport_rect().size
	var p := Vector2(slot.global_position.x + slot.size.x * 0.5 - ts.x * 0.5,
		slot.global_position.y - ts.y - 10.0)
	p.x = clampf(p.x, 8.0, maxf(8.0, screen.x - ts.x - 8.0))
	p.y = maxf(p.y, 8.0)
	_tip.global_position = p
	_tip.modulate.a = 1.0


## One square slot, drawn in the same chamfered style as the skills menu.
class BarSlot extends Control:
	var skill: SkillInstance:
		set(value):
			skill = value
			queue_redraw()
	var title := "":
		set(value):
			if value != title:
				title = value
				queue_redraw()
	var key_text := "":
		set(value):
			if value != key_text:
				key_text = value
				queue_redraw()
	var mana_cost := 0.0:
		set(value):
			if not is_equal_approx(value, mana_cost):
				mana_cost = value
				queue_redraw()
	var affordable := true:
		set(value):
			if value != affordable:
				affordable = value
				queue_redraw()
	var hovered := false:
		set(value):
			if value != hovered:
				hovered = value
				queue_redraw()
	var usable := true:
		set(value):
			if value != usable:
				usable = value
				queue_redraw()
	var accent := Color.WHITE
	var skill_col := Color.WHITE
	var warn_col := Color.RED
	var mana_col := Color.BLUE
	var font: Font
	var font_scale := 1.0

	## A small counter in the top-right corner (Variable Store's charge). "" = none.
	var badge := "":
		set(value):
			if value != badge:
				badge = value
				queue_redraw()
	## The skill's symbol (an ItemGlyph kind), drawn in place of the title. "" = show the title
	## (its first three letters).
	var glyph := "":
		set(value):
			if value != glyph:
				glyph = value
				queue_redraw()
	var _cd_left := 0.0
	var _cd_total := 0.0
	var _cd_text := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func start_cooldown(total: float, show_text: bool) -> void:
		_cd_total = maxf(total, 0.01)
		_cd_left = _cd_total
		_cd_text = show_text and total >= 1.5
		queue_redraw()

	func tick(delta: float) -> void:
		if _cd_left <= 0.0:
			return
		_cd_left = maxf(_cd_left - delta, 0.0)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := 9.0
		var poly := PackedVector2Array([
			Vector2(0, 0), Vector2(w - c, 0), Vector2(w, c),
			Vector2(w, h), Vector2(c, h), Vector2(0, h - c)])
		var outline := PackedVector2Array(poly)
		outline.append(poly[0])

		var has := skill != null
		var col := skill_col if has else accent
		draw_colored_polygon(poly, Color(0.02, 0.05, 0.09, 0.75))
		draw_colored_polygon(poly, Color(col, 0.18 if has else 0.04))
		var ok := affordable and usable
		var edge := col if (ok or not has) else warn_col
		if hovered:
			draw_polyline(outline, Color(edge, 0.25), 7.0, true)    # glow
		draw_polyline(outline, Color(edge, 0.9 if has else 0.25), 2.0, true)

		if has:
			var ink := Color(col, 1.0 if affordable else 0.45)
			var top := 18.0 * font_scale                 # clear of the key text
			var bottom := 14.0 * font_scale              # clear of the mana cost
			var area := Rect2(w * 0.16, top, w * 0.68, h - top - bottom)
			if glyph == "" or not ItemGlyph.draw(self, glyph, area, ink):
				draw_string(font, Vector2(0, h * 0.5 + 8.0), title, HORIZONTAL_ALIGNMENT_CENTER, w,
					roundi(20 * font_scale), ink)
			if mana_cost > 0.0:
				draw_string(font, Vector2(0, h - 6.0), GemText.num(mana_cost),
					HORIZONTAL_ALIGNMENT_RIGHT, w - 6.0, roundi(12 * font_scale),
					mana_col if affordable else warn_col)

		draw_string(font, Vector2(6.0, 16.0), key_text, HORIZONTAL_ALIGNMENT_LEFT, w - 8.0,
			roundi(13 * font_scale), Color(accent, 0.95 if has else 0.5))
		if has and badge != "":
			draw_string_outline(font, Vector2(0, 16.0), badge, HORIZONTAL_ALIGNMENT_RIGHT, w - 6.0,
				roundi(14 * font_scale), 4, Color(0, 0, 0, 0.85))
			draw_string(font, Vector2(0, 16.0), badge, HORIZONTAL_ALIGNMENT_RIGHT, w - 6.0,
				roundi(14 * font_scale), Color(1.0, 0.82, 0.30))

		if _cd_left > 0.0:
			var frac := clampf(_cd_left / _cd_total, 0.0, 1.0)
			draw_rect(Rect2(2.0, 2.0, w - 4.0, (h - 4.0) * frac), Color(0, 0, 0, 0.6))
			if _cd_text:
				draw_string(font, Vector2(0, h * 0.5 + 7.0), "%.1f" % _cd_left,
					HORIZONTAL_ALIGNMENT_CENTER, w, roundi(18 * font_scale), Color.WHITE)
		if has and not usable:
			draw_rect(Rect2(2, 2, w - 4, h - 4), Color(0, 0, 0, 0.45))
			draw_line(Vector2(c, c), Vector2(w - c, h - c), Color(warn_col, 0.8), 2.0, true)
			draw_line(Vector2(w - c, c), Vector2(c, h - c), Color(warn_col, 0.8), 2.0, true)
