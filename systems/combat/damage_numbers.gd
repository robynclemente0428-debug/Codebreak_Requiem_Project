class_name DamageNumbers
extends Control
## Floating damage numbers, drawn at full screen resolution.
##
## Same trick as LootLabels: the world renders in a small pixelated SubViewport, so the numbers
## are normal 2D Labels in the HUD. Each frame the overlay projects the point where the hit
## happened through the world camera, so a number stays glued to the world while the camera moves.
##
## Setup: add a plain Control to the Hud CanvasLayer and attach this script.
## Then call track(enemy.health) for every enemy (the populator does it), and
## track(health, true) for the player if you want to see damage you take.

const DEFAULT_FONT := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"

@export var container: SubViewportContainer     # leave empty to find "SubViewportContainer" automatically
@export var font: Font

@export_group("Look")
@export var font_size: int = 22
@export var outline_size: int = 6
@export var enemy_color := Color(1.0, 0.92, 0.55)
@export var player_color := Color(1.0, 0.30, 0.37)
## Co-op: another player's hits on enemies (ours keep enemy_color): a cool colour, a bit smaller
## and fainter, so your own numbers stay the ones that stand out.
@export var ally_color := Color(0.55, 0.78, 1.0)
@export_range(0.3, 1.0, 0.05) var ally_scale: float = 0.8
@export_range(0.0, 1.0, 0.05) var ally_opacity: float = 0.8
@export_range(0.0, 1.0, 0.05) var opacity: float = 1.0
## Big hits (a large share of the target's max life) are drawn up to this many times larger.
@export var big_hit_scale: float = 1.7

@export_group("Motion")
@export var duration: float = 0.9               # seconds on screen
@export var rise_px: float = 70.0               # how far a number floats up
@export var spread_px: float = 22.0             # random sideways offset so hits don't stack exactly
@export var head_height: float = 1.8            # metres above the target's feet where numbers start

@export_group("Limits")
@export var show_enemy_damage: bool = true
@export var show_player_damage: bool = true
@export var max_active: int = 60                # oldest numbers are dropped past this

var _viewport: SubViewport
var _entries: Array[Dictionary] = []
var _font: Font
## Labels are reused: a hidden one waits here for the next number instead of being freed, and
## their look is a shared LabelSettings per size and colour (no theme overrides per label), so
## dozens of hits a second don't build dozens of Controls.
var _pool: Array[Label] = []
var _settings: Dictionary = {}               # "size|colour" -> LabelSettings


func _enter_tree() -> void:
	add_to_group("damage_numbers")


func _ready() -> void:
	Settings.bind_to(self, &"show_enemy_damage", "gameplay", "enemy_damage_numbers")
	Settings.bind_to(self, &"show_player_damage", "gameplay", "player_damage_numbers")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = font
	if _font == null and ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)
	if container == null:
		container = get_tree().current_scene.find_child("SubViewportContainer", true, false) as SubViewportContainer
	if container == null:
		push_warning("DamageNumbers: no SubViewportContainer found, assign the Container export")
		return
	for child in container.get_children():
		if child is SubViewport:
			_viewport = child
			break


## Starts showing a number whenever this HealthComponent takes damage.
func track(health: HealthComponent, is_player: bool = false) -> void:
	if health == null:
		return
	health.damage_taken.connect(_on_damage.bind(health, is_player))
	health.damage_shown.connect(_on_damage.bind(health, is_player))   # co-op: a hit another machine applied


func _on_damage(amount: float, health: HealthComponent, is_player: bool) -> void:
	if is_player and not show_player_damage:
		return
	if not is_player and not show_enemy_damage:
		return
	if _viewport == null or not is_instance_valid(health):
		return
	var target := health.get_parent() as Node3D
	if target == null:
		return

	var max_hp := 1.0
	if health.stats != null:
		max_hp = maxf(health.stats.get_stat(StatTypes.Stat.MAX_HEALTH), 1.0)
	var weight := clampf(amount / max_hp * 4.0, 0.0, 1.0)        # 0 = tiny hit, 1 = big hit

	# Co-op: another player's hit on an enemy looks like an ally's (Coop.damage_by is set around it)
	var ally := not is_player and Coop.damage_by_other()
	var colour := player_color if is_player else enemy_color
	var size_mult := lerpf(1.0, big_hit_scale, weight)
	if ally:
		colour = Color(ally_color, ally_color.a * ally_opacity)
		size_mult *= ally_scale
	var label := _take_label(_format(amount), _size_px(size_mult), colour)
	_entries.append({
		"label": label,
		"world": target.global_position + Vector3.UP * head_height,   # fixed point in the world
		"age": 0.0,
		"dx": randf_range(-spread_px, spread_px),
		"half": label.size * 0.5,
	})


func _process(delta: float) -> void:
	if _viewport == null or container == null or _entries.is_empty():
		return
	var cam := _viewport.get_camera_3d()
	if cam == null:
		return
	var ratio := container.size / Vector2(_viewport.size)

	for i in range(_entries.size() - 1, -1, -1):
		var e: Dictionary = _entries[i]
		var label: Label = e["label"]
		e["age"] += delta
		var dur: float = e.get("dur", duration)
		if e["age"] >= dur:
			_release(label)
			_entries.remove_at(i)
			continue

		var world: Vector3 = e["world"]
		if cam.is_position_behind(world):
			label.visible = false
			continue
		label.visible = true

		var t: float = e["age"] / dur
		var rise := rise_px * (1.0 - pow(1.0 - t, 3.0))            # fast at first, then slows
		var base := cam.unproject_position(world) * ratio + container.global_position
		var half: Vector2 = e["half"]
		label.position = (base + Vector2(e["dx"], -rise) - half).round()
		label.pivot_offset = half
		label.scale = Vector2.ONE * (1.0 + 0.35 * maxf(0.0, 1.0 - t * 8.0))   # quick pop on hit
		label.modulate.a = opacity * (1.0 if t < 0.6 else 1.0 - (t - 0.6) / 0.4)


## Floating gold "+12 CR" at a world point (credits from kills and props).
func pop_credits(world_pos: Vector3, amount: int) -> void:
	pop_text(world_pos, "+%s CR" % _format(amount), Color(1.0, 0.82, 0.30), 1.15)


## Any floating text at a world point, with the same rise-and-fade as damage numbers.
## `seconds` > 0: how long this one stays on screen (default `duration`), for text meant to be read.
func pop_text(world_pos: Vector3, text: String, color: Color, size_mult := 1.0, seconds := 0.0) -> void:
	if _viewport == null:
		return
	var label := _take_label(text, _size_px(size_mult), color)
	_entries.append({
		"label": label,
		"world": world_pos,
		"age": 0.0,
		"dx": 0.0,
		"half": label.size * 0.5,
		"dur": seconds if seconds > 0.0 else duration,
	})


## A hidden label showing `text`, reused from the pool when one is free. Makes room first when
## max_active numbers are already up (the oldest goes).
## Text sizes, as multiples of font_size: normal, credits, a big hit, the biggest. Every number
## snaps to the nearest one: each font size has its own glyphs to rasterize the first time it's
## drawn, so a handful of sizes (warmed up by prewarm) beats a new size for every hit.
func _size_steps() -> Array[float]:
	return [1.0, 1.15, (1.0 + big_hit_scale) * 0.5, big_hit_scale]


func _size_px(mult: float) -> int:
	var best := 1.0
	for s in _size_steps():
		if absf(s - mult) < absf(best - mult):
			best = s
	return roundi(font_size * best)


## Draws every digit (and ",+CR") once at each size and colour, nearly transparent, so their
## glyphs are rasterized while the area loads (EffectWarmup) and not in the first fight.
func prewarm() -> void:
	for col in [enemy_color, player_color, Color(1.0, 0.82, 0.30)]:
		for s in _size_steps():
			var label := _take_label("0123456789,+ CR", roundi(font_size * s), col)
			label.position = Vector2(4, 4)
			label.modulate.a = 0.004                 # drawn (so rasterized), not seen
			label.visible = true
			get_tree().create_timer(0.5, true).timeout.connect(_release.bind(label))


func _take_label(text: String, size_px: int, color: Color) -> Label:
	if _entries.size() >= max_active:
		var oldest: Dictionary = _entries.pop_front()
		_release(oldest["label"])
	var label: Label = _pool.pop_back() if not _pool.is_empty() else null
	if label == null:
		label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
	label.visible = false
	label.scale = Vector2.ONE
	label.modulate.a = 1.0
	label.label_settings = _settings_for(size_px, color)
	label.text = text
	label.size = Vector2.ZERO
	label.size = label.get_combined_minimum_size()
	return label


func _release(label: Label) -> void:
	if not is_instance_valid(label):
		return
	label.visible = false
	if _pool.size() < max_active:
		_pool.append(label)
	else:
		label.queue_free()


## One LabelSettings per size and colour, shared by every label that looks like that.
func _settings_for(size_px: int, color: Color) -> LabelSettings:
	var key := "%d|%s" % [size_px, color.to_html()]
	if not _settings.has(key):
		var ls := LabelSettings.new()
		ls.font = _font
		ls.font_size = size_px
		ls.font_color = color
		ls.outline_color = Color(0, 0, 0, 0.9)
		ls.outline_size = outline_size
		_settings[key] = ls
	return _settings[key]


## 1234 -> "1,234"
func _format(amount: float) -> String:
	var s := str(maxi(roundi(amount), 1))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.left(s.length() - 3)
	return s + out
