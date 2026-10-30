extends Node
## Autoload: SoundManager
## Every sound in assets/sound, wired into the game in one place:
##   Music      menus -> MENU_MUSIC, towns -> TOWN_MUSIC, dungeons -> DUNGEON_MUSIC (crossfades)
##   Buttons    every Button in the game clicks when pressed (start / exit / normal click,
##              picked from the button's text). Give a button the meta "no_click_sound" to mute it.
##   Skills     each skill animation key plays a sound (SKILL_SOUNDS), for players and enemies
##   Footsteps  loop while the local player walks
##   Damage     TAKE_DAMAGE when a player or an enemy loses life (any HealthComponent)
##   Guns       a shot per trigger pull, by weapon type (GUN_SOUNDS), from ShootBehavior
##   Impacts    BLAST_IMPACT where a Blast explodes, from BlastBehavior
## Volumes follow the Settings menu through the Music / Effects / UI audio buses.
##
## To change what plays where, edit the constants below. Nothing else needs touching.

const MENU_MUSIC := "res://assets/sound/Main_Menu_BGM.wav"
const TOWN_MUSIC := "res://assets/sound/In-game_BGM.wav"
const DUNGEON_MUSIC := "res://assets/sound/BGM_2.ogg"

const CLICK := "res://assets/sound/Futuristic_Button_Click.wav"
const CLICK_START := "res://assets/sound/Start_Button_Click.wav"
const CLICK_EXIT := "res://assets/sound/Exit_Button_Click.mp3"
const FOOTSTEPS := "res://assets/sound/Footsteps.wav"
const TAKE_DAMAGE := "res://assets/sound/take_damage.wav"
const TAKE_DAMAGE_LENGTH := 0.45     # the file is 3.3 s but the hit is in the first 0.4 s
const PLAYER_HURT_DB := -4.0
const ENEMY_HURT_DB := -9.0
const HURT_COOLDOWN := 0.08          # per target: rapid multi-hits don't stack into noise

## Weapon type id -> [sound, volume dB]. Shots from a gun type not listed use DEFAULT_GUN.
const GUN_SOUNDS := {
	"assault_rifle": ["res://assets/sound/rifle_shot.wav", -6.0],
	"sniper": ["res://assets/sound/sniper_shot.wav", -4.0],
}
const DEFAULT_GUN := "assault_rifle"
const GUN_PITCH_JITTER := 0.06       # +/- pitch per shot, so rapid fire doesn't sound copy-pasted

const BLAST_IMPACT := "res://assets/sound/blast_impact_sound.wav"
const BLAST_IMPACT_DB := -5.0
const MAX_IMPACT_VOICES := 6         # loop repeats and enemy blasts can explode many at once

## Animation key -> [sound, seconds BEFORE the hit to start it (-1 = at once), volume dB]
## A skill gem's animation_keys decide which entry plays ("slash_r", "slam", "magic", ...).
const SKILL_SOUNDS := {
	"slash_l": ["res://assets/sound/Large_sword_swing.wav", 0.12, -4.0],
	"slash_r": ["res://assets/sound/Large_sword_swing.wav", 0.12, -4.0],
	"slam": ["res://assets/sound/Large_sword_swing.wav", 0.15, -2.0],
	"magic": ["res://assets/sound/Fireball_Casting_SFX.wav", -1.0, -6.0],
	"attack": ["res://assets/sound/Large_sword_swing.wav", 0.10, -10.0],   # enemy basic attacks
}

## Words in a button's text that pick the start or exit click (checked in this order).
const START_WORDS := ["PLAY", "START", "CREATE", "CONTINUE", "NEW GAME", "ENTER", "ACCEPT"]
const EXIT_WORDS := ["EXIT", "QUIT", "LEAVE", "MAIN MENU", "BACK", "CANCEL", "CLOSE", "DECLINE"]

const MUSIC_DB := -8.0
const CLICK_DB := -4.0
const FOOTSTEPS_DB := -12.0
const FADE_SEC := 1.2
const MAX_ENEMY_VOICES := 6         # a swarm of Glitchlings shouldn't drown everything out

var _music: Array[AudioStreamPlayer] = []
var _music_on := 0                  # which of the two players is the current track
var _music_path := ""
var _ui: AudioStreamPlayer
var _steps: AudioStreamPlayer
var _cache: Dictionary = {}         # path -> AudioStream
var _check := 0.0
var _enemy_voices := 0
var _impact_voices := 0
var _last_hurt: Dictionary = {}     # target instance id -> msec of its last hurt sound


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS         # music and clicks keep working while paused
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = _bus("Music")
		p.volume_db = -80.0
		p.finished.connect(p.play)                   # loop, whatever the file's import settings
		add_child(p)
		_music.append(p)
	_ui = _player("UI")
	_steps = _player("Effects")
	_steps.stream = _load(FOOTSTEPS)
	_steps.volume_db = FOOTSTEPS_DB
	_steps.finished.connect(_steps.play)
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().root.find_children("*", "", true, false):
		_on_node_added(n)                            # buttons / health that existed before we started


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		_update_music()
	_update_footsteps()


# ---------- MUSIC ----------
func _update_music() -> void:
	var am := get_tree().get_first_node_in_group("area_manager")
	if am == null:
		play_music(MENU_MUSIC)
		return
	var area = am.get("current_area")
	if area == null:
		return                                       # still loading the first area
	play_music(TOWN_MUSIC if area is TownArea or area.get("instance") == null else DUNGEON_MUSIC)


## Crossfades to `path`. Calling it with the track that's already playing does nothing.
func play_music(path: String) -> void:
	if path == _music_path:
		return
	_music_path = path
	var old := _music[_music_on]
	_music_on = 1 - _music_on
	var new := _music[_music_on]
	new.stream = _load(path)
	new.volume_db = -40.0
	if new.stream:
		new.play()
	var t := create_tween().set_parallel(true)
	t.tween_property(new, "volume_db", MUSIC_DB, FADE_SEC)
	t.tween_property(old, "volume_db", -80.0, FADE_SEC)
	t.chain().tween_callback(old.stop)


# ---------- BUTTONS ----------
func _on_node_added(node: Node) -> void:
	if node is HealthComponent:
		var hc := node as HealthComponent
		if not hc.damage_taken.is_connected(_on_damage_taken):
			hc.damage_taken.connect(_on_damage_taken.bind(hc))
		return
	if node is BaseButton and not node.has_meta("no_click_sound"):
		var b := node as BaseButton
		if not b.pressed.is_connected(_on_button_pressed):
			b.pressed.connect(_on_button_pressed.bind(b))


func _on_button_pressed(b: BaseButton) -> void:
	if not is_instance_valid(b) or b.has_meta("no_click_sound"):
		return
	var text := ""
	if b is Button:
		text = (b as Button).text.to_upper()
	var path := CLICK
	if START_WORDS.any(func(w: String) -> bool: return w in text):
		path = CLICK_START
	elif EXIT_WORDS.any(func(w: String) -> bool: return w in text) or text.strip_edges() == "X":
		path = CLICK_EXIT
	play_ui(path)


## Plays a menu sound. Safe across scene changes (this node never leaves the tree).
func play_ui(path: String, volume_db := CLICK_DB) -> void:
	_ui.stream = _load(path)
	_ui.volume_db = volume_db
	_ui.play()


# ---------- SKILLS ----------
## Called when a skill (or an enemy's basic attack, key "attack") starts its animation.
## `hit_in` is the seconds until the hit lands, so a swing whoosh can peak on the hit.
## The local player's sounds play flat; enemies' come from where they stand.
func play_skill(key: String, source: Node3D, hit_in: float) -> void:
	if not SKILL_SOUNDS.has(key) or not is_instance_valid(source):
		return
	var entry: Array = SKILL_SOUNDS[key]
	var lead: float = entry[1]
	var wait := 0.0 if lead < 0.0 else maxf(hit_in - lead, 0.0)
	if wait > 0.0:
		await get_tree().create_timer(wait, false).timeout
		if not is_instance_valid(source):
			return
	if source.is_in_group("players"):
		_play_flat(entry[0], entry[2])
	else:
		_play_at(source, entry[0], entry[2])


# ---------- GUNS AND IMPACTS ----------
## One gunshot for `shooter`, picked by the weapon it holds (GUN_SOUNDS). Players' shots play
## flat; anyone else's (enemies, holograms) come from where they stand.
func play_gunshot(shooter: Node3D) -> void:
	if not is_instance_valid(shooter):
		return
	var gun := DEFAULT_GUN
	var eq = shooter.get("equipment")
	if eq != null and eq.has_method("get_equipped"):
		var weapon = eq.get_equipped(EquipmentSlots.Slot.WEAPON)
		if weapon != null and weapon.definition.weapon_type != null \
				and GUN_SOUNDS.has(weapon.definition.weapon_type.id):
			gun = weapon.definition.weapon_type.id
	var entry: Array = GUN_SOUNDS[gun]
	var pitch := randf_range(1.0 - GUN_PITCH_JITTER, 1.0 + GUN_PITCH_JITTER)
	if shooter.is_in_group("players"):
		_play_flat(entry[0], entry[1], pitch)
	else:
		_play_at(shooter, entry[0], entry[1], pitch)


## The Blast explosion sound at a point in the world. `world` is any node in that 3D world
## (the cast's effect parent).
func play_blast_impact(world: Node, at: Vector3) -> void:
	play_at_point(world, at, BLAST_IMPACT, BLAST_IMPACT_DB, randf_range(0.94, 1.06))


## A one-off sound at a position (explosions and other things with no node to sit on).
## Respects MAX_IMPACT_VOICES.
func play_at_point(world: Node, at: Vector3, path: String, volume_db: float, pitch := 1.0) -> void:
	if _impact_voices >= MAX_IMPACT_VOICES or world == null or not is_instance_valid(world) \
			or not world.is_inside_tree():
		return
	var p3 := AudioStreamPlayer3D.new()
	p3.bus = _bus("Effects")
	p3.stream = _load(path)
	if p3.stream == null:
		p3.free()
		return
	p3.volume_db = volume_db
	p3.pitch_scale = pitch
	p3.unit_size = 8.0
	p3.max_distance = 40.0
	world.add_child(p3)
	p3.global_position = at
	_impact_voices += 1
	var done := func() -> void:
		if is_instance_valid(p3) and not p3.is_queued_for_deletion():
			_impact_voices -= 1
			p3.queue_free()
	p3.finished.connect(done)
	p3.tree_exiting.connect(func() -> void:          # the area was swapped mid-sound
		if not p3.is_queued_for_deletion():
			_impact_voices -= 1)
	p3.play()


# ---------- TAKING DAMAGE ----------
func _on_damage_taken(amount: float, hc: HealthComponent) -> void:
	if amount <= 0.0 or not is_instance_valid(hc):
		return
	var target := hc.get_parent() as Node3D
	if target == null or target.is_in_group(&"breakables"):
		return                                       # barrels don't scream
	var now := Time.get_ticks_msec()
	var key := target.get_instance_id()
	if now - int(_last_hurt.get(key, -100000)) < int(HURT_COOLDOWN * 1000.0):
		return
	_last_hurt[key] = now
	if target.is_in_group("players"):
		_play_flat(TAKE_DAMAGE, PLAYER_HURT_DB, randf_range(0.95, 1.05), TAKE_DAMAGE_LENGTH)
	else:
		_play_at(target, TAKE_DAMAGE, ENEMY_HURT_DB, randf_range(1.05, 1.25), TAKE_DAMAGE_LENGTH)


## A one-off sound with no position (the local player's own sounds).
## max_len > 0 cuts it off early (for files with long silent tails).
func _play_flat(path: String, volume_db: float, pitch := 1.0, max_len := 0.0) -> void:
	var p := _player("Effects")
	p.stream = _load(path)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	p.play()
	if max_len > 0.0:
		get_tree().create_timer(max_len, false).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.queue_free())


## A one-off sound coming from `source` (enemies). Respects MAX_ENEMY_VOICES.
func _play_at(source: Node3D, path: String, volume_db: float, pitch := 1.0, max_len := 0.0) -> void:
	if _enemy_voices >= MAX_ENEMY_VOICES or not is_instance_valid(source):
		return
	var p3 := AudioStreamPlayer3D.new()
	p3.bus = _bus("Effects")
	p3.stream = _load(path)
	p3.volume_db = volume_db
	p3.pitch_scale = pitch
	p3.unit_size = 6.0
	p3.max_distance = 30.0
	source.add_child(p3)                             # same 3D world as the camera that hears it
	_enemy_voices += 1
	var done := func() -> void:
		if is_instance_valid(p3) and not p3.is_queued_for_deletion():
			_enemy_voices -= 1
			p3.queue_free()
	p3.finished.connect(done)
	p3.tree_exiting.connect(func() -> void:          # the enemy was removed mid-sound
		if not p3.is_queued_for_deletion():
			_enemy_voices -= 1)
	if max_len > 0.0:
		get_tree().create_timer(max_len, false).timeout.connect(done)
	p3.play()


# ---------- FOOTSTEPS ----------
func _update_footsteps() -> void:
	var walking := false
	if not get_tree().paused:
		var p := get_tree().get_first_node_in_group("players")
		if p != null and p.get("walking") == true and p is CharacterBody3D and p.is_on_floor():
			var h = p.get("health")
			walking = h == null or h.current_health > 0.0
	if walking:
		if not _steps.playing:
			_steps.play()
		_steps.stream_paused = false
	elif _steps.playing:
		_steps.stream_paused = true


# ---------- HELPERS ----------
func _player(bus_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = _bus(bus_name)
	add_child(p)
	return p


## The bus if the layout has it, else Master (so a missing bus never silences a sound).
func _bus(bus_name: String) -> StringName:
	return StringName(bus_name) if AudioServer.get_bus_index(bus_name) >= 0 else &"Master"


func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
		if _cache[path] == null:
			push_warning("SoundManager: missing sound %s" % path)
	return _cache[path]
