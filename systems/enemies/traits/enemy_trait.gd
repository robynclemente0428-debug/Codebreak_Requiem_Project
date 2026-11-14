class_name EnemyTrait
extends Node
## A behaviour an enemy modifier adds (EnemyModifierDefinition.on_spawn_script). EnemySpawner
## adds one as a child of the enemy and lists it in enemy.traits. Traits are what make one
## script better than another in a dungeon (see DungeonThreats):
##   Firewalled  shrugs off part of every hit: few big hits beat many small ones
##   Reflector   zaps the attacker on every hit: fast attacks hurt the player
##   Swarmling   small and weak, but there are twice as many: area skills shine

const LockBannerUI := preload("res://scenes/ui/player_ui/lock_banner/lock_banner.gd")   # LockBanner, by path

## ---- How a lock shows itself ----
## A trait is a lock (a puzzle) when its script has a LOCK_NAME constant. Every lock then shows
## the same way everywhere: a tag over the enemy's head (LockTags), a row on the hover plate
## (EnemyHover), the lock banner (LockBanner, bosses) and the quest tracker. Optional constants:
##   HINT        String  how to beat it (the plate shows it from rank OPERATOR, like threat hints)
##   LOCK_COLOR  Color   the tag's colour
##   LOCK_SHAPE  String  the tag's icon, so it reads without colour: "ring", "split", "hex",
##                       "diamond" or "square" (LockTags.draw_icon)
##   LOCK_AURA   int     the effect on its body, an EnemySilhouette.AURA_* (bosses keep theirs)
##   BANNER      bool    false: never on the lock banner (for locks that pop on every hit)
## tag_state() says what the lock knows right now (ECHO's learned pattern...). UI reads it
## through shown_tag_state(), which is right on a co-op guest's copy too.
##
## ---- Co-op ----
## The host's trait is the real one: it judges every player's hits (Coop._e_hit, from HitFacts).
## A guest's copy (enemy.is_remote) runs none of its own logic (Coop "A COPY RUNS NO LOGIC") and
## only shows what the host's does: what it pops and says ("trait_say"), its tag ("trait_tag"),
## and whatever a subclass sends (a port opening, a form). Messages name the trait by its script
## (coop_key). A trait that runs its own co-op sets COOP_AWARE := true and is left alone (the
## Warden's ChallengeLock).
const TAG_COLOR := Color(0.3, 0.95, 1.0)

var enemy: Node3D
var _popped_at := -10.0
var _spoke_at := -10.0                     # when it last said something: its tag flashes
static var _consts := {}                   # script -> its lock constants (with its bases')
var _shown_tag := ""                       # a guest's copy: the host's tag_state()
var _relaying := false                     # a guest's copy: showing what the host's said


## Called by EnemySpawner once the enemy is built.
func setup(p_enemy: Node3D) -> void:
	enemy = p_enemy
	if is_lock():
		_apply_aura.call_deferred()        # once the populator has marked act bosses


## True when this trait is a puzzle (its script has LOCK_NAME).
func is_lock() -> bool:
	return lock_name() != ""


func lock_name() -> String:
	return str(_lock_const("LOCK_NAME", ""))


func lock_hint() -> String:
	return str(_lock_const("HINT", ""))


func lock_color() -> Color:
	var c = _lock_const("LOCK_COLOR", TAG_COLOR)
	return c if c is Color else TAG_COLOR


func lock_shape() -> String:
	return str(_lock_const("LOCK_SHAPE", "square"))


## What the lock knows right now, short enough for the tag ("" = nothing to say yet).
func tag_state() -> String:
	return ""


## Seconds since the lock last said something (pop / say).
func spoke_ago() -> float:
	return Time.get_ticks_msec() / 1000.0 - _spoke_at


## A constant of this trait's script or one of its bases, or `default`.
func _lock_const(key: String, default: Variant) -> Variant:
	var s: Script = get_script()
	if s == null:
		return default
	if not _consts.has(s):
		var all := {}
		var cur := s
		while cur != null:
			var own := cur.get_script_constant_map()
			for k in own:
				if not all.has(k):
					all[k] = own[k]
			cur = cur.get_base_script()
		_consts[s] = all
	return _consts[s].get(key, default)


## The lock's effect on the enemy's body (EnemySilhouette.cover_aura). Bosses keep their own
## look (and a boss lock's port glow), so only ordinary enemies get one, the first lock's.
func _apply_aura() -> void:
	if not is_instance_valid(enemy) or enemy.get_meta(&"act_boss", false) or enemy.has_meta(&"lock_aura"):
		return
	if has_method("open_port"):            # a boss lock (PortLock) glows its own way
		return
	var aura := int(_lock_const("LOCK_AURA", 0))
	var model := enemy.get("model") as Node
	if aura <= 0 or model == null:
		return
	enemy.set_meta(&"lock_aura", aura)
	EnemySilhouette.cover_aura(model, aura, lock_color())


## Before the hit lands: change info.damage or set info.cancelled.
func modify_incoming(_info: HitInfo) -> void:
	pass


## After the hit landed (info.landed is true).
func after_hit(_info: HitInfo) -> void:
	pass


## One of this enemy's own skills is about to hit `info.target` (before the damage is applied).
func on_outgoing(_info: HitInfo) -> void:
	pass


## Seconds a trait's text (a boss lock's hint) stays over the enemy: longer than a damage number,
## so it can be read mid-fight.
const HINT_SECONDS := 2.0


## Floating text over the enemy, at most once per `gap` seconds so fast attacks don't spam it.
func pop(text: String, col: Color, gap := 0.6) -> void:
	if is_copy() and not _relaying:
		return                                      # a copy only says what the host's says
	var now := Time.get_ticks_msec() / 1000.0
	if now - _popped_at < gap or not is_instance_valid(enemy):
		return
	_popped_at = now
	_spoke_at = now
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers != null:
		numbers.pop_text(enemy.global_position + Vector3.UP * 2.2, text, col, 1.0, HINT_SECONDS)
	LockBannerUI.report(self, text, col)            # a boss lock: also on the lock banner (LockBanner)
	_tell_copies("trait_say", [0, text, col, 1.0])


## Floating text over the enemy, every time (for messages that must not be skipped).
func say(text: String, col: Color, size_mult := 1.0) -> void:
	if is_copy() and not _relaying:
		return
	if not is_instance_valid(enemy):
		return
	_spoke_at = Time.get_ticks_msec() / 1000.0
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers != null:
		numbers.pop_text(enemy.global_position + Vector3.UP * 2.6, text, col, size_mult * 1.2, HINT_SECONDS)
	LockBannerUI.report(self, text, col)            # a boss lock: also on the lock banner (LockBanner)
	_tell_copies("trait_say", [1, text, col, size_mult])


# ---------- CO-OP ----------
## This is a guest's copy of the host's trait: it shows what the host's does, it doesn't decide.
func is_copy() -> bool:
	return is_instance_valid(enemy) and enemy.get("is_remote") == true and not coop_aware()


## The trait runs its own co-op (COOP_AWARE): Coop leaves it running on a copy.
func coop_aware() -> bool:
	return bool(_lock_const("COOP_AWARE", false))


## What the UI shows on its tag: its own tag_state(), or on a copy the host's.
func shown_tag_state() -> String:
	return _shown_tag if is_copy() else tag_state()


## Names this trait in messages: its script (an enemy has one trait of each kind).
func coop_key() -> String:
	var s := get_script() as Script
	return s.resource_path if s != null else ""


## The host's trait: send `what` to this trait on every guest's copy (args get coop_key in front).
func _tell_copies(what: String, args: Array) -> void:
	if Coop.in_game and Coop.is_host() and not coop_aware() and is_instance_valid(enemy):
		Coop.enemy_send(enemy, what, [coop_key()] + args)


## A message for this enemy's parts (Coop.enemy_send). A copy takes the host's word; a subclass
## with messages of its own handles them, then calls super for the rest. `args[0]` = coop_key.
func coop_message(what: String, args: Array, from: int) -> void:
	if from != 1 or not is_copy() or args.is_empty() or str(args[0]) != coop_key():
		return
	match what:
		"trait_say":
			if args.size() < 5 or not args[3] is Color:
				return
			_relaying = true
			if int(args[1]) == 0:
				pop(str(args[2]).left(120), args[3], 0.0)
			else:
				say(str(args[2]).left(120), args[3], clampf(float(args[4]), 0.5, 2.0))
			_relaying = false
		"trait_tag":
			_shown_tag = str(args[1]).left(48) if args.size() > 1 else ""
		_:
			_copy_message(what, args.slice(1))


## A subclass's own messages on a copy (`args` without the key). See _tell_copies.
func _copy_message(_what: String, _args: Array) -> void:
	pass


## The nearest living player's character within `reach` metres, or null. Every player counts:
## in co-op the host's "players" group holds every player's character in this area.
func player_within(reach: float) -> Node3D:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return null
	var best: Node3D = null
	var best_d := reach
	for p in get_tree().get_nodes_in_group("players"):
		var body := p as Node3D
		var hp := p.get("health") as HealthComponent
		if body == null or (hp != null and hp.current_health <= 0.0):
			continue
		var d := body.global_position.distance_to(enemy.global_position)
		if d <= best_d:
			best = body
			best_d = d
	return best


func max_health() -> float:
	var stats := enemy.get("stats") as StatComponent
	return stats.get_stat(StatTypes.Stat.MAX_HEALTH) if stats != null else 0.0
