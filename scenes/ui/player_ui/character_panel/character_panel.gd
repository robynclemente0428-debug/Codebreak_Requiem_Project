class_name CharacterPanel
extends Control
## Retro-futuristic character sheet. Press C to slide it open from the left.
## It builds its whole UI in code, so there is nothing to set up in the scene tree:
## add a plain Control, attach this script, and call bind() from the player.
##
## To show another stat, add a line to ROWS below.

@export var toggle_key: Key = KEY_C
@export var panel_width: float = 620.0
@export_range(0.0, 1.0, 0.01) var bg_opacity: float = 0.88
@export var font_scale: float = 1.0
@export var font: Font                          # leave empty to use the Courier Prime font below
@export var accent := Color("#00E5FF")
@export var debug_stats := false                # prints what the panel is bound to when it opens
@export var debug_clicks := false               # prints which Control is under the mouse on every click

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const OPEN_X := 32.0
const CHAMFER := 24.0
const TAB_NAMES := ["Offence", "Defence", "Misc"]
const NAME_FONT_MAX := 30       # the name shrinks from this size...
const NAME_FONT_MIN := 18       # ...down to this, then gets cut off with "..."

const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_LIFE := Color(1.0, 0.30, 0.37)
const COL_MANA := Color(0.30, 0.64, 1.0)
const COL_RANK := Color(1.0, 0.82, 0.30)        # gold, like a ready quest
const COL_STR := Color(1.0, 0.30, 0.37)
const COL_DEX := Color(0.30, 1.0, 0.60)
const COL_INT := Color(0.30, 0.64, 1.0)

## One line per displayed stat.
##   tab:   0 = Offence, 1 = Defence, 2 = Misc
##   stats: the stat (two stats for a "range")
##   fmt:   "int"   -> 280
##          "dec"   -> 1.4
##          "pct"   -> 0.05 shows as 5.0%      (use this if the stat is stored as a fraction)
##          "mult"  -> 1.5 shows as x1.50
##          "range" -> min - max
##   mul:   optional, multiplies the value before display
const ROWS := [
	{"tab": 0, "label": "Attack Damage", "stats": [StatTypes.Stat.MIN_ATTACK_DAMAGE, StatTypes.Stat.MAX_ATTACK_DAMAGE], "fmt": "range"},
	{"tab": 0, "label": "Attacks per Second", "stats": [StatTypes.Stat.ATTACK_SPEED], "fmt": "dec"},
	{"tab": 0, "label": "Critical Strike Chance", "stats": [StatTypes.Stat.CRIT_CHANCE], "fmt": "pct"},
	{"tab": 0, "label": "Critical Strike Multiplier", "stats": [StatTypes.Stat.CRIT_MULTIPLIER], "fmt": "mult"},
	{"tab": 0, "label": "Life on Hit", "stats": [StatTypes.Stat.LIFE_ON_HIT], "fmt": "dec"},
	{"tab": 0, "label": "Skill Damage Multiplier", "stats": [StatTypes.Stat.SKILL_DAMAGE_MULT], "fmt": "mult"},

	{"tab": 1, "label": "Maximum Life", "stats": [StatTypes.Stat.MAX_HEALTH], "fmt": "int"},
	{"tab": 1, "label": "Armour", "stats": [StatTypes.Stat.ARMOUR], "fmt": "int"},
	# HealthComponent subtracts ARMOUR * 0.1 from every hit, so this shows that number
	{"tab": 1, "label": "Flat Damage Reduction", "stats": [StatTypes.Stat.ARMOUR], "fmt": "dec", "mul": 0.1},
	{"tab": 1, "label": "Regeneration", "stats": [StatTypes.Stat.REGENERATION], "fmt": "int"},
	{"tab": 2, "label": "Movement Speed", "stats": [StatTypes.Stat.MOVE_SPEED], "fmt": "dec"},
	{"tab": 2, "label": "Maximum Mana", "stats": [StatTypes.Stat.MANA], "fmt": "int"},
	{"tab": 2, "label": "Mana on Hit", "stats": [StatTypes.Stat.MANA_ON_HIT], "fmt": "dec"},
	{"tab": 2, "label": "Mana Regeneration", "stats": [StatTypes.Stat.MANA_REGEN], "fmt": "dec"},
]

var _font: Font
var _stats: StatComponent
var _health: HealthComponent

var _built := false
var _open := false
## Co-op: another player's sheet shown instead of ours (PartyMenu INFO -> inspect), as their own
## machine sent it (Coop.my_sheet): {name, class_id, level, rank, grade, life, stats {id: value}}.
## Cleared when the panel closes; C then opens our own again.
var _inspect: Dictionary = {}
var _inspect_peer := 0
var _tab := 0
var _tween: Tween
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _changed_mouse_mode := false

var _portrait: TextureRect
var _name_label: Label
var _sub_label: Label
var _rank_label: Label                # Executor rank (Ranks), and the next one to earn
var _life_label: Label
var _mana_label: Label
var _badges: Array[AttrBadge] = []
var _scroll: ScrollContainer
var _rows_box: VBoxContainer
var _value_labels: Array[Label] = []
var _row_defs: Array = []


# Joined in _enter_tree so the player can find the panel even if it readies first
func _enter_tree() -> void:
	add_to_group("character_panel")

func is_open() -> bool:
	return _open

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	_layout()
	_build_ui()
	_built = true
	visible = false


func _layout() -> void:
	# Docked to the left edge, full height with a margin
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = OPEN_X
	offset_right = OPEN_X + panel_width
	offset_top = 32.0
	offset_bottom = -32.0


# ---------- PUBLIC ----------
func bind(stats: StatComponent, health: HealthComponent = null) -> void:
	if _stats and _stats.stats_changed.is_connected(_on_changed):
		_stats.stats_changed.disconnect(_on_changed)
	if _health and _health.health_changed.is_connected(_on_changed):
		_health.health_changed.disconnect(_on_changed)
	_stats = stats
	_health = health
	if _stats:
		_stats.stats_changed.connect(_on_changed)
	if _health:
		_health.health_changed.connect(_on_changed)
	if _open:
		_update_values()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## Co-op: shows another player's sheet (`info`, from Coop.my_sheet on their machine). Called
## again with fresh numbers while it stays open.
func inspect(peer: int, info: Dictionary) -> void:
	if not info.get("stats") is Dictionary:
		return
	_inspect = info
	_inspect_peer = peer
	if _open:
		_refresh_header()
		_update_values()
	else:
		open()


## The other player whose sheet is showing (0 = our own, or closed).
func inspected_peer() -> int:
	return _inspect_peer if _open and not _inspect.is_empty() else 0


func open() -> void:
	if _open or not _built:
		return
	_open = true
	# A captured or hidden cursor can't click UI, so show it while the panel is open
	var mode := Input.mouse_mode
	if mode == Input.MOUSE_MODE_CAPTURED or mode == Input.MOUSE_MODE_HIDDEN \
			or mode == Input.MOUSE_MODE_CONFINED_HIDDEN:
		_prev_mouse_mode = mode
		_changed_mouse_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _stats == null and _inspect.is_empty():
		push_warning("CharacterPanel: no StatComponent bound. Is bind() being called from the player?")
	elif debug_stats:
		print("[CharacterPanel] bound to ", _stats, " | base_stats: ", _stats.base_stats)
	_refresh_header()
	_update_values()
	if not visible:
		position.x = -(panel_width + OPEN_X + 20.0)
		modulate.a = 0.0
		visible = true
	_play_slide(true)


func close() -> void:
	if not _open:
		return
	_open = false
	_inspect = {}                       # next time: our own sheet
	_inspect_peer = 0
	if _changed_mouse_mode:
		Input.mouse_mode = _prev_mouse_mode
		_changed_mouse_mode = false
	_play_slide(false)


## Debug helper: shows what is actually under the mouse when you click.
func _input(event: InputEvent) -> void:
	if debug_clicks and event is InputEventMouseButton and event.pressed:
		print("[CharacterPanel] click on: ", get_viewport().gui_get_hovered_control())


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == toggle_key:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _open:
		close()
		get_viewport().set_input_as_handled()


func _on_changed(_a = null, _b = null) -> void:
	if _open:
		_update_values()


func _play_slide(opening: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	var target_x := OPEN_X if opening else -(panel_width + OPEN_X + 20.0)
	_tween.tween_property(self, "position:x", target_x, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0 if opening else 0.0, 0.18)
	if not opening:
		_tween.finished.connect(_on_slide_finished)


func _on_slide_finished() -> void:
	if not _open:
		visible = false


# ---------- BUILDING THE UI ----------
var _passive_box: PanelContainer
var _passive_title: Label
var _passive_desc: Label


func _build_ui() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	# Title bar
	var title_row := HBoxContainer.new()
	col.add_child(title_row)
	var title := _label("// CHARACTER //", 26, accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn := _button("X", 20)
	close_btn.custom_minimum_size = Vector2(44, 36)
	close_btn.pressed.connect(close)
	title_row.add_child(close_btn)
	col.add_child(_rule())

	# Portrait, name, life and mana
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	col.add_child(head)

	var frame := PanelContainer.new()
	var frame_style := _flat(Color(0, 0, 0, 0.35), accent, 2)
	frame_style.set_content_margin_all(3)
	frame.add_theme_stylebox_override("panel", frame_style)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(104, 104)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_portrait)
	head.add_child(frame)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	_name_label = _label("", 30, COL_TEXT)
	# A long name must never widen the panel: with clip_text the label's minimum width
	# is 0, so it can't push the tabs and stat rows past the edge.
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.custom_minimum_size.x = 0.0
	_sub_label = _label("", 16, accent)
	_rank_label = _label("", 15, COL_RANK)
	_life_label = _label("", 19, COL_LIFE)
	_mana_label = _label("", 19, COL_MANA)
	for l in [_name_label, _sub_label, _rank_label, _life_label, _mana_label]:
		info.add_child(l)

	# Attribute dials
	var attr_row := HBoxContainer.new()
	attr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	attr_row.add_theme_constant_override("separation", 34)
	col.add_child(attr_row)
	var dials := [["STR", COL_STR], ["DEX", COL_DEX], ["INT", COL_INT]]
	for d in dials:
		var badge := AttrBadge.new()
		badge.title = d[0]
		badge.color = d[1]
		badge.font = _font if _font else ThemeDB.fallback_font
		attr_row.add_child(badge)
		_badges.append(badge)

	# Class passive (filled in _refresh_header, hidden if the class has none)
	_passive_box = PanelContainer.new()
	var pstyle := _flat(Color(0, 0, 0, 0.30), Color(accent, 0.35), 1)
	pstyle.content_margin_left = 14
	pstyle.content_margin_right = 14
	pstyle.content_margin_top = 8
	pstyle.content_margin_bottom = 10
	_passive_box.add_theme_stylebox_override("panel", pstyle)
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 4)
	_passive_box.add_child(pcol)
	_passive_title = _label("", 16, accent)
	pcol.add_child(_passive_title)
	_passive_desc = _label("", 15, COL_TEXT)
	_passive_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_passive_desc.custom_minimum_size.x = 100.0
	pcol.add_child(_passive_desc)
	_passive_box.visible = false
	col.add_child(_passive_box)

	# Tabs and the stat list
	col.add_child(_build_tabs())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(_scroll.get_v_scroll_bar())
	col.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 2)
	_scroll.add_child(_rows_box)

	var hint := _label("[ %s ]  CLOSE" % OS.get_keycode_string(toggle_key), 14, COL_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(hint)

	# Scanlines go on top of everything
	var overlay := ScanOverlay.new()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_rows()


func _build_tabs() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for i in TAB_NAMES.size():
		var b := _button(String(TAB_NAMES[i]).to_upper(), 18)
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 42
		b.toggled.connect(_on_tab_toggled.bind(i))
		box.add_child(b)
		if i == 0:
			b.set_pressed_no_signal(true)
	return box


func _on_tab_toggled(on: bool, index: int) -> void:
	if not on:
		return
	_tab = index
	_build_rows()
	_update_values()


func _build_rows() -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_value_labels.clear()
	_row_defs.clear()

	var idx := 0
	for row in ROWS:
		if row["tab"] != _tab:
			continue
		var even := idx % 2 == 0
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _row_style(even, false))
		panel.mouse_entered.connect(func() -> void:
			panel.add_theme_stylebox_override("panel", _row_style(even, true)))
		panel.mouse_exited.connect(func() -> void:
			panel.add_theme_stylebox_override("panel", _row_style(even, false)))

		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_l := _label(String(row["label"]).to_upper(), 17, COL_DIM)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_l := _label("", 19, COL_TEXT)
		value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(name_l)
		hb.add_child(value_l)
		panel.add_child(hb)
		_rows_box.add_child(panel)

		_value_labels.append(value_l)
		_row_defs.append(row)
		idx += 1


# ---------- FILLING IN THE DATA ----------
func _refresh_header() -> void:
	if not _inspect.is_empty():
		_refresh_inspect_header()
		return
	var data: Dictionary = {}
	if not SaveManager.party.is_empty():
		data = SaveManager.get_data(SaveManager.party[0])

	var char_name := String(data.get("name", "Unknown")).to_upper()
	_name_label.text = char_name
	_fit_name(char_name)
	_name_label.add_theme_color_override("font_color", COL_TEXT)

	var class_id := String(data.get("class_id", ""))
	var class_text := class_id.capitalize()
	_portrait.texture = null
	var path := "res://data/classes/%s.tres" % class_id
	if class_id != "" and ResourceLoader.exists(path):
		var c := load(path) as ClassData
		if c:
			class_text = c.display_name
			_portrait.texture = c.icon
			_name_label.add_theme_color_override("font_color", c.accent_color)

	_sub_label.text = class_text.to_upper()

	var player := get_tree().get_first_node_in_group("players")
	var qm: QuestManager = player.get("quests") if player != null else null
	var next_rank := Ranks.next(qm)
	_rank_label.text = "RANK  %s" % Ranks.current(qm)
	var grade := Ranks.grade(qm)
	if grade != "":
		_rank_label.text += " (%s)" % grade
	if next_rank != "":
		_rank_label.text += "  ·  NEXT: %s" % next_rank
	var tip := PackedStringArray()
	var held := Ranks.index_of(qm)
	for r in range(1, held + 1):
		for line in Ranks.unlock_lines(r):
			tip.append("  + " + line)
	if not tip.is_empty():
		tip.insert(0, "Your rank unlocks:")
	if next_rank != "":
		tip.append("Next rank: %s. Pass Examiner Sudo's exam." % next_rank)
		for line in Ranks.unlock_lines(held + 1):
			tip.append("  + " + line)
	else:
		tip.append("Highest rank.")
	for r in Ranks.waiting(qm):
		tip.append("%s exam passed: it counts once you reach %s." % [r, r])
	_rank_label.tooltip_text = "\n".join(tip)
	_rank_label.mouse_filter = Control.MOUSE_FILTER_PASS        # so the tooltip shows

	var t := ClassTrait.for_class(class_id)
	_passive_box.visible = t != null
	if t != null:
		_passive_title.text = "PASSIVE  //  %s" % t.display_name.to_upper()
		_passive_desc.text = t.description


## Co-op: the header for another player's sheet (_inspect): their name, class, level and rank.
func _refresh_inspect_header() -> void:
	var char_name := str(_inspect.get("name", "Player")).to_upper()
	_name_label.text = char_name
	_fit_name(char_name)
	_name_label.add_theme_color_override("font_color", COL_TEXT)
	var class_id := str(_inspect.get("class_id", ""))
	var class_text := class_id.capitalize()
	_portrait.texture = null
	var path := "res://data/classes/%s.tres" % class_id
	if class_id != "" and ResourceLoader.exists(path):
		var c := load(path) as ClassData
		if c:
			class_text = c.display_name
			_portrait.texture = c.icon
			_name_label.add_theme_color_override("font_color", c.accent_color)
	_sub_label.text = "%s  ·  LV %d  ·  ANOTHER PLAYER" % [class_text.to_upper(), int(_inspect.get("level", 1))]
	_rank_label.text = "RANK  %s" % str(_inspect.get("rank", "?"))
	if str(_inspect.get("grade", "")) != "":
		_rank_label.text += " (%s)" % str(_inspect.get("grade", ""))
	_rank_label.tooltip_text = ""
	var t := ClassTrait.for_class(class_id)
	_passive_box.visible = t != null
	if t != null:
		_passive_title.text = "PASSIVE  //  %s" % t.display_name.to_upper()
		_passive_desc.text = t.description


## Shrinks the name's font until it fits next to the portrait.
func _fit_name(text: String) -> void:
	# panel width minus margins (56), portrait (110) and the gap between them (18), with a little spare
	var avail := panel_width - 190.0
	var f: Font = _font if _font else ThemeDB.fallback_font
	var fs := roundi(NAME_FONT_MAX * font_scale)
	var min_fs := roundi(NAME_FONT_MIN * font_scale)
	while fs > min_fs and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
		fs -= 1
	_name_label.add_theme_font_size_override("font_size", fs)


func _update_values() -> void:
	# Life and mana under the name
	if _stats == null and _inspect.is_empty():
		_life_label.text = "LIFE   --"
		_mana_label.text = "MANA   --"
	else:
		var max_hp := _stat(StatTypes.Stat.MAX_HEALTH)
		var cur_hp := _health.current_health if _health else max_hp
		if not _inspect.is_empty():
			cur_hp = float(_inspect.get("life", max_hp))   # another player's, as they sent it
		var max_shown := roundi(max_hp)
		_life_label.text = "LIFE   %d / %d" % [mini(ceili(cur_hp), max_shown), max_shown]
		_mana_label.text = "MANA   %d" % roundi(_stat(StatTypes.Stat.MANA))

	# Attribute dials show the live values (class base + any bonuses),
	# not the starting values stored in the save file.
	var attr_stats := [StatTypes.Stat.STRENGTH, StatTypes.Stat.DEXTERITY, StatTypes.Stat.INTELLIGENCE]
	for i in _badges.size():
		_badges[i].set_value(roundi(_stat(attr_stats[i])))

	# Stat rows. A value that changed flashes white.
	for i in _row_defs.size():
		var text := _format(_row_defs[i])
		var lbl := _value_labels[i]
		if lbl.text == text:
			continue
		var had_value := lbl.text != ""
		lbl.text = text
		if had_value and _open:
			lbl.modulate = Color(2.4, 2.4, 2.4)
			lbl.create_tween().tween_property(lbl, "modulate", Color.WHITE, 0.45)


func _stat(stat: int) -> float:
	if not _inspect.is_empty():
		return float((_inspect["stats"] as Dictionary).get(stat, 0.0))   # another player's sheet
	if _stats == null:
		return 0.0
	return _stats.get_stat(stat as StatTypes.Stat)


func _format(row: Dictionary) -> String:
	if _stats == null and _inspect.is_empty():
		return "--"                 # not bound to a StatComponent yet
	var ids: Array = row["stats"]
	var v := _stat(ids[0]) * float(row.get("mul", 1.0))
	match row["fmt"]:
		"int":
			return str(roundi(v))
		"dec":
			return "%.1f" % v
		"pct":
			return "%.1f%%" % (v * 100.0)
		"mult":
			return "x%.2f" % v
		"range":
			return "%d - %d" % [roundi(v), roundi(_stat(ids[1]))]
	return str(v)


# ---------- STYLING HELPERS ----------
func _draw() -> void:
	var w := size.x
	var h := size.y
	var poly := PackedVector2Array([
		Vector2(CHAMFER, 0), Vector2(w, 0), Vector2(w, h - CHAMFER),
		Vector2(w - CHAMFER, h), Vector2(0, h), Vector2(0, CHAMFER)])
	draw_colored_polygon(poly, Color(0.02, 0.05, 0.09, bg_opacity))
	var outline := PackedVector2Array(poly)
	outline.append(poly[0])
	draw_polyline(outline, Color(accent, 0.18), 7.0, true)    # glow
	draw_polyline(outline, accent, 2.0, true)


func _label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", roundi(fsize * font_scale))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, fsize: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", roundi(fsize * font_scale))
	b.add_theme_color_override("font_color", COL_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _flat(Color(accent, 0.06), Color(accent, 0.35), 1))
	b.add_theme_stylebox_override("hover", _flat(Color(accent, 0.16), Color(accent, 0.8), 1))
	b.add_theme_stylebox_override("pressed", _flat(Color(accent, 0.28), accent, 2))
	b.add_theme_stylebox_override("hover_pressed", _flat(Color(accent, 0.28), accent, 2))
	return b


func _flat(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _row_style(even: bool, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var a := 0.07 if even else 0.0
	if hover:
		a = 0.18
		sb.border_color = accent
		sb.border_width_left = 3
	sb.bg_color = Color(accent, a)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(accent, 0.5)
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _style_scrollbar(bar: ScrollBar) -> void:
	bar.custom_minimum_size = Vector2(8, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(accent, 0.08)
	bar.add_theme_stylebox_override("scroll", track)
	for entry in [["grabber", 0.55], ["grabber_highlight", 0.85], ["grabber_pressed", 1.0]]:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(accent, entry[1])
		bar.add_theme_stylebox_override(entry[0], g)


# ---------- SMALL DRAWN WIDGETS ----------
## A glowing circular dial with a number, used for STR / DEX / INT.
class AttrBadge extends Control:
	var title := ""
	var value := 0
	var color := Color.WHITE
	var font: Font

	func _init() -> void:
		custom_minimum_size = Vector2(96, 118)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: int) -> void:
		value = v
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 48.0)
		var r := 40.0
		draw_circle(c, r, Color(color, 0.10))
		draw_arc(c, r, 0.0, TAU, 48, Color(color, 0.22), 9.0, true)    # glow
		draw_arc(c, r, 0.0, TAU, 48, color, 2.5, true)
		for i in 12:                                                     # dial ticks
			var dir := Vector2.from_angle(TAU * i / 12.0)
			draw_line(c + dir * (r + 5.0), c + dir * (r + 10.0), Color(color, 0.6), 2.0)
		draw_string(font, Vector2(0, c.y + 10.0), str(value),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color.WHITE)
		draw_string(font, Vector2(0, size.y - 4.0), title,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, color)


## CRT scanlines and a slow sweep drawn over the whole panel.
class ScanOverlay extends Control:
	var t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			t += delta
			queue_redraw()

	func _draw() -> void:
		var inset := 24.0
		var y := 2.0
		while y < size.y - 2.0:
			draw_line(Vector2(inset, y), Vector2(size.x - inset, y), Color(0, 0, 0, 0.13), 1.0)
			y += 3.0
		# The sweep stays inside the scanlines' band, so it never shows past the panel's edges
		var top := 2.0 + 4.0                          # half the sweep's 8 px thickness
		var band := maxf(size.y - 4.0 - 8.0, 1.0)
		var sweep_y := top + fposmod(t * 90.0, band)
		draw_line(Vector2(inset, sweep_y), Vector2(size.x - inset, sweep_y), Color(1, 1, 1, 0.05), 8.0)
