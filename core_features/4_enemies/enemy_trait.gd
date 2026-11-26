class_name EnemyTrait
extends Node

const LockBannerUI := preload("res://scenes/ui/player_ui/lock_banner/lock_banner.gd")

const TAG_COLOR := Color(0.3, 0.95, 1.0)

var enemy: Node3D
var _popped_at := -10.0
var _spoke_at := -10.0
static var _consts := {}
var _shown_tag := ""
var _relaying := false


func setup(p_enemy: Node3D) -> void:
	enemy = p_enemy
	if is_lock():
		_apply_aura.call_deferred()


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


func tag_state() -> String:
	return ""


func spoke_ago() -> float:
	return Time.get_ticks_msec() / 1000.0 - _spoke_at


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


func _apply_aura() -> void:
	if not is_instance_valid(enemy) or enemy.get_meta(&"act_boss", false) or enemy.has_meta(&"lock_aura"):
		return
	if has_method("open_port"):
		return
	var aura := int(_lock_const("LOCK_AURA", 0))
	var model := enemy.get("model") as Node
	if aura <= 0 or model == null:
		return
	enemy.set_meta(&"lock_aura", aura)
	EnemySilhouette.cover_aura(model, aura, lock_color())


func modify_incoming(_info: HitInfo) -> void:
	pass


func after_hit(_info: HitInfo) -> void:
	pass


func on_outgoing(_info: HitInfo) -> void:
	pass


const HINT_SECONDS := 2.0


func pop(text: String, col: Color, gap := 0.6) -> void:
	if is_copy() and not _relaying:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _popped_at < gap or not is_instance_valid(enemy):
		return
	_popped_at = now
	_spoke_at = now
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers != null:
		numbers.pop_text(enemy.global_position + Vector3.UP * 2.2, text, col, 1.0, HINT_SECONDS)
	LockBannerUI.report(self, text, col)
	_tell_copies("trait_say", [0, text, col, 1.0])


func say(text: String, col: Color, size_mult := 1.0) -> void:
	if is_copy() and not _relaying:
		return
	if not is_instance_valid(enemy):
		return
	_spoke_at = Time.get_ticks_msec() / 1000.0
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers != null:
		numbers.pop_text(enemy.global_position + Vector3.UP * 2.6, text, col, size_mult * 1.2, HINT_SECONDS)
	LockBannerUI.report(self, text, col)
	_tell_copies("trait_say", [1, text, col, size_mult])


func is_copy() -> bool:
	return is_instance_valid(enemy) and enemy.get("is_remote") == true and not coop_aware()


func coop_aware() -> bool:
	return bool(_lock_const("COOP_AWARE", false))


func shown_tag_state() -> String:
	return _shown_tag if is_copy() else tag_state()


func coop_key() -> String:
	var s := get_script() as Script
	return s.resource_path if s != null else ""


func _tell_copies(what: String, args: Array) -> void:
	if Coop.in_game and Coop.is_host() and not coop_aware() and is_instance_valid(enemy):
		Coop.enemy_send(enemy, what, [coop_key()] + args)


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


func _copy_message(_what: String, _args: Array) -> void:
	pass


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
