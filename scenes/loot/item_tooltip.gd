class_name ItemTooltip
extends PanelContainer
## Floating item card in the same retro-futuristic style as the inventory panel.
## It ignores the mouse completely so it never blocks clicks. Create it once,
## then call show_item() / hide_item(), and move it by setting `position`.

@export var accent := Color("#00E5FF")
@export var font: Font                          # leave empty to use the Courier Prime font below
@export var font_scale: float = 1.0
@export var tooltip_width: float = 340.0
@export_range(0.0, 1.0, 0.01) var bg_opacity: float = 0.92

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const CHAMFER := 16.0

const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_WARN := Color(1.0, 0.30, 0.37)
const COL_AFFIX := Color(0.45, 0.75, 1.0)

const RARITY_COLORS := {
	"normal": Color(0.85, 0.96, 1.0),
	"magic": Color(0.30, 0.64, 1.0),
	"rare": Color(1.0, 0.82, 0.30),
	"champion": Color(1.0, 0.45, 0.15),
}

var _font: Font
var _box: VBoxContainer
var _item: ItemInstance
var _equip: EquipmentComponent
var _hint := ""
var _hint_warn := false
var _ids := false                               # holding ALT shows affix ids, like the inventory


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	custom_minimum_size.x = tooltip_width

	var pad := StyleBoxEmpty.new()              # the chamfered frame is drawn in _draw()
	pad.content_margin_left = 18
	pad.content_margin_right = 18
	pad.content_margin_top = 14
	pad.content_margin_bottom = 14
	add_theme_stylebox_override("panel", pad)

	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 3)
	add_child(_box)
	visible = false


func show_item(item: ItemInstance, equipment: EquipmentComponent = null) -> void:
	var ids := Input.is_key_pressed(KEY_ALT)
	if visible and item == _item and ids == _ids:
		return                                  # nothing changed, don't rebuild every frame
	_item = item
	_equip = equipment
	_ids = ids
	_rebuild()
	visible = true


func hide_item() -> void:
	_item = null
	visible = false


## Bottom line, e.g. "LEFT CLICK TO PICK UP". warn = true draws it in red.
func set_hint(text: String, warn: bool = false) -> void:
	if text == _hint and warn == _hint_warn:
		return
	_hint = text
	_hint_warn = warn
	if _item != null:
		_rebuild()


func _rebuild() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	if _item == null:
		return

	var def := _item.definition
	var rarity_col: Color = RARITY_COLORS.get(_item.rarity, COL_TEXT)

	var name_l := _label(_item.get_display_name().to_upper(), 22, rarity_col)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(name_l)
	_box.add_child(_label("%s  //  %s" % [ItemText.type_name(def), _item.rarity.to_upper()], 14, COL_DIM))
	_box.add_child(_label("ITEM LEVEL  %d" % _item.item_level, 14, COL_DIM))

	var slot: int = def.get_slot()
	var current: ItemInstance = _equip.get_equipped(slot) if (_equip != null and slot >= 0) else null
	if current != null:
		_box.add_child(_label("REPLACES  " + current.get_display_name().to_upper(), 13, COL_DIM))

	var lines := ItemText.base_lines(def.base_stats)
	if not lines.is_empty() or not _item.rolled_affixes.is_empty():
		_box.add_child(_rule())
	for text in lines:
		_box.add_child(_label(text, 17, COL_TEXT))
	if not lines.is_empty() and not _item.rolled_affixes.is_empty():
		_box.add_child(_rule())
	for entry in _item.rolled_affixes:
		if _ids:                                   # ALT: the modifier's id, small and dim, over it
			var a: AffixDefinition = entry["affix"]
			_box.add_child(_label(a.id, 11, Color(COL_DIM, 0.6)))
		var l := _label(ItemText.affix_text(entry), 16, COL_AFFIX)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_box.add_child(l)

	if _hint != "":
		_box.add_child(_rule())
		var h := _label(_hint, 14, COL_WARN if _hint_warn else accent)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_box.add_child(h)

	reset_size.call_deferred()                  # shrink to fit the new content


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Chamfers on the top-right and bottom-left, same as the inventory panel
	var poly := PackedVector2Array([
		Vector2(0, 0), Vector2(w - CHAMFER, 0), Vector2(w, CHAMFER),
		Vector2(w, h), Vector2(CHAMFER, h), Vector2(0, h - CHAMFER)])
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


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(accent, 0.5)
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
