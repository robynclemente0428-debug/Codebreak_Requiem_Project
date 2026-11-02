class_name RollbackWatch
extends Node
## ROLLBACK SUPPORT (any skill). While a skill with Rollback is socketed, this node keeps a short
## history of the owner's life. When life drops below `rollback_trigger` (0.3 = 30%) it is
## restored to what it was `rollback_window` seconds ago, then waits `rollback_cooldown` seconds.
## It doesn't need the skill to be cast: socketing the gem is enough.
## Flags (SkillGemRegistry._support_flag_modifiers, scripted through Rollback's DEFENSE knobs in
## always: rules): rollback_window, rollback_cooldown, rollback_trigger.
## Several skills with Rollback share one watch: the longest window and shortest cooldown win.

const SUPPORT_ID := "rollback_support"
const SAMPLE_EVERY := 0.2
const KEEP_SECONDS := 8.0
const COL := Color(0.45, 0.85, 1.0)

var skills: SkillComponent
var window := 3.0
var cooldown := 20.0
var trigger := 0.3
var _history: Array = []        # [msec, life], oldest first
var _sample_t := 0.0
var _ready_at := 0


## Adds, updates or removes the watch to match the sockets (SkillComponent calls this).
static func sync(component: SkillComponent) -> void:
	var watch := component.get_node_or_null("RollbackWatch") as RollbackWatch
	var found := false
	var w := 0.0
	var cd := INF
	var trig := 0.0
	for s in component.sockets:
		if s.skill == null or not s.supports.any(func(it: ItemInstance) -> bool:
				return it.definition.support_gem != null and it.definition.support_gem.id == SUPPORT_ID):
			continue
		found = true
		w = maxf(w, s.skill.get_flag("rollback_window"))
		cd = minf(cd, s.skill.get_flag("rollback_cooldown"))
		trig = maxf(trig, s.skill.get_flag("rollback_trigger"))
	if not found:
		if watch != null:
			watch.queue_free()
		return
	if watch == null:
		watch = RollbackWatch.new()
		watch.name = "RollbackWatch"
		watch.skills = component
		component.add_child(watch)
	watch.window = clampf(w, 0.5, KEEP_SECONDS - 1.0)
	watch.cooldown = maxf(cd, 4.0)
	watch.trigger = clampf(trig, 0.1, 0.9)


## Seconds until it can trigger again (0 = ready), for the HUD.
func seconds_left() -> float:
	return maxf((_ready_at - Time.get_ticks_msec()) / 1000.0, 0.0)


func _process(delta: float) -> void:
	var hp := _health()
	if hp == null or hp.current_health <= 0.0:
		_history.clear()
		return
	var now := Time.get_ticks_msec()
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = SAMPLE_EVERY
		_history.append([now, hp.current_health])
		while not _history.is_empty() and now - int(_history[0][0]) > KEEP_SECONDS * 1000.0:
			_history.pop_front()
	var max_hp := hp.stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	if now < _ready_at or max_hp <= 0.0 or hp.current_health / max_hp >= trigger:
		return
	var back := _life_at(now - int(window * 1000.0))
	if back <= hp.current_health:
		return                          # nothing better to roll back to
	hp.heal(back - hp.current_health)
	_ready_at = now + int(cooldown * 1000.0)
	_history.clear()
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	var owner_3d := skills.get_parent() as Node3D
	if numbers != null and owner_3d != null:
		numbers.pop_text(owner_3d.global_position + Vector3.UP * 2.4, "ROLLBACK", COL, 1.1)


## Life at (or just after) the given time; the oldest sample if the history is shorter.
func _life_at(msec: int) -> float:
	for entry in _history:
		if int(entry[0]) >= msec:
			return float(entry[1])
	return float(_history[-1][1]) if not _history.is_empty() else 0.0


func _health() -> HealthComponent:
	return skills.get_parent().get("health") as HealthComponent if skills != null else null
