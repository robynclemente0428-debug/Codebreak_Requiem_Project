class_name BreakpointSupport
extends SupportBehavior

const META_PREFIX := "breakpoint_"
const LAST_TARGET_PREFIX := "breakpoint_last_"
const MARK_NODE := "BreakpointMark"
const COL_MARK := Color(1.0, 0.55, 0.15)
const COL_BURST := Color(1.0, 0.3, 0.1)


func modify_hit(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	if target.is_in_group(&"breakables"):
		return
	var n := mark_count(cast.caster, target) + 1
	if n <= 1:
		return
	if n >= _hits_needed(cast, hit):
		hit.damage *= 1.0 + maxf(hit.flag("breakpoint_burst"), 0.0)
		hit.set_meta(&"breakpoint_consume", true)
	else:
		hit.damage *= 1.0 + maxf(hit.flag("breakpoint_bonus"), 0.0)
	hit.set_meta(&"breakpoint_n", n)


func on_hit(cast: SkillCast, target: Node, hit: HitInfo) -> void:
	if target.is_in_group(&"breakables"):
		return
	var owner := VariableStoreSupport.owner_of(cast.caster)
	if owner == null:
		return
	owner.set_meta(_last_key(owner), target.get_instance_id())
	var key := _key(owner)
	if hit.get_meta(&"breakpoint_consume", false):
		target.remove_meta(key)
		_remove_marker(target)
		if target is Node3D:
			ImpactEffect.spawn(cast.effect_parent(), (target as Node3D).global_position + Vector3.UP,
					1.1, COL_BURST, COL_MARK)
		return
	if hit.killed:
		target.remove_meta(key)
		_remove_marker(target)
		return
	var n: int = hit.get_meta(&"breakpoint_n", 1)
	target.set_meta(key, {"n": n, "msec": Time.get_ticks_msec(),
			"duration": maxf(cast.flag("breakpoint_duration"), 0.5)})
	_show_marker(target, n, _hits_needed(cast, hit), maxf(cast.flag("breakpoint_duration"), 0.5), key)


static func mark_count(caster: Node, target: Node) -> int:
	var owner := VariableStoreSupport.owner_of(caster)
	if owner == null or not is_instance_valid(target):
		return 0
	var key := _key(owner)
	if not target.has_meta(key):
		return 0
	var m: Dictionary = target.get_meta(key)
	if (Time.get_ticks_msec() - int(m["msec"])) / 1000.0 > float(m["duration"]):
		target.remove_meta(key)
		_remove_marker(target)
		return 0
	return int(m["n"])


static func is_marked(caster: Node, target: Node) -> bool:
	return is_instance_valid(target) and not SkillBehavior.is_dead(target) \
			and mark_count(caster, target) > 0


static func last_target(caster: Node) -> Node:
	var owner := VariableStoreSupport.owner_of(caster)
	if owner == null:
		return null
	var id: int = owner.get_meta(_last_key(owner), 0)
	var n := instance_from_id(id) if id != 0 else null
	return n as Node if is_instance_valid(n) else null


func _hits_needed(cast: SkillCast, hit: HitInfo = null) -> int:
	return maxi(int(round(hit.flag("breakpoint_hits") if hit != null else cast.flag("breakpoint_hits"))), 2)


static func _key(owner: Node) -> String:
	return META_PREFIX + str(owner.get_instance_id())


static func _last_key(owner: Node) -> String:
	return LAST_TARGET_PREFIX + str(owner.get_instance_id())


static func _show_marker(target: Node, n: int, needed: int, duration: float, key: String) -> void:
	if not target is Node3D:
		return
	var label := target.get_node_or_null(MARK_NODE) as Label3D
	if label == null:
		label = Label3D.new()
		label.name = MARK_NODE
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0011
		label.font_size = 26
		label.outline_size = 8
		label.outline_modulate = Color(0, 0, 0, 0.9)
		label.modulate = COL_MARK
		label.position = Vector3.UP * 2.3
		target.add_child(label)
		var timer := Timer.new()
		timer.name = "Expire"
		timer.one_shot = true
		label.add_child(timer)
		timer.timeout.connect(func():
			if is_instance_valid(target):
				target.remove_meta(key)
			label.queue_free())
	(label.get_node("Expire") as Timer).start(duration)
	label.text = "BREAKPOINT %d/%d" % [n, needed]
	label.modulate = COL_BURST if n >= needed - 1 else COL_MARK


static func _remove_marker(target: Node) -> void:
	if not is_instance_valid(target):
		return
	var label := target.get_node_or_null(MARK_NODE)
	if label != null:
		label.queue_free()
