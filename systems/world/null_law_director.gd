class_name NullLawDirector
extends Node
## Put one in an Act IV zone: the Null rewrites one of AXIOM's rules at a time (NullLaws). A
## law holds for `law_time` seconds; `warn_time` before it ends, the banner names the next one
## so the player can swap script sets, and Vesper says what she hears. The law clears when
## the zone unloads, so towns and other acts are never touched. Its banner goes on the HUD's
## StimLayer (beside the ThreatPanel, outside the retro-filtered game view), and is freed with it.

const NullLawsRef := preload("res://systems/world/null_laws.gd")
const BannerScript := preload("res://systems/world/null_law_banner.gd")
const TouchScript := preload("res://systems/world/null_law_touch.gd")
const COL_ECHO := Color(0.85, 0.6, 1.0)
const COL_DRAIN := Color(0.45, 0.6, 1.0)
## Seconds between sweeps that give new enemies (summons, waves) their NullLawTouch.
const TOUCH_EVERY := 1.0
const CALLOUT_GAP := 1.2
const COL_VESPER := Color(0.78, 0.55, 1.0)

## Seconds after arriving before the first law (its warning included).
@export var first_delay := 16.0
## Seconds each law holds.
@export var law_time := 80.0
## Seconds of warning before a rewrite.
@export var warn_time := 8.0
## Which laws this zone uses (NullLaws.LAWS ids). Empty = all of them.
@export var laws: Array[String] = []

var _law := ""
var _next := ""
var _left := 0.0
var _span := 1.0
var _warned := false
var _banner: Control
var _touch_left := 0.0
var _player_hp: HealthComponent
var _echoing := false                     # an echo hit is landing: it doesn't echo again
var _callout_at := -10.0


func _ready() -> void:
	NullLawsRef.law = ""
	_left = first_delay
	_span = first_delay
	_banner = BannerScript.new()
	_banner.name = "NullLawBanner"
	var hud := get_tree().root.find_child("StimLayer", true, false)
	if hud != null:
		hud.add_child(_banner)
	else:
		add_child(_banner)                    # no HUD (a test scene): it still shows, filtered


func _exit_tree() -> void:
	NullLawsRef.law = ""
	if is_instance_valid(_player_hp) and _player_hp.damage_taken.is_connected(_on_player_hit):
		_player_hp.damage_taken.disconnect(_on_player_hit)
	if is_instance_valid(_banner) and _banner.get_parent() != self:
		_banner.queue_free()                   # it lives on the HUD, not under this zone


## The law in force now ("" = none yet).
func current() -> String:
	return _law


func _process(delta: float) -> void:
	_touch_left -= delta
	if _touch_left <= 0.0:
		_touch_left = TOUCH_EVERY
		_touch_enemies()
		_hook_player()
	_left -= delta
	if not _warned and _left <= warn_time:
		_warned = true
		_next = _pick()
		_banner.warn(_next)
		if _law == "":
			QuestItems.toast(get_tree(), "VESPER: \"Listen. It's about to rewrite something.\"", COL_VESPER)
	_banner.set_left(_left / maxf(_span, 0.01) if not _warned else _left / maxf(warn_time, 0.01))
	if _left > 0.0:
		return
	_law = _next
	NullLawsRef.law = _law
	_left = law_time
	_span = law_time
	_warned = false
	_banner.show_law(_law)
	_banner.announce(_law)
	QuestItems.toast(get_tree(), "NULL LAW: %s\nVESPER: \"%s\"" % [NullLawsRef.name_of(_law), NullLawsRef.vesper_of(_law)], COL_VESPER)
	GameEvents.report("null_law", _law)


# ---------- THE LAWS IN A FIGHT ----------
## Every enemy here gets a NullLawTouch (the laws that change how hard the player hits).
func _touch_enemies() -> void:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if e is Node3D and "traits" in e and not e.has_meta(&"null_law_touch"):
			e.set_meta(&"null_law_touch", true)
			EnemySpawner._add_trait(e, TouchScript, "null_law_touch")


func _hook_player() -> void:
	var player := get_tree().get_first_node_in_group("players")
	var hp := player.get("health") as HealthComponent if player != null else null
	if hp == null or hp == _player_hp:
		return
	if is_instance_valid(_player_hp) and _player_hp.damage_taken.is_connected(_on_player_hit):
		_player_hp.damage_taken.disconnect(_on_player_hit)
	_player_hp = hp
	hp.damage_taken.connect(_on_player_hit)


## The laws that change what a hit on the player does.
func _on_player_hit(amount: float) -> void:
	if amount <= 0.0 or _player_hp == null or _player_hp.current_health <= 0.0:
		return
	var player := _player_hp.get_parent() as Node3D
	if NullLawsRef.law == "loops_plus_one" and not _echoing:
		_echo(amount * NullLawsRef.ECHO_SHARE)
	elif NullLawsRef.law == "counters_forget" and player != null:
		var mana := player.get("mana") as ManaComponent
		if mana != null:
			var drain := minf(mana.get_max_mana() * NullLawsRef.MANA_DRAIN, mana.current_mana)
			if drain > 0.0:
				mana.spend(drain)
				_callout(player, "FORGOTTEN -%d MANA" % roundi(drain), COL_DRAIN)


## LOOPS RUN ONCE MORE: the hit lands again, a moment later.
func _echo(amount: float) -> void:
	await get_tree().create_timer(NullLawsRef.ECHO_DELAY).timeout
	if not is_instance_valid(_player_hp) or _player_hp.current_health <= 0.0 or NullLawsRef.law != "loops_plus_one":
		return
	_echoing = true
	_player_hp.take_damage(amount, true)       # already past armour the first time
	_echoing = false
	var player := _player_hp.get_parent() as Node3D
	if player != null:
		_callout(player, "LOOPED x2", COL_ECHO)


func _callout(player: Node3D, text: String, col: Color) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _callout_at < CALLOUT_GAP:
		return
	_callout_at = now
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers != null:
		numbers.pop_text(player.global_position + Vector3.UP * 2.4, text, col, 1.0, EnemyTrait.HINT_SECONDS)


func _pick() -> String:
	var pool: Array = laws.duplicate() if not laws.is_empty() else NullLawsRef.LAWS.keys()
	if pool.size() > 1:
		pool.erase(_law)                     # never the same law twice in a row
	return str(pool[randi() % pool.size()])
