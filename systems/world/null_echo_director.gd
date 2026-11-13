class_name NullEchoDirector
extends Node
## Put one in an Act IV zone, named "NullEchoes": the Null copies the player there (NullEcho).
## The dungeon asks it how many Null Echoes to place (DungeonPopulator.place_echoes, from
## Dungeon._spawn_enemies), so they're tracked like any enemy: killed ones stay dead in that
## instance. Vesper says what she hears: when you arrive, when an Echo copies you, when one
## crashes on a routine that isn't there. Act IV's thread, in place of the old Null Laws.

const ECHO_DEF := "res://data/enemies/null_echo.tres"
const COL_VESPER := Color(0.78, 0.55, 1.0)
## Seconds between Vesper's lines about copies and crashes.
const VESPER_GAP := 22.0

## Null Echoes in each ordinary room (the Mirror Forge: 2).
@export var per_room := 1
## How many different skills each Echo copies (the Weaver's Loom: 2).
@export var copies := 1
## The Mirror Forge: a champion Echo in the room farthest from the way in, whose copy also calls
## every one of your routines.
@export var champion := false

static var _greeted := {}                 # zone scene path -> true: Vesper's arrival line, once a session
var _spoke_at := -100.0


func _ready() -> void:
	GameEvents.happened.connect(_on_event)
	_greet.call_deferred()


func _exit_tree() -> void:
	if GameEvents.happened.is_connected(_on_event):
		GameEvents.happened.disconnect(_on_event)


func echo_definition() -> EnemyDefinition:
	return load(ECHO_DEF) as EnemyDefinition


func _greet() -> void:
	var zone := get_parent().scene_file_path if get_parent() != null else ""
	if _greeted.has(zone):
		return
	_greeted[zone] = true
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree():
		return
	var line := "\"They copy the first thing they see you do. Show them something you don't mind losing.\""
	if copies > 1:
		line = "\"These ones watch longer. Two of your skills each, before they've seen enough.\""
	elif champion:
		line = "\"Something in here calls every routine you have. All of them, at once.\""
	_vesper(line, true)


func _on_event(kind: String, target: String, _amount: int) -> void:
	match kind:
		NullEcho.COPIED_EVENT:
			_vesper("\"It took your %s. It's saying it back. Wrong, but it's saying it.\"" % target.replace("_", " "))
		NullEcho.CRASH_EVENT:
			_vesper("\"It called %s() and got nothing back. Hear that? That's a copy finding out.\"" % target)


func _vesper(line: String, always := false) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not always and now - _spoke_at < VESPER_GAP:
		return
	_spoke_at = now
	QuestItems.toast(get_tree(), "VESPER: %s" % line, COL_VESPER)
