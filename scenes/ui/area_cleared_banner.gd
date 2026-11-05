class_name AreaClearedBanner
extends CanvasLayer
## The "AREA CLEARED" announcement: a band across the screen that opens, the title decoding out
## of scrambled binary, the area's name and what the clear gave. Then it fades out and frees
## itself. DungeonPopulator shows one when the last enemy of an instance dies.
##
##   AreaClearedBanner.announce(get_tree(), "The Spillway", "+1 SCRIPT POINT ON EVERY SKILL")

const FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const SOUND := "res://assets/sound/Start_Button_Click.wav"
const TITLE := "AREA CLEARED"
const COL_ACCENT := Color(0.45, 0.85, 1.0)
const COL_TITLE := Color(0.90, 0.98, 1.0)
const COL_NAME := Color(0.62, 0.80, 0.86)
const COL_REWARD := Color(0.45, 1.0, 0.6)
const COL_BAND := Color(0.02, 0.06, 0.09, 0.86)
const BAND_Y := 0.30                    # band centre, as a share of the screen height
const BAND_H := 170.0                   # px when open
# Timing, in seconds from the start
const OPEN := 0.25                      # band opens
const DECODE := 0.7                     # title finishes decoding
const HOLD := 3.6                       # starts fading
const FADE := 0.6

var _t := 0.0
var _band: Control
var _title: Label
var _name: Label
var _reward: Label


## Where the band ends (px from the top of the screen) while a banner is up, else -1. The quest
## tracker's messages (a beacon coming online, QUEST READY...) move below it meanwhile.
static func bottom_y(tree: SceneTree) -> float:
	for b in tree.get_nodes_in_group("area_cleared_banner"):
		var banner := b as AreaClearedBanner
		if banner != null and not banner.is_queued_for_deletion() and banner._band != null:
			var screen := banner._band.get_viewport_rect().size
			return screen.y * BAND_Y + BAND_H * 0.5
	return -1.0


## Shows the banner over the game. `reward` "" leaves the reward line out.
static func announce(tree: SceneTree, area_name: String, reward: String) -> void:
	for old in tree.get_nodes_in_group("area_cleared_banner"):
		old.queue_free()                    # never two at once
	var b := AreaClearedBanner.new()
	b.add_to_group("area_cleared_banner")
	tree.root.add_child(b)
	b._fill(area_name, reward)


func _init() -> void:
	layer = 15                              # over the world and name plates, under the HUD (20)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var font: Font = load(FONT) if ResourceLoader.exists(FONT) else null
	_band = Control.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.draw.connect(_draw_band)
	add_child(_band)
	_title = _label(font, 58, COL_TITLE)
	_name = _label(font, 22, COL_NAME)
	_reward = _label(font, 20, COL_REWARD)


func _label(font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l


func _fill(area_name: String, reward: String) -> void:
	_name.text = "// %s //" % area_name.to_upper()
	_reward.text = reward
	_reward.visible = reward != ""
	_layout()
	SoundManager.play_ui(SOUND, -4.0)


func _process(delta: float) -> void:
	_t += delta
	if _t >= HOLD + FADE:
		queue_free()
		return
	# The title decodes left to right: settled letters, then scrambled 0s and 1s
	var settled := int(clampf((_t - OPEN * 0.5) / (DECODE - OPEN * 0.5), 0.0, 1.0) * TITLE.length())
	var text := TITLE.substr(0, settled)
	for i in range(settled, TITLE.length()):
		text += " " if TITLE[i] == " " else ("1" if randf() < 0.5 else "0")
	_title.text = text
	var shown := clampf(_t / OPEN, 0.0, 1.0)
	var fade := 1.0 - clampf((_t - HOLD) / FADE, 0.0, 1.0)
	_title.modulate.a = shown * fade
	_name.modulate.a = clampf((_t - DECODE * 0.6) / 0.3, 0.0, 1.0) * fade
	_reward.modulate.a = clampf((_t - DECODE) / 0.3, 0.0, 1.0) * fade
	_band.modulate.a = fade
	_layout()
	_band.queue_redraw()


func _layout() -> void:
	var screen := _band.get_viewport_rect().size
	var cy := screen.y * BAND_Y
	_title.position = Vector2(0.0, cy - 66.0)
	_name.position = Vector2(0.0, cy + 6.0)
	_reward.position = Vector2(0.0, cy + 38.0)
	for l in [_title, _name, _reward]:
		l.size.x = screen.x


## The band: a dark strip with bright rules top and bottom, opening from its centre line, and a
## light sweep running across it while the title decodes.
func _draw_band() -> void:
	var screen := _band.get_viewport_rect().size
	var cy := screen.y * BAND_Y
	var open := ease(clampf(_t / OPEN, 0.0, 1.0), 0.4)
	var h := BAND_H * open
	var top := cy - h * 0.5 - 8.0
	_band.draw_rect(Rect2(0.0, top, screen.x, h), COL_BAND)
	for y in [top, top + h]:
		_band.draw_line(Vector2(0.0, y), Vector2(screen.x, y), Color(COL_ACCENT, 0.25), 7.0)   # glow
		_band.draw_line(Vector2(0.0, y), Vector2(screen.x, y), COL_ACCENT, 2.0)
	if _t < DECODE + 0.3:
		var x := screen.x * clampf(_t / (DECODE + 0.3), 0.0, 1.0)
		_band.draw_rect(Rect2(x - 60.0, top, 120.0, h), Color(COL_ACCENT, 0.10))
